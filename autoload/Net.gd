extends Node
## Peer-to-peer multiplayer over WebRTC. One player hosts and gets a room code,
## the other joins with it. Positions, emotes, settings and photos travel as RPCs.

signal status(text: String)
signal failed(reason: String)
signal hosting_started(code: String)
signal welcome_received                       # guest: host told us the world
signal partner_joined(peer_id: int)
signal partner_left(peer_id: int)
signal state_received(peer_id: int, pos: Vector3, yaw: float, pitch: float, flags: int)
signal event_received(peer_id: int, kind: String, data: Dictionary)
signal photo_progress(from_name: String, done: int, total: int)

const PeerSignaling := preload("res://autoload/PeerSignaling.gd")
const ID_PREFIX := "polaroidpals-v1-"
const ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
	# Add a TURN server here if strict networks (e.g. campus wifi) block P2P:
	# {"urls": ["turn:your.turn.server:3478"], "username": "...", "credential": "..."},
]
const CODE_WORDS := [
	"MOSS", "FERN", "PINE", "LAKE", "MOCHI", "TEA", "PLUM", "CLOUD", "BIRCH",
	"LILY", "HONEY", "MAPLE", "OTTER", "PEACH", "SUNNY", "COZY", "BERRY", "WREN",
]
const CHUNK := 16000
const CONNECT_TIMEOUT := 25.0

enum Mode { OFFLINE, HOSTING, JOINING, CONNECTED }

var mode := Mode.OFFLINE
var room_code := ""
var _sig: Node
var _rtc: WebRTCMultiplayerPeer
var _conns := {}               # signaling src id -> WebRTCPeerConnection
var _pending_cands := []       # guest: candidates that arrived before the answer
var _remote_set := false
var _host_sig_id := ""
var _join_timer := 0.0
var _send_queue: Array = []    # outgoing photo chunks
var _incoming := {}            # photo id -> {meta, chunks, got}


func _ready() -> void:
	_sig = PeerSignaling.new()
	_sig.name = "Signaling"
	add_child(_sig)
	_sig.opened.connect(_on_sig_opened)
	_sig.id_taken.connect(_on_sig_id_taken)
	_sig.message.connect(_on_sig_message)
	_sig.closed.connect(_on_sig_closed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return mode == Mode.CONNECTED or (mode == Mode.HOSTING and _rtc != null)


func has_partner() -> bool:
	return multiplayer.multiplayer_peer != null and _rtc != null and multiplayer.get_peers().size() > 0


func is_host() -> bool:
	return _rtc != null and multiplayer.is_server()


func my_peer_id() -> int:
	return multiplayer.get_unique_id() if _rtc != null else 1


# ------------------------------------------------------------------ hosting

func host(code := "") -> void:
	leave()
	mode = Mode.HOSTING
	_rtc = WebRTCMultiplayerPeer.new()
	_rtc.create_server()
	multiplayer.multiplayer_peer = _rtc
	if code != "":
		room_code = code
		_sig.start(ID_PREFIX + code.replace("-", ""))
	else:
		_new_code()
	status.emit("Opening a room…")


func _new_code() -> void:
	room_code = "%s-%02d" % [CODE_WORDS[randi() % CODE_WORDS.size()], randi() % 100]
	_sig.start(ID_PREFIX + room_code.replace("-", ""))


# ------------------------------------------------------------------ joining

func join(code: String) -> void:
	leave()
	code = code.strip_edges().to_upper().replace(" ", "-")
	if code.is_empty():
		failed.emit("Type the room code your partner sees")
		return
	room_code = code
	mode = Mode.JOINING
	_host_sig_id = ID_PREFIX + code.replace("-", "")
	_join_timer = CONNECT_TIMEOUT
	status.emit("Looking for room %s…" % code)
	_sig.start(ID_PREFIX + "g%x%x" % [randi(), randi()])


func leave() -> void:
	_sig.stop()
	for c in _conns.values():
		c.close()
	_conns.clear()
	_pending_cands.clear()
	_remote_set = false
	_send_queue.clear()
	_incoming.clear()
	if _rtc:
		_rtc.close()
	_rtc = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.partners.clear()
	mode = Mode.OFFLINE
	room_code = ""


# ------------------------------------------------------------------ signaling

func _on_sig_opened() -> void:
	print("[net] signaling open as ", _sig.my_id)
	if mode == Mode.HOSTING:
		hosting_started.emit(room_code)
		status.emit("Room %s is open" % room_code)
	elif mode == Mode.JOINING:
		_start_guest_connection()


func _on_sig_id_taken() -> void:
	if mode == Mode.HOSTING:
		_new_code()
	else:
		failed.emit("Signaling id clash — try again")


func _on_sig_closed(reason: String) -> void:
	if mode == Mode.JOINING:
		_fail(reason)
	elif mode == Mode.HOSTING and not has_partner():
		status.emit("Room closed: %s" % reason)


func _make_conn(sig_src: String) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": ICE_SERVERS})
	conn.session_description_created.connect(_on_local_sdp.bind(conn, sig_src))
	conn.ice_candidate_created.connect(_on_local_candidate.bind(sig_src))
	_conns[sig_src] = conn
	return conn


## The public PeerJS broker validates payloads against the official client's
## schema (and drops the socket otherwise), so we speak its exact dialect.
func _on_local_sdp(type: String, sdp: String, conn: WebRTCPeerConnection, dst: String) -> void:
	conn.set_local_description(type, sdp)
	var cid := "dc_" + room_code.replace("-", "").to_lower()
	if type == "offer":
		_sig.send("OFFER", dst, {
			"sdp": {"type": "offer", "sdp": sdp}, "type": "data", "connectionId": cid,
			"metadata": {"pid": my_peer_id()}, "label": cid, "reliable": true, "serialization": "binary"})
	else:
		_sig.send("ANSWER", dst, {"sdp": {"type": "answer", "sdp": sdp}, "type": "data", "connectionId": cid})


func _on_local_candidate(mid: String, idx: int, cand: String, dst: String) -> void:
	var cid := "dc_" + room_code.replace("-", "").to_lower()
	_sig.send("CANDIDATE", dst, {
		"candidate": {"candidate": cand, "sdpMid": mid, "sdpMLineIndex": idx},
		"type": "data", "connectionId": cid})


static func _sdp_of(p: Dictionary) -> String:
	var s = p.get("sdp", "")
	return str(s.get("sdp", "")) if s is Dictionary else str(s)


func _start_guest_connection() -> void:
	_rtc = WebRTCMultiplayerPeer.new()
	var my_id := randi_range(2, 1 << 30)
	_rtc.create_client(my_id)
	multiplayer.multiplayer_peer = _rtc
	var conn := _make_conn(_host_sig_id)
	_rtc.add_peer(conn, 1)
	conn.create_offer()
	status.emit("Knocking on room %s…" % room_code)


func _on_sig_message(type: String, src: String, p: Dictionary) -> void:
	print("[net] <- ", type, " from ", src.right(8))
	match type:
		"OFFER":
			if mode != Mode.HOSTING and mode != Mode.CONNECTED:
				return
			if not is_host() or _conns.has(src):
				return
			var md = p.get("metadata", {})
			var pid := int(md.get("pid", 0)) if md is Dictionary else 0
			if pid < 2:
				return
			var conn := _make_conn(src)
			_rtc.add_peer(conn, pid)
			conn.set_remote_description("offer", _sdp_of(p))
			status.emit("Partner found, connecting…")
		"ANSWER":
			if _conns.has(src):
				_conns[src].set_remote_description("answer", _sdp_of(p))
				_remote_set = true
				for c in _pending_cands:
					_conns[src].add_ice_candidate(c[0], c[1], c[2])
				_pending_cands.clear()
				status.emit("Room found, shaking hands…")
		"CANDIDATE":
			var c = p.get("candidate", {})
			if not (c is Dictionary):
				return
			var cand := [str(c.get("sdpMid", "")), int(c.get("sdpMLineIndex", 0)), str(c.get("candidate", ""))]
			if _conns.has(src):
				if mode == Mode.JOINING and not _remote_set:
					_pending_cands.append(cand)
				else:
					_conns[src].add_ice_candidate(cand[0], cand[1], cand[2])
		"EXPIRE":
			if mode == Mode.JOINING:
				_fail("No room called %s — check the code" % room_code)
		"LEAVE":
			if _conns.has(src) and mode == Mode.JOINING:
				_fail("The room closed")


func _fail(reason: String) -> void:
	print("[net] failed: ", reason)
	leave()
	failed.emit(reason)


func _process(delta: float) -> void:
	if mode == Mode.JOINING:
		_join_timer -= delta
		if _join_timer <= 0.0:
			_fail("Couldn't connect. The room may not exist, or this network blocks peer-to-peer.")
	_pump_photos()


# ------------------------------------------------------------------ peers

func _on_peer_connected(id: int) -> void:
	print("[net] peer connected ", id)
	if is_host():
		GameState.partners[id] = {"name": "Partner", "color": Color.WHITE}
		_welcome.rpc_id(id, GameState.settings_dict(), GameState.player_name, GameState.player_color)
		partner_joined.emit(id)
	elif id == 1:
		mode = Mode.CONNECTED
		status.emit("Connected!")


func _on_peer_disconnected(id: int) -> void:
	GameState.partners.erase(id)
	GameState.partner_info_changed.emit()
	partner_left.emit(id)
	# Host: clean up the dead connection so the same partner can rejoin.
	for k in _conns.keys():
		var st: int = _conns[k].get_connection_state()
		if st == WebRTCPeerConnection.STATE_CLOSED or st == WebRTCPeerConnection.STATE_FAILED or st == WebRTCPeerConnection.STATE_DISCONNECTED:
			_conns.erase(k)


func _on_server_disconnected() -> void:
	leave()
	failed.emit("Lost connection to your partner")


@rpc("authority", "call_remote", "reliable")
func _welcome(settings: Dictionary, host_name: String, host_color: Color) -> void:
	GameState.apply_settings_dict(settings)
	GameState.partners[1] = {"name": host_name, "color": host_color}
	mode = Mode.CONNECTED
	_hello.rpc(GameState.player_name, GameState.player_color)
	welcome_received.emit()


@rpc("any_peer", "call_remote", "reliable")
func _hello(pname: String, pcolor: Color) -> void:
	var id := multiplayer.get_remote_sender_id()
	GameState.partners[id] = {"name": pname, "color": pcolor}
	GameState.partner_info_changed.emit()
	event_received.emit(id, "hello", {"name": pname})


# ------------------------------------------------------------------ gameplay traffic

func send_state(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	if has_partner():
		_state.rpc(pos, yaw, pitch, flags)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	state_received.emit(multiplayer.get_remote_sender_id(), pos, yaw, pitch, flags)


func send_event(kind: String, data: Dictionary = {}) -> void:
	if has_partner():
		_event.rpc(kind, data)


@rpc("any_peer", "call_remote", "reliable")
func _event(kind: String, data: Dictionary) -> void:
	event_received.emit(multiplayer.get_remote_sender_id(), kind, data)


## Queue a photo for delivery; it's chunked so big photos never stall movement.
func send_photo(meta: Dictionary, png: PackedByteArray) -> void:
	if not has_partner():
		return
	var total := int(ceil(png.size() / float(CHUNK)))
	for i in total:
		_send_queue.append([meta if i == 0 else {}, str(meta["id"]), i, total,
			png.slice(i * CHUNK, min((i + 1) * CHUNK, png.size()))])


func _pump_photos() -> void:
	if _send_queue.is_empty() or not has_partner():
		return
	for _i in 3:
		if _send_queue.is_empty():
			break
		var c: Array = _send_queue.pop_front()
		_photo_chunk.rpc(c[0], c[1], c[2], c[3], c[4])


@rpc("any_peer", "call_remote", "reliable")
func _photo_chunk(meta: Dictionary, id: String, idx: int, total: int, bytes: PackedByteArray) -> void:
	if not _incoming.has(id):
		_incoming[id] = {"meta": {}, "chunks": [], "got": 0}
		_incoming[id]["chunks"].resize(total)
	var entry: Dictionary = _incoming[id]
	if not meta.is_empty():
		entry["meta"] = meta
	if entry["chunks"][idx] == null:
		entry["chunks"][idx] = bytes
		entry["got"] += 1
	photo_progress.emit(str(entry["meta"].get("by", "Partner")), entry["got"], total)
	if entry["got"] == total:
		var png := PackedByteArray()
		for b in entry["chunks"]:
			png.append_array(b)
		_incoming.erase(id)
		PhotoStore.add_photo_png(png, entry["meta"])


# ------------------------------------------------------------------ invite links

## ...?join=CODE in the page URL.
func invite_code_from_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('join') || ''", true)
	return str(q).strip_edges().to_upper() if q != null else ""


## A link your partner can open to join straight away (falls back to the bare code).
func invite_link() -> String:
	if room_code == "":
		return ""
	if not OS.has_feature("web"):
		return room_code
	var base = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
	return "%s?join=%s" % [str(base), room_code.replace("-", "")]


## ...?host=CODE opens a room with a chosen code (handy for testing).
func host_code_from_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('host') || ''", true)
	return str(q).strip_edges().to_upper() if q != null else ""

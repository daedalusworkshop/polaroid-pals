extends Node
## Minimal PeerJS-protocol signaling client over WebSocket.
## GitHub Pages is static-only, so the two browsers find each other through the
## free public PeerJS broker. It only relays tiny OFFER/ANSWER/CANDIDATE messages;
## all game traffic then flows peer-to-peer over WebRTC.

signal opened                                  # our id is registered
signal id_taken
signal message(type: String, src: String, payload: Dictionary)
signal closed(reason: String)

## Swap these if you ever self-host a PeerJS server.
const HOST := "0.peerjs.com"
const PATH := "/peerjs"
const KEY := "peerjs"
const HEARTBEAT_SEC := 5.0

var my_id := ""
var _ws := WebSocketPeer.new()
var _open := false
var _was_connected := false
var _hb := 0.0
var _active := false


func start(id: String) -> void:
	stop()
	my_id = id
	var token := "%x%x" % [randi(), randi()]
	var url := "wss://%s%s?key=%s&id=%s&token=%s&version=1.5.4" % [HOST, PATH, KEY, id.uri_encode(), token]
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	_active = err == OK
	_open = false
	_was_connected = false
	if err != OK:
		closed.emit("Could not reach the matchmaking server (%s)" % error_string(err))


func stop() -> void:
	if _active:
		_ws.close()
	_active = false
	_open = false


func is_open() -> bool:
	return _open


func send(type: String, dst: String, payload: Dictionary) -> void:
	if not _open:
		return
	var txt := JSON.stringify({"type": type, "dst": dst, "payload": payload})
	print("[sig] -> ", type, " (", txt.length(), " bytes)")
	_ws.send_text(txt)


func _process(delta: float) -> void:
	if not _active:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_was_connected = true
		_hb += delta
		if _hb >= HEARTBEAT_SEC:
			_hb = 0.0
			_ws.send_text('{"type":"HEARTBEAT"}')
		while _ws.get_available_packet_count() > 0:
			_handle(_ws.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		_active = false
		_open = false
		var why := _ws.get_close_reason()
		print("[sig] closed code=", _ws.get_close_code(), " reason=", why, " was_connected=", _was_connected)
		if not _was_connected:
			why = "Could not reach the matchmaking server"
		closed.emit(why)


func _handle(text: String) -> void:
	var msg = JSON.parse_string(text)
	if not (msg is Dictionary):
		return
	var type: String = msg.get("type", "")
	match type:
		"OPEN":
			_open = true
			opened.emit()
		"ID-TAKEN":
			id_taken.emit()
			stop()
		"ERROR":
			print("[sig] server error: ", text)
			push_warning("Signaling error: %s" % str(msg.get("payload", "")))
		"HEARTBEAT":
			pass
		_:
			var payload = msg.get("payload", {})
			if not (payload is Dictionary):
				payload = {"value": payload}
			message.emit(type, str(msg.get("src", "")), payload)

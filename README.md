# Polaroid Pals

A cozy 3D pixel-art photography walk for two. It's first person and runs in the browser, built with Godot 4.7.

## Playing together
1. Both of you open the game's page (your GitHub Pages URL).
2. One person clicks **Host a walk**. They get a room code like `MOSS-42`.
3. The other person types the code and clicks **Join**. Or the host can send an **invite link** from the Esc menu, and opening it joins automatically.

Every photo either of you takes shows up in the shared album for both of you (**Tab**). You can heart photos and download them as full-size pixel-perfect PNGs.

## Controls
| | |
|---|---|
| WASD / Shift / Space | walk / run / jump |
| Right-click or C | raise or lower the camera |
| Left-click | take a photo (camera raised) |
| Scroll | switch lens: 16 / 24 / 35 / 50 / 85 / 135 / 200 mm |
| Q / E | open or close the aperture (depth of field is baked into the photo) |
| Z / X | exposure − / + |
| F | film look: Natural, Portra, Cinestill, Velvia, Faded, Mono |
| Tab | shared album |
| T or Enter | chat |
| 1–4 | wave, heart, sit, hop |
| G | ping your location to your partner |
| H | hide the HUD |
| Esc | time of day, weather, travel between worlds, invite link, settings |

## Worlds
Each world is procedurally generated from a seed that both players share:
- **Jungle Ruins**: inspired by Ta Prohm, Angkor.
- **Alpine Valley**: inspired by Lauterbrunnen, Switzerland.
- **Tokyo Backstreets**: inspired by Yanaka, Tokyo.

The weather options are Clear, Mist, Rain, Snow (it settles on things), Petals and Fireflies.

## Deploying to GitHub Pages
1. Create a GitHub repo and push this folder to its `main` branch.
2. In the repo, go to **Settings → Pages → Source** and choose **GitHub Actions**.
3. Every push runs `.github/workflows/pages.yml`, which exports the Web build and publishes it at `https://<you>.github.io/<repo>/`.

## Local development
- Editor: Godot **4.7.2** (Compatibility renderer).
- Build the web version locally: `tools/export_web.sh`, then serve it with `node tools/serve.js` and open http://localhost:8060.
- `tools/duo.html?code=TEST1` runs a host and a guest side by side in one page, for testing multiplayer.
- To render a screenshot for development: `godot --path . -- shot world=alps tod=17 pos=0,20 yaw=90 out=shot.png` (add `raise photo lens=85 ap=0` to test the camera).

## How it works
- **Look**: the 3D view renders at about 480×270 and is upscaled with nearest-neighbour filtering. Toon shading uses tinted ambient light (blue-violet shadows), painted light shafts and a gentle ordered dither. All art is generated in code: meshes in `world/Geo.gd`, textures in `world/TextureForge.gd`.
- **Networking**: WebRTC peer-to-peer (`autoload/Net.gd`). The two browsers find each other through the free public PeerJS broker (`autoload/PeerSignaling.gd`), so no server of your own is needed. If a strict network (for example campus wifi) blocks the connection, add a TURN server to `ICE_SERVERS` in `Net.gd`.
- **Photos**: shooting renders an extra depth pass, and `shaders/post.gdshader` develops the photo with real depth of field and the chosen film look (`World.develop_photo`).

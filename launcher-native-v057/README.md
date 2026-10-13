# Paladin Guard 0.5.7 — single continuous animated mesh

**Changes:** Only one Direct2D background graph spans the entire launcher, including behind translucent cards, sidebar, settings, help and news. 44 shared nodes, <=65 links, connected spanning-tree structure, subtle red/blue/gold/white colors, 15 FPS low-spec or 30 FPS standard. Mouse repulsion and clicks work in one window-wide coordinate system; no per-card network, no node count growth, no WebView/CLR. Both IP address and port are intentionally **not drawn anywhere in the UI**; the private server endpoint remains needed internally to request live status and to connect via the game client.

The bundled client remains OpenSAMP v0.5.6 with native FreeCam changes; this release is a launcher UX revision. End-to-end FreeCam and server-side save/teleport still require actual game + VPS testing, not just Windows CI compilation.

Build: `cmake -S launcher-native-v057 -B build/native -G "Visual Studio 17 2022" -A x64 && cmake --build build/native --config Release`.

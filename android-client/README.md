# PGRP Independent Android Game Client — Alpha 0.2.0

## What this actually is
This project is a **new, standalone Android game runtime** that runs entirely inside its own APK, not a wrapper that launches a third-party SA-MP client. It is separate from the earlier `android-launcher` and the stable Windows PGRP v0.5.31 branch.

The APK contains a real-time **OpenGL ES 2.0** renderer, independently generated procedural city blocks with roads and buildings, WASD-equivalent two-thumb movement, right-hand camera look, a player pose, a HUD, and a read-only UDP probe of the PGRP game server.

**Do not label this a playable GTA SA/open.mp-compatible multiplayer client yet.** The 3D scene is an original test environment, not the GTA San Andreas map; it currently has no player login, RakNet reliable transport, SA-MP/open.mp RPCs or entity replication.

## Implemented
- Full-screen landscape immersive game experience, Android 8+ (API 26+)
- Proprietary-free renderer with a procedural road/building district, depth and perspective
- Fixed delta-time movement, yaw + clamped pitch, multitouch joystick + camera
- Reset spawn, movement action and live 3D world-position HUD
- SA-MP UDP server-information query and **one** initial RakNet OpenConnectionRequest1 probe, **NOT** a full connection
- Deterministic no-Android JUnit tests for input, player movement, world bounds, network packet structure
- Debug-signed standalone APK generated in GitHub Actions

## Major unimplemented game-client milestones
1. **Real game asset support**: legally acquired GTA SA files supplied by each user; streaming of IPL/IDE/DFF/TXD/COL/IMG, rendering and collisions. These files cannot be bundled into a public APK without distribution rights.
2. **Full RakNet transport**: MTU negotiation, connection request 2, session setup, connected packets, ACK/NACK, sequencing, reliable delivery, splitting, bitstreams, validation, timeouts and protocol-version selection.
3. **SA-MP/open.mp compatibility**: actual challenge and Join RPC, server dialog/authentication, gamemode sync, vehicles, objects, animations, streaming, HUD, chat, voice if supported.
4. **Game systems**: character models, skeletons, movement physics, collisions, combat, animations, vehicles, maps, textures, sound, interior transitions.
5. **Secure content/config delivery**: licensed local assets or authorized OTA patches; signed releases and update/rollback mechanism.
6. **On-device compatibility testing**: graphics features, 30/60 FPS, Android lifecycle, thermal budget, input responsiveness and gameplay interoperability with server 46.38.138.33:7777.

## Build
Android Studio + Android SDK API 35 + JDK 17; open `android-client` and build using `gradle testDebugUnitTest assembleDebug`.
The CI workflow `.github/workflows/build-independent-android-v020.yml` generates and publishes `PGRP_Independent_Android_Client_v0.2.0_Alpha.apk`.

## Test on phone
Install the debug APK. Use the left joystick to walk the **prototype** city and drag on the right to look around. Tap "تست اتصال" to check if PGRP server replies to a query and initial RakNet request. It does **not** log into the gamemode. Do not delete your stable PC install.

## Licenses/asset ownership
The original example environment is produced procedurally and requires no GTA intellectual property. No proprietary GTA/SA-MP Android client binary, Rockstar game assets, or unauthorized game downloads are incorporated. Any external engine/protocol library incorporated later must be separately license-reviewed.

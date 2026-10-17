# PGRP Native Launcher 0.5.15

Replacement for the 0.5.4 self-contained .NET launcher with a native x64 Windows C++17 executable. **No .NET Runtime, WebView, browser engine or external GPU shaders.**

- Windows 10 or later; Direct2D and DirectWrite (bundled with Windows).
- /MT static CRT. Avoid additional x64 runtime.
- Real SA-MP UDP Query for server status/player count and ping; bounded 1.2-second background worker.
- Drawing in one Direct2D HWND render target; animation 15 FPS low-spec / 30 FPS normal, 44 reusable nodes.
- Interactive node graph; hover/click; PGRP roleplay dashboard; settings; nickname and GTA path; server play.
- Saved settings in %LOCALAPPDATA%/PaladinGuard/Launcher/settings-native-v055.ini
- Automatically closes after starting the existing OpenSAMP game client.
- Does not bundle GTA content, modify live server, or bypass access controls.

## Build (Visual Studio 2022 Windows runner)

cmake -S launcher-native-v055 -B build/native -G "Visual Studio 17 2022" -A x64
cmake --build build/native --config Release --parallel

**Security:** Signing and trustworthy distribution are separate from compilation. This repository does not contain a code-signing certificate.

**Freecam:** Native launcher's small size does not itself repair missing object/camera RPC handlers in the game client.

## Dashboard v0.5.15
One connected background mesh for all tabs (72 nodes; 15 FPS low-spec), no per-card rendering. Private server endpoint is used only internally, never shown in UI. 1.5-second UDP ping samples populate a continuous line chart with honest gaps for missed replies. Installer asks for an existing legally owned GTA SA and puts gta_sa.exe beside PGRPLauncher.exe in the chosen installation folder.

0.5.15: PALADIN GUARD ROLEPLAY is the only brand label, lighter de-duplicated menu and permanently moving 4-color full-scene graph. Native game client adds world-ready spawn handshake, camera-cell streaming and bounded ImGui command history with Up/Down. Live admin TAB list auto-refreshes in the separately delivered server ZIP. Test freecam in GTA; CI only ensures native code compiles.

0.5.15: Player-friendly dashboard (main join, player count and full-width ping graph), no technical cards. The native client shows admin-only live TAB without repeatedly opening open.mp dialogs; up/down command history and high-resolution chat geometry remain enabled. Corresponding 0.5.15 server source must be compiled and deployed for live TAB updates.

## Camera and spawn v0.5.15
Native GTA camera mode is entered once. A separate fixed-mode source API (GTA 1.0 0x50BEC0) and SCM look-at update the camera every frame. The invisible ped tracks the camera for proper GTA streaming. The initial authenticated spawn preloads collision before teleport and maintains a bounded position/velocity lock until the server's world-ready confirmation. Preserve v0.5.9 for rollback. The Windows CI cannot run GTA SA itself, so on-device runtime verification remains required.

## PGRP 0.5.15 server+client coordinated fix
Install the paired server update first: server rejects bootstrap-origin account locations (0.5,0.5,0) and restores configured spawn.cfg, without writing invalid new positions. This client rejects an invalid SetSpawnInfo instead of teleporting into unloaded sea. Replaces exception-throwing CStreaming::LoadScene with safe SCM refresh and adds 1-second FreeCam movement diagnostics. GTA gameplay validation still required; build success alone is insufficient.

0.5.15 FreeCam: the native game client no longer overrides legitimate on-foot coordinates with stale data. Free flight begins from the current physically synchronised player location; a hook immediately following GTA's own CCamera::Process updates the active CCam vectors and RenderWare camera matrix so the camera moves on screen rather than just the radar. Render hook is conditional on active server-authorized FreeCam; no changes to the working login spawn. The existing PGRP 0.5.11 server is protocol compatible. Verify in-game, CI cannot emulate GTA.

### FreeCam input hotfix v0.5.15
The 0.5.12 module maintained two independent GTA HWND globals: the D3D hook's static HWND was valid, but GUI's global HWND was never initialised. FreeCam's GetForegroundWindow() test always failed, so WASD and mouse were silently ignored. The 0.5.15 patch initialises gui::g_hwnd and exposes PgrpFreeCamIsActive to suppress ordinary ped movement keydown during flight. Added logs to confirm physical input, ped hide state and camera-render hook. This is compatible with the same 0.5.11 server. Check gameplay on a real GTA instance.


## FreeCam movement 0.5.15
W and S now translate forward/back on the level XY plane according to camera yaw; A/D strafe on the same plane; Space/Ctrl independently adjust altitude. Camera pitch no longer causes W/S to fly vertically. Mouse look uses genuine WM_INPUT relative mouse deltas with no SetCursorPos/desktop cursor recentering and drops stale input while chat or game is unfocused. Vertical look remains independent, with pitch clamp. Only the client is changed; keep the known-working server v0.5.11.


## FreeCam mouse/game controls hotfix 0.5.15
W now moves visibly forward and S backward, matching GTA camera view. The previous global `RegisterRawInputDevices()` call at ImGui startup wrongly hijacked GTA's mouse registration in ordinary gameplay, even if FreeCam was never active. Mouse capture is now lazily installed only while FreeCam is active AND game window is focused, after snapshotting any existing mouse HID registration. On FreeCam exit, alt-tab or shutdown, the original registration/flags/HWND are restored; when none existed, the temporary one is removed. Legacy GTA mouse cursor/camera input is never blocked during normal play. Raw mouse look sensitivity is reduced to limit spikes. All spawn/server logic remains unchanged and server v0.5.11 remains protocol compatible. CI does not emulate real GTA: verify physical mouse in both modes on Windows.

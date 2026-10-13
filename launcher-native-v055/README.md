# PGRP Native Launcher 0.5.5

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

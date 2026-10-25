# PGRP Launcher Preview v0.5.2 (Windows x64)

A desktop front-end for existing PGRP OpenSAMP test installations, implemented in WinForms .NET 8, with:
- Functional "Play" button launching the **existing** opensamp.exe located beside a legally obtained gta_sa.exe and Client.Native.dll.
- Optional auto-connect environment variable 'PGRP_AUTOCONNECT_NICK' (requires v0.5.2 native patch); older versions retain manual //connect 46.38.138.33 7777 Name_Surname behavior.
- UDP query of the known server endpoint, player count and ping. Timeout means **status unknown / no query response**, not proven offline.
- Browse path, nickname settings, low-spec animation preset.
- Node-link background with cursor repulsion, click to recycle nodes (bounded to 36).
- Local announcements placeholder explicitly marked as non-live.

The launcher **does not** bundle GTA assets, does not alter game files or accounts, and does not patch the server. It doesn't silently auto-update the GTA game folder. Requires Windows 10+ x64. Self-contained CI build needs no separate .NET runtime.

## Build
dotnet publish launcher-v052/PGRPLauncher.csproj -c Release -r win-x64 -p:PublishSingleFile=true --self-contained true -o dist/PGRPLauncher

The default version in the app remains a preview; CI artifacts are candidate builds and require actual user-PC testing. Preserve any prior known-working PGRP installer.

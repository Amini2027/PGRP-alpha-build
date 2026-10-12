# PGRP client roadmap — agreed product goals (2026-10-12)

This document separates **confirmed user requirements** from **unapproved design choices**.

## Baseline
- Server: open.mp 1.5.8.3079, GTA SA RolePlay; accounts, world state, and spawn remain authoritative on server.
- Windows client PGRP Alpha v0.4.7 is verified in the user's real environment as loading and entering server on a 4 GB PC with an old NVIDIA GT 430; keep regressions as a hard gate.
- PC2 (16 GB RAM) also works. Never silently replace a known-working installation.
- Standalone Windows Setup asks for owned GTA San Andreas gta_sa.exe and creates a separate per-version installation.

## Confirmed requirements
1. Clock, world time and weather must stay synchronized with the open.mp server, not local vanilla GTA.
2. A distinct PGRP visual design **inspired by** VMP multiplayer polish; no exact copy of logos, artwork or proprietary assets.
3. Graphical login / registration forms. User will define cinematic flow later; no unapproved storyboard.
4. Normal players must not see the traditional TAB scoreboard; elevated/staff access must be permission-based and verified by server.
5. Additional modular UI features to be specified later.
6. Windows machines with 4 GB RAM / low-end graphics and Android phones are primary targets; performance is an acceptance criterion, not an afterthought.
7. Retain open.mp/SA-MP networking and game-mode features, and existing PGRP account continuity.
8. User wants an independent PGRP launcher, not a mandatory third-party launcher for play.

## Architecture boundaries
- Open.mp server: source of truth for auth, account rank/permissions, spawn, clock/weather, vehicle/player state.
- Desktop: Windows x86 GTA SA + Windows launcher + native injected client; UI layer uses existing lightweight ImGui/D3D9 implementation. Dynamic GPU-heavy overlays are opt-in only.
- Android: **different mobile client implementation/integration** required. Windows EXE, x86 native DLL and Windows D3D9 hooks cannot run directly on Android/ARM. Must research licensing, integration, networking compatibility and legal distribution of game assets before promising a playable APK. No arbitrary APK packaging of PC DLLs.
- Shared *UI design system and server RPC semantics*, not a shared executable.

## Implementation order
1. Stable network protocol and server-authoritative world state (RPC 29 SetPlayerTime, 94 SetPlayerWorldTime, 152 SetPlayerWeather, InitGame).
2. Client PC1 performance gate and startup/crash diagnostics.
3. Design tokens (PGRP premium dark/gold/charcoal with legible typography; adjust after user supplies desired reference screenshots).
4. Server-sourced role flag for scoreboard: normal players TAB disabled; administrators allowed only as confirmed by server; avoid client-only privilege check.
5. Modular HUD, menus, notifications and scalable responsive forms; keyboard/mouse and touch navigation abstracted.
6. Cinematic auth scenes after user sends sequence, screens and UI copy; offer instant skip and static variant for Low Spec.
7. Explore Android native/mobile-compatible GTA SA client path and parallel performance testing.

## Performance/QA gates
- Mandatory "Low Spec" visual preset: no blur, no animated backdrops in gameplay, minimal draw calls, pooled widgets, lazy assets, small textures, minimal RAM overhead.
- Track consistent initial connection and stable 10-minute play sessions on the real 4GB Windows PC and on the 16GB reference PC.
- Measure frame-time, memory, GPU draw counts, packet send frequency, scene load latency. Optimize based on measured bottlenecks.
- Low-end Android model/OS specs needed before setting mobile FPS/memory budgets.
- Validate reconnect, sky/weather, login, spawn, chat, vehicle sync, spectator transitions.
- Update components incrementally. Preserve the last known-working installer; no unattended server schema migrations.

## Not yet decided
- VMP screenshot/reference; branding specifics; login cinematic storyboard.
- Permission semantics for admins/moderators and whether staff TAB should be native or custom.
- Android GTA SA mobile version and distribution model.
- Visual assets, localized UI language(s), target FPS tiers and minimum OS/hardware.

# PGRP v0.5.2 — Server-authoritative spawn persistence

The verified GitHub repo contains launcher/client patches but **does not contain the server gamemode (.pwn), account schema, or live MySQL configuration**. Do not patch the client to teleport to a guessed coordinate, and do not overwrite the VPS game-mode from an example.

## Current behavior and required server-side fix
- New account, first-ever authentication: initial registered spawn from existing RP gamemode.
- Returning authenticated account: last **valid, persisted** position (x, y, z, facing angle, interior, virtual world) and skin restored from database.
- Disconnect: checkpoint the authoritative position if player was fully authenticated/spawned, not spectating, not inside a transition/invalid world, and coordinates are finite and within GTA world bounds.
- Periodic checkpoint every 30–60 seconds while playing, for server crashes (and optionally before player death/teleport with the gamemode's own policy).
- Never treat (0,0,0), login camera, connection bootstrap, class-selection, or spectator location as a valid saved position.
- Avoid moving the initial spawn each reconnect; distinguish first login by 'has_completed_initial_spawn' (or the existing equivalent DB flag) rather than last_* defaults.
- Persist atomically by **stable account ID**, never by temporary SA-MP player ID. Use parameterized queries with explicit column names and async MySQL completion.
- If player logs out while driving, save last safe on-foot exit point or a validated vehicle position and settle the player on nearby ground — policy must be integrated with the server's vehicle subsystem.
- Restore interior/VW and skin before first server-authorized SetSpawnInfo + TogglePlayerSpectating(false). Don't send an early Spawn RPC; v0.5.1 client already protects the PGRP spawn handshake.
- The native client is a renderer and input/network implementation; it **must not** invent persisted player coordinates.
- QA: brand-new account, reconnect at road (on foot), disconnect in interior, world instance, death, during auth, vehicle, network timeout, server restart, and player account swap.

## Migration boundary
Before writing executable server changes, inspect actual .pwn source, MySQL plugin version, account load/save code, auth state, existing spawn callback order, and current DB schema. Prepare an additive migration and verify migration on a disposable copy of the DB; **never** replace existing character/account records or reset locations.

## In-game chat (client)
'apply-pgrp-chat-v052.ps1' is applied *after* 'apply-pgrp-ui-v051.ps1' to remove the dark 'ImGuiCol_ChildBg' rectangle and route '[NetGame]' diagnostics to 'OpenSamp.log'. The regular chat stays readable for a few seconds and F7 retains the history. 'PGRP_AUTOCONNECT_NICK' is optional; without it, manual //connect <IP> <PORT> <NICK> remains supported.

## Rollback
Never replace a user's known-working v0.5.1 installation in place; build v0.5.2 as separate test artifacts. Keep the server and database unchanged until its .pwn source has been inspected and patched.

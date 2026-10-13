param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label) {
  $p=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $s=[IO.File]::ReadAllText($p)
  $count=([regex]::Matches($s,[regex]::Escape($before))).Count
  if($count -ne 1){throw "FreeCam compatibility patch ${label}: expected one anchor, got $count"}
  [IO.File]::WriteAllText($p,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PATCH OK: FreeCam $label"
}
# v0.5.4 introduced an all-screen login/loading veil whose predicate was false
# whenever bIsSpectating=true, including an ADMIN's *post-login* /freecam.
# This was a certain visual blocker; distinguish not-yet-spawned auth from
# spectator status. Never disable the login veil prior to first spawn.
Patch 'native/sampraknet_bridge.cpp' @'
        if (!iSpawned || bIsSpectating || g_pgrpSpawnVisualHoldMs == 0) return false;
'@ @'
        // Spectator mode is also used by logged-in admins in /freecam.
        // Once a server-authorized initial spawn has completed, DO NOT
        // re-cover the entire world with the authentication screen.
        if (!iSpawned || g_pgrpSpawnVisualHoldMs == 0) return false;
'@ 'remove spectator overlay collision'
# The PGRP spawn patch replaces the original ScrTogglePlayerSpectating
# branch with an endpoint-aware one. Apply the restore to that exact branch.
Patch 'native/sampraknet_bridge.cpp' @'
    if (g_pgrpEndpoint)
    {
        g_pgrpReleasedSpectator = (bToggle == 0);
'@ @'
    if (g_pgrpEndpoint)
    {
        // The server may release an already-spawned admin from FreeCam.
        // The generic initial-spawn code cannot run again; restore local
        // camera mode without rewriting the player's persisted location.
        if (bIsSpectating && !bToggle && iSpawned)
        {
            gta::sa::CameraRestore();
            Log("[PGRP FreeCam] spectator released; GTA camera restored");
        }
        g_pgrpReleasedSpectator = (bToggle == 0);
'@ 'restore GTA camera on post-login freecam exit'
Write-Host 'PGRP v0.5.5 FreeCam: authenticated overlay and spectator exit fixed.'
Write-Host 'NOTE: Full object attach/streaming and spectator key sync are still absent in upstream.'

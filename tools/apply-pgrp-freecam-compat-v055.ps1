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
# This client previously restored camera only on initial login spawn.
# FreeCam exit begins with iSpawned=1: restore camera explicitly to prevent
# remaining in a fixed/attached camera mode when the server releases spectator.
Patch 'native/sampraknet_bridge.cpp' @'
    if (bIsSpectating && !bToggle && !iSpawned)
    {
        sampSpawn();
        iSpawned = 1;
    }

    bIsSpectating = bToggle;
'@ @'
    if (bIsSpectating && !bToggle)
    {
        if (!iSpawned)
        {
            sampSpawn();
            iSpawned = 1;
        }
        else
        {
            gta::sa::CameraRestore();
            Log("[PGRP FreeCam] spectator released; following physical player");
        }
    }
    bIsSpectating = bToggle;
'@ 'restore third-person GTA camera on freecam exit'
Write-Host 'PGRP v0.5.5 FreeCam: authenticated overlay and spectator exit fixed.'
Write-Host 'NOTE: Full object attach/streaming and spectator key sync are still absent in upstream.'

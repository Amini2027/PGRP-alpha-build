param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$Path,[string]$Before,[string]$After) {
 $full=(Resolve-Path -LiteralPath (Join-Path $Root $Path)).Path
 $s=[IO.File]::ReadAllText($full)
 $hits=([regex]::Matches($s,[regex]::Escape($Before))).Count
 if($hits -ne 1) { throw "Patch expected one occurrence ${Path}: $hits" }
 [IO.File]::WriteAllText($full,$s.Replace($Before,$After),[Text.UTF8Encoding]::new($false))
 Write-Host ("PGRP PC1 Camera/Patch fix: "+$Path)
}
# Clear the 115-kB scanlist through the memory abstraction which applies
# VirtualProtect and catches memory write failure. A naked memset can throw
# an access violation on systems whose GTA 1.0 build maps it read-only.
Patch 'native/patches.cpp' '    std::memset(reinterpret_cast<void*>(0xB7D0B8), 0, 8 * 14400);' @'
    if (!mem_set(0xB7D0B8u, 0, 8 * 14400))
    {
        // Do not dereference untrusted/unwritable GTA pages.
        // Preserve stage trace rather than killing the initialization thread.
        OutputDebugStringA("[PGRP] WARN original scanlist clear failed; continuing.\n");
    }
'@
# Fix RPC 124: SA-MP transmits a single boolean byte, not a Win32
# 4-byte BOOL. The previous read could fail and leave bToggle uninitialized,
# preventing spawn and leaving the auth camera pointed at empty terrain.
Patch 'native/sampraknet_bridge.cpp' @'
    BOOL bToggle;

    bsData.Read(bToggle);

    if (bIsSpectating && !bToggle && !iSpawned)
'@ @'
    BYTE bToggle = 0;
    if (!bsData.Read(bToggle))
    {
        Log("[Spectating] malformed toggle RPC; ignoring");
        return;
    }

    if (bIsSpectating && !bToggle && !iSpawned)
'@
Patch 'native/sampraknet_bridge.cpp' @'
    bIsSpectating = bToggle;
}

// RPC 70
'@ @'
    bIsSpectating = (bToggle != 0);
    if (!bIsSpectating)
    {
        // Login left a fixed/spectator camera active. The server's spawn
        // coordinates may already be correct (radar correct), but the view
        // remains at the login-camera target without this restoration.
        gta::sa::CameraRestore();
        Log("[Camera] reset behind local player after Spectating=false");
    }
}

// RPC 70
'@
Patch 'native/sampraknet_bridge.cpp' @'
    bIsSpectating = false;

    Log("You have been spawned!");
'@ @'
    bIsSpectating = false;
    gta::sa::CameraRestore();
    Log("[Spawn] restored player-follow camera at spawn point");

    Log("You have been spawned!");
'@
# Debug RPCs are useful in OpenSamp.log, but not as chat HUD lines.
Patch 'native/sampraknet_bridge.cpp' '    g_chat.PushLineAsync(buffer);' @'
    const bool isEngineDiagnostic =
        std::strncmp(buffer, "[WorldTime]", 11) == 0 ||
        std::strncmp(buffer, "[Weather]", 9) == 0 ||
        std::strncmp(buffer, "[TEXTDRAW:EDIT]", 15) == 0 ||
        std::strncmp(buffer, "[Camera]", 8) == 0;
    if (!isEngineDiagnostic)
        g_chat.PushLineAsync(buffer);
'@
Write-Host 'PGRP PC1 v0.4.7 scanlist/spectator/camera/chat fixes successfully applied.'

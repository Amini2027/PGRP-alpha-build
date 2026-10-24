param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$old,[string]$new,[string]$label){
    $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
    $s=[IO.File]::ReadAllText($file)
    $n=([regex]::Matches($s,[regex]::Escape($old))).Count
    if($n -ne 1){throw "v0531 $label requires one occurrence, found $n"}
    [IO.File]::WriteAllText($file,$s.Replace($old,$new),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0531 PATCH OK: $label"
}
# The real in-game v0530 test confirmed all buildings and roads are visible.
# Changing the RW camera right vector to remove mirrored backface culling
# reversed the *perceived* horizontal mouse direction relative to v0529.
# Recalibrate only the horizontal HID delta sign to the new stable camera.
# DO NOT modify vertical mouse axis, WASD, RW parity, streaming or camera.
Patch 'native/sampraknet_bridge.cpp' @'
            s.yaw=std::remainder(s.yaw+mx*mouseScale,6.283185307f);
'@ @'
            // v0531 user-calibrated left/right after v0530 RW handedness fix.
            // Keep signed raw HID input and pitch handling otherwise intact.
            s.yaw=std::remainder(s.yaw-mx*mouseScale,6.283185307f);
'@ 'invert horizontal mouse axis only'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0530] BUILD=proper-rw-camera-parity-20261022 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0531] BUILD=horizontal-mouse-only-20261022 DLL=%s",dllPath);
'@ 'new build identity with loaded DLL path'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0530] BUILD=proper-rw-camera-parity-20261022 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0531] BUILD=horizontal-mouse-only-20261022 DLL_PATH_UNAVAILABLE");
'@ 'build identity fallback'
Write-Host 'v0531: only horizontal mouse direction inverted; v0530 RW camera and world visibility unchanged.'

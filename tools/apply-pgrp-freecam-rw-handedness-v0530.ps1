param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$tag) {
    $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
    $source=[IO.File]::ReadAllText($file)
    $n=([regex]::Matches($source,[regex]::Escape($before))).Count
    if($n -ne 1){throw "PGRP v0.5.30 $tag requires one anchor; found $n"}
    [IO.File]::WriteAllText($file,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0.5.30 PATCH OK: $tag"
}
# Root cause: v0525 copied the [right, forward, up] GTA CMatrix into
# RenderWare [right, up, at] without correcting the swapped axes' parity.
# Old determinant = dot(cross(GTA_right, up), forward) = -1, so the
# camera is a REFLECTION rather than a proper rotation. GPU backface
# winding/culling then makes streets, roads and building faces disappear
# despite models being present and CStreaming requests fully draining.
#
# Preserve GTA's proper CMatrix (right, forward, up) and FreeCam strafing
# basis; negate ONLY the RenderWare camera's right vector.
Patch 'native/sampraknet_bridge.cpp' @'
            desired.right[0]=basis.right.x;
            desired.right[1]=basis.right.y;
            desired.right[2]=basis.right.z;
'@ @'
            // GTA [right,forward,up] and RenderWare [right,up,at]
            // have opposite axis parity. A proper render camera MUST
            // satisfy dot(cross(RW.right,RW.up),RW.at) = +1.
            // The old v0525 used basis.right directly, producing -1 and
            // mirrored front faces that disappeared under backface culling.
            const auto rwRight=pgrpfc_math::RenderWareRight(basis);
            desired.right[0]=rwRight.x;
            desired.right[1]=rwRight.y;
            desired.right[2]=rwRight.z;
'@ 'make RenderWare camera a proper rotation rather than a reflection'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0525] RW copies=%u corrected=%u beforeUp=%.4f beforeAt=%.4f LTMup=%.4f LTMat=%.4f upZ=%.4f yaw=%.4f pitch=%.4f",
                    copyCount,correctedCount,beforeUp,beforeAt,
                    postUp,postAt,finalMatrix[6],s.renderYaw,pitch);
'@ @'
                // Real LTM—not the source basis—must be a right-handed
                // matrix. Record the determinant to confirm the GPU sees
                // normal outward-facing triangles in FreeCam.
                const float det=
                    (finalMatrix[1]*finalMatrix[6]-finalMatrix[2]*finalMatrix[5])*finalMatrix[8]+
                    (finalMatrix[2]*finalMatrix[4]-finalMatrix[0]*finalMatrix[6])*finalMatrix[9]+
                    (finalMatrix[0]*finalMatrix[5]-finalMatrix[1]*finalMatrix[4])*finalMatrix[10];
                const float rightDot=finalMatrix[0]*rwRight.x+
                    finalMatrix[1]*rwRight.y+finalMatrix[2]*rwRight.z;
                Log("[PGRP FC v0530 RW] copies=%u corrected=%u det=%.5f rightDot=%.4f LTMup=%.4f LTMat=%.4f xyz=(%.1f,%.1f,%.1f) yaw=%.4f pitch=%.4f",
                    copyCount,correctedCount,det,rightDot,
                    postUp,postAt,s.renderX,s.renderY,s.renderZ,
                    s.renderYaw,pitch);
                if(!std::isfinite(det) || det<0.97f || det>1.03f)
                    Log("[PGRP FC v0530 RW] ERROR camera handedness invalid: %.5f",det);
'@ 'measure actual rendered matrix determinant and camera parity'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0529] BUILD=world-sector-visibility-20261022 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0530] BUILD=proper-rw-camera-parity-20261022 DLL=%s",dllPath);
'@ 'identify installed DLL with actual loaded path'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0529] BUILD=world-sector-visibility-20261022 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0530] BUILD=proper-rw-camera-parity-20261022 DLL_PATH_UNAVAILABLE");
'@ 'new build identity fallback'
Write-Host 'PGRP v0.5.30: correct RenderWare camera determinant to +1, preserving player movement and GTA CMatrix.'

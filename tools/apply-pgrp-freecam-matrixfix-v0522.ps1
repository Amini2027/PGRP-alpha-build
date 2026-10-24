param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
  $full=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $s=[IO.File]::ReadAllText($full)
  $hits=([regex]::Matches($s,[regex]::Escape($before))).Count
  if($hits -ne 1){throw "PGRP v0.5.22 $label expected 1 anchor, got $hits"}
  [IO.File]::WriteAllText($full,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v0.5.22 PATCH OK: $label"
}
# CMatrix (GTA SA): right @ +00, forward @ +10, up @ +20, pos @ +30.
# v0521 put up at +10, forward at +20: that was the in-game inverted world.
Patch 'native/sampraknet_bridge.cpp' @'
        put3(m+0x00,right);
        put3(m+0x10,up);
        put3(m+0x20,forward);
        put3(m+0x30,pos);
'@ @'
        put3(m+0x00,right);
        put3(m+0x10,forward); // GTA CMatrix::m_forward / RW::up
        put3(m+0x20,up);      // GTA CMatrix::m_up / RW::at
        put3(m+0x30,pos);
'@ 'match GTA CMatrix axis offsets with CCam and actual rendering'
# Windows Raw mouse positive X = mouse moved right. In GTA world
# front=(cos(yaw),sin(yaw),pitch); negative yaw is camera-right.
Patch 'native/sampraknet_bridge.cpp' @'
            s.yaw=std::remainder(s.yaw+mx*mouseScale,6.283185307f);
'@ @'
            s.yaw=std::remainder(s.yaw-mx*mouseScale,6.283185307f);
'@ 'mouse right moves camera to the right in GTA frame'
# v0520 (for stability) limited pitch to 80 degrees, despite the HUD's
# advertised nearly-vertical look. With corrected basis we can use +/-89.
$path=(Resolve-Path -LiteralPath (Join-Path $Root 'native/sampraknet_bridge.cpp')).Path
$text=[IO.File]::ReadAllText($path)
$old='1.3962634f'
$matches=([regex]::Matches($text,[regex]::Escape($old))).Count
if($matches -lt 4 -or $matches -gt 10){throw "Unexpected pitch clamp count $matches"}
$text=$text.Replace($old,'1.55334306f')
[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
Write-Host "PGRP v0.5.22 PATCH OK: expand $matches upright pitch clamps to +/-89 degrees"
# Initialize yaw/pitch from a normalized GTA CCam front vector.
Patch 'native/sampraknet_bridge.cpp' @'
                st.pitch=std::asin((std::max)(-.99f,(std::min)(.99f,f[2])));
'@ @'
                const float normalizedZ=(std::max)(-1.f,
                    (std::min)(1.f,f[2]/len));
                st.pitch=std::asin(normalizedZ);
'@ 'normalize initial camera front before asin'
# Update message so user can read accurate safe controls.
Patch 'native/sampraknet_bridge.cpp' @'
            : std::string("[PGRP FreeCam] UPRIGHT: full 360 yaw, +/-80 pitch. Ctrl+F11 enters vertical spin."));
'@ @'
            : std::string("[PGRP FreeCam v0.5.22] UPRIGHT: full 360 yaw, +/-89 pitch. Ctrl+F11 enters vertical spin."));
'@ 'display accurate pitch limit and testable build marker'
# Do not access matrix/render locals from the separate input Tick scope.
Patch 'native/sampraknet_bridge.cpp' @'
        if((++renderTick % 18000)==0)
            Log("[PGRP FC v0521] camera hook alive, frame %u",renderTick);
'@ @'
        if((++renderTick % 18000)==0)
            Log("[PGRP FC v0522] camera input tick alive, frame %u",renderTick);
'@ 'update existing input tick heartbeat version'
# Log exact loaded DLL path once from the real post-CCamera::Process hook
# and print the actual written matrix values at a safe low sample rate.
Patch 'native/sampraknet_bridge.cpp' @'
        put3(m+0x30,pos);
        // Synchronise the RenderWare camera with the overridden GTA matrix.
'@ @'
        put3(m+0x30,pos);
        static unsigned matrixCheckCount=0;
        if((++matrixCheckCount)==1) {
            char dllPath[MAX_PATH]={0};
            HMODULE activeDll=GetModuleHandleA("Client.Native.dll");
            if(activeDll && GetModuleFileNameA(activeDll,dllPath,MAX_PATH))
                Log("[PGRP FC v0522] BUILD=matrixfix-20261020 DLL=%s",dllPath);
            else
                Log("[PGRP FC v0522] BUILD=matrixfix-20261020 DLL_PATH_UNAVAILABLE");
        }
        if((matrixCheckCount % 240)==0) {
            const float* matrixForward=reinterpret_cast<const float*>(m+0x10);
            const float* matrixUp=reinterpret_cast<const float*>(m+0x20);
            const float dotFF=forward[0]*matrixForward[0]
                 +forward[1]*matrixForward[1]+forward[2]*matrixForward[2];
            const float dotUU=up[0]*matrixUp[0]
                 +up[1]*matrixUp[1]+up[2]*matrixUp[2];
            Log("[PGRP FC v0522] frame=%u yaw=%.4f pitch=%.4f pos=(%.2f,%.2f,%.2f) forward=(%.3f,%.3f,%.3f) up=(%.3f,%.3f,%.3f) matrixDotF=%.5f matrixDotU=%.5f",
                matrixCheckCount,s.yaw,s.pitch,s.x,s.y,s.z,forward[0],forward[1],forward[2],
                up[0],up[1],up[2],dotFF,dotUU);
        }
        // Synchronise the RenderWare camera with the overridden GTA matrix.
'@ 'diagnostic exact loaded DLL path and rendered CMatrix data from valid scope'
Write-Host 'PGRP v0.5.22: verified GTA CMatrix Right/Forward/Up, camera right handedness, yaw sign, +/-89 degree upright look.'

param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label) {
  $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $source=[IO.File]::ReadAllText($file)
  $count=([regex]::Matches($source,[regex]::Escape($before))).Count
  if($count -ne 1){throw ("PGRP v0.5.21 "+$label+" expected 1 anchor; got "+$count)}
  [IO.File]::WriteAllText($file,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host ("PGRP v0.5.21 PATCH OK: "+$label)
}
$header=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'include/pgrp_freecam_math.h')).Path
Copy-Item -LiteralPath $header -Destination (Join-Path $Root 'native/pgrp_freecam_math.h') -Force
Patch 'native/sampraknet_bridge.cpp' @'
#include "game/game.h"
'@ @'
#include "game/game.h"
#include "pgrp_freecam_math.h"
'@ 'use tested unified camera basis'
# Stop flying purely on XY: W/S now use camera's full 3D forward including Z.
Patch 'native/sampraknet_bridge.cpp' @'
            // FreeCam = ground-plane travel relative to horizontal LOOK.
            // Looking up/down must never change W/S height. Only Space and
            // Control affect altitude, independently from camera pitch.
            const float fx=std::cos(st.yaw),fy=std::sin(st.yaw);
            const float rx=-std::sin(st.yaw),ry=std::cos(st.yaw);
            float vx=0.f,vy=0.f,vz=0.f;
            const bool ahead=held('W')||held(VK_UP),back=held('S')||held(VK_DOWN);
            const bool left=held('A')||held(VK_LEFT),right=held('D')||held(VK_RIGHT);
            if(ahead){vx+=fx;vy+=fy;} // W / Up: forward along camera heading
            if(back){vx-=fx;vy-=fy;}  // S / Down: backward
            if(right){vx+=rx;vy+=ry;}
            if(left){vx-=rx;vy-=ry;}
            if(held(VK_SPACE))vz+=1.f;
            if(held(VK_CONTROL))vz-=1.f;
'@ @'
            // W/S follow exact 3D camera look vector, including its pitch.
            // A/D strafe to camera-right on the level plane. Space/Ctrl
            // retain world-up/world-down. Normalized diagonal speed.
            const bool ahead=held('W')||held(VK_UP),back=held('S')||held(VK_DOWN);
            const bool left=held('A')||held(VK_LEFT),right=held('D')||held(VK_RIGHT);
            const float fly=(ahead?1.f:0.f)-(back?1.f:0.f);
            const float strafe=(right?1.f:0.f)-(left?1.f:0.f);
            const float altitude=(held(VK_SPACE)?1.f:0.f)-
                ((held(VK_CONTROL)&&!held(VK_F11))?1.f:0.f);
            const auto dir=pgrpfc_math::FlightDirection(
                st.yaw,st.pitch,fly,strafe,altitude);
            float vx=dir.x,vy=dir.y,vz=dir.z;
'@ 'camera-relative 3D W/S movement and normalized diagonals'
# Prevent delayed "tail" motion from the persistent pending-delta queue.
Patch 'native/sampraknet_bridge.cpp' @'
        float pendingMouseX=0,pendingMouseY=0; // deferred bounded input
'@ @'
        // Raw deltas are consumed only once per camera update; no input backlog.
'@ 'remove accumulated delayed mouse motion'
Patch 'native/sampraknet_bridge.cpp' @'
        if(dx>-4000 && dx<4000 && dy>-4000 && dy<4000){
'@ @'
        if(dx>-1500 && dx<1500 && dy>-1500 && dy<1500){
'@ 'reject implausible per-HID-event motion spikes'
Patch 'native/sampraknet_bridge.cpp' @'
            constexpr float mouseScale=.00108f;
            // Avoid single-frame overflow after display transitions, while
            // allowing a full high-DPI flick without a 220-count ceiling.
            s.pendingMouseX=(std::max)(-1800.f,
                (std::min)(1800.f,s.pendingMouseX+float(dx)));
            s.pendingMouseY=(std::max)(-1800.f,
                (std::min)(1800.f,s.pendingMouseY+float(dy)));
            // Each frame moves at most ~9 degrees. Even a huge valid
            // swipe is released smoothly rather than flipping the scene.
            const float mx=(std::max)(-145.f,(std::min)(145.f,s.pendingMouseX));
            const float my=(std::max)(-145.f,(std::min)(145.f,s.pendingMouseY));
            s.pendingMouseX-=mx;
            s.pendingMouseY-=my;
'@ @'
            // One device-relative sample, one bounded rotation update.
            // No deferred mouse movement into future frames after release.
            constexpr float mouseScale=.00090f;
            const float mx=(std::max)(-280.f,(std::min)(280.f,float(dx)));
            const float my=(std::max)(-280.f,(std::min)(280.f,float(dy)));
'@ 'remove mouse movement backlog and cap single-frame angle'
Patch 'native/sampraknet_bridge.cpp' @'
                s.pendingMouseX=0.f;s.pendingMouseY=0.f;
                Log("[PGRP FC v0520] Camera mode: %s",
'@ @'
                pgrpfc::ClearMouse();
                Log("[PGRP FC v0521] Camera mode: %s",
'@ 'clear device impulse when F11 mode changes'
Patch 'native/sampraknet_bridge.cpp' @'
        }else{
            pgrpfc::ClearMouse();
            s.pendingMouseX=0.f;s.pendingMouseY=0.f;
        }
'@ @'
        }else{
            pgrpfc::ClearMouse();
        }
'@ 'drop invalid input on alt-tab/chat rather than storing it'
Patch 'native/sampraknet_bridge.cpp' @'
        // Very short frame-rate-independent rotational filtering suppresses
        // the high-frequency unfiltered mouse oscillation without the long
        // delay of the old 0.5.16 secondary camera follow.
        const float rotationAlpha=1.f-std::exp(-dt*85.f);
        s.renderYaw+=std::remainder(s.yaw-s.renderYaw,6.283185307f)*rotationAlpha;
        s.renderPitch+=std::remainder(s.pitch-s.renderPitch,6.283185307f)*rotationAlpha;
'@ @'
        // Direct one-writer orientation: old second orientation filter
        // caused a moving view to trail physical mouse motion.
        s.renderYaw=s.yaw;
        s.renderPitch=s.pitch;
'@ 'remove second camera rotational smoothing loop'
Patch 'native/sampraknet_bridge.cpp' @'
        const float cp=std::cos(pitch),sp=std::sin(pitch);
        const float cy=std::cos(s.renderYaw),sy=std::sin(s.renderYaw);
        // Orthogonal basis derived from a fixed world-up. For any supported
        // pitch the up vector has positive Z, so the horizon cannot roll.
        const float right[3]={-sy,cy,0.f};
        const float up[3]={-cy*sp,-sy*sp,cp};
        const float forward[3]={cy*cp,sy*cp,sp};
'@ @'
        const auto basis=pgrpfc_math::BuildBasis(s.renderYaw,pitch);
        const float right[3]={basis.right.x,basis.right.y,basis.right.z};
        const float up[3]={basis.up.x,basis.up.y,basis.up.z};
        const float forward[3]={basis.forward.x,basis.forward.y,basis.forward.z};
'@ 'use same tested camera basis for render and motion'
Patch 'native/sampraknet_bridge.cpp' @'
        if((++renderTick % 18000)==0)
            Log("[PGRP FC v0518] camera hook alive, frame %u",renderTick);
'@ @'
        if((++renderTick % 18000)==0)
            Log("[PGRP FC v0521] camera hook alive, frame %u",renderTick);
'@ 'update camera hook heartbeat version'
Write-Host 'PGRP v0.5.21: W/S follow camera pitch in 3D; no delayed mouse queue; shared orthogonal view basis.'

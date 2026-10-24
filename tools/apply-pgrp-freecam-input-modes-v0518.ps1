param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
  $p=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $s=[IO.File]::ReadAllText($p)
  $count=([regex]::Matches($s,[regex]::Escape($before))).Count
  if($count -ne 1){throw ("PGRP v0.5.18 "+$label+": expected 1 anchor, found "+$count)}
  [IO.File]::WriteAllText($p,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host ("PGRP v0.5.18 PATCH OK "+$label)
}
Patch 'native/sampraknet_bridge.cpp' @'
        float renderYaw=0,renderPitch=0;
        DWORD lastRenderTick=0;
'@ @'
        float renderYaw=0,renderPitch=0;
        // Two real camera modes. HorizonLock is default. F11 switches to
        // full vertical 360 flight; full loops naturally invert world-up.
        bool fullVertical=false;
        DWORD lastRenderTick=0;
'@ 'flight pitch mode stored per freecam session'
Patch 'native/sampraknet_bridge.cpp' @'
        st.pitch=(std::max)(-1.553343f,(std::min)(1.553343f,st.pitch));
'@ @'
        // Lock the horizon at startup. In Free Spin mode pitch wraps 360.
        st.pitch=(std::max)(-1.48352986f,(std::min)(1.48352986f,st.pitch));
'@ 'start with stable horizon'
Patch 'native/sampraknet_bridge.cpp' @'
            s.yaw=std::remainder(s.yaw+mx*mouseScale,6.283185307f);
            s.pitch=(std::max)(-1.553343f,
                (std::min)(1.553343f,s.pitch-my*mouseScale));
'@ @'
            // Rising-edge F11 toggles the two legitimately different camera
            // control models. 360 vertical travel necessarily entails an
            // inverted horizon while upside down; this is smooth and not a
            // mathematical gimbal flip. Locked-horizon mode never rolls.
            static bool wasF11Pressed=false;
            const bool f11Pressed=(GetAsyncKeyState(VK_F11)&0x8000)!=0;
            if(f11Pressed && !wasF11Pressed){
                s.fullVertical=!s.fullVertical;
                if(!s.fullVertical){
                    s.pitch=(std::max)(-1.48352986f,
                        (std::min)(1.48352986f,s.pitch));
                }
                Log("[PGRP FC v0518] F11 camera mode: %s",
                    s.fullVertical?"FULL_VERTICAL_360":"HORIZON_LOCK");
            }
            wasF11Pressed=f11Pressed;
            s.yaw=std::remainder(s.yaw+mx*mouseScale,6.283185307f);
            if(s.fullVertical){
                s.pitch=std::remainder(s.pitch-my*mouseScale,6.283185307f);
            }else{
                s.pitch=(std::max)(-1.48352986f,
                    (std::min)(1.48352986f,s.pitch-my*mouseScale));
            }
'@ 'offer explicit full vertical rotation without breaking level camera'
Patch 'native/sampraknet_bridge.cpp' @'
        // Raw Input comes in already as device-relative impulses; do not
        // smooth it a second time (that lagged and fluttered the view).
        s.renderYaw=s.yaw;
        s.renderPitch=s.pitch;
        const float pitch=(std::max)(-1.553343f,
            (std::min)(1.553343f,s.renderPitch));
'@ @'
        // Very short frame-rate-independent rotational filtering suppresses
        // the high-frequency unfiltered mouse oscillation without the long
        // delay of the old 0.5.16 secondary camera follow.
        const float rotationAlpha=1.f-std::exp(-dt*85.f);
        s.renderYaw+=std::remainder(s.yaw-s.renderYaw,6.283185307f)*rotationAlpha;
        s.renderPitch+=std::remainder(s.pitch-s.renderPitch,6.283185307f)*rotationAlpha;
        // The continuous trigonometric basis is valid across +/-90deg and
        // 180deg without a singular denominator. No Euler pitch clamp when
        // full-vertical mode is requested.
        const float pitch=s.fullVertical
            ?s.renderPitch
            :(std::max)(-1.48352986f,
                (std::min)(1.48352986f,s.renderPitch));
'@ 'remove hard 89 degree ceiling and damp high-frequency mouse flutter'
Patch 'native/sampraknet_bridge.cpp' @'
        static unsigned renderTick=0;
        if((++renderTick % 120)==0)
            Log("[PGRP FC v0513] post-camera hook rendering frame %u",renderTick);
'@ @'
        // Log a heartbeat only rarely; writing one line every 120 frames
        // caused excessive synchronous disk I/O on low-end PCs.
        static unsigned renderTick=0;
        if((++renderTick % 18000)==0)
            Log("[PGRP FC v0518] camera hook alive, frame %u",renderTick);
'@ 'throttle debug writes inside hot camera rendering loop'
Write-Host 'PGRP v0.5.18: upright horizon mode and opt-in full pitch loops, smooth mouse filter.'

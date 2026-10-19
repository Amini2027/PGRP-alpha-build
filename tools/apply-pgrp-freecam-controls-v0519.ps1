param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
    $p=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
    $s=[IO.File]::ReadAllText($p)
    $count=([regex]::Matches($s,[regex]::Escape($before))).Count
    if($count -ne 1){ throw ("PGRP v0.5.19 "+$label+": expected 1 anchor; got "+$count) }
    [IO.File]::WriteAllText($p,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host ("PGRP v0.5.19 PATCH OK: "+$label)
}
# Camera Z is up, and +cos(yaw),+sin(yaw) is the direction of m_vecFront.
# v0.5.18 subtracted this heading for W, so forward/backward were reversed.
Patch 'native/sampraknet_bridge.cpp' @'
            if(ahead){vx-=fx;vy-=fy;}
            if(back){vx+=fx;vy+=fy;}
'@ @'
            if(ahead){vx+=fx;vy+=fy;} // W / Up: forward along camera heading
            if(back){vx-=fx;vy-=fy;}  // S / Down: backward
'@ 'W/S direction relative to camera'
# Restore near-full +/-89 degree upright look; avoid the 85-degree ceiling.
# A genuinely continuous FULL 360 vertical rotation necessarily rotates world-up.
# F11 remains an *explicit opt-in*; default always keeps the horizon upright.
Patch 'native/sampraknet_bridge.cpp' @'
        st.pitch=(std::max)(-1.48352986f,(std::min)(1.48352986f,st.pitch));
'@ @'
        st.pitch=(std::max)(-1.55334306f,(std::min)(1.55334306f,st.pitch));
'@ 'default upright pitch initialization'
Patch 'native/sampraknet_bridge.cpp' @'
                    s.pitch=(std::max)(-1.48352986f,
                        (std::min)(1.48352986f,s.pitch));
'@ @'
                    s.pitch=(std::max)(-1.55334306f,
                        (std::min)(1.55334306f,s.pitch));
'@ 'return from full-spin uses upright 89 degree bound'
Patch 'native/sampraknet_bridge.cpp' @'
                s.pitch=(std::max)(-1.48352986f,
                    (std::min)(1.48352986f,s.pitch-my*mouseScale));
'@ @'
                s.pitch=(std::max)(-1.55334306f,
                    (std::min)(1.55334306f,s.pitch-my*mouseScale));
'@ 'upright mouse pitch limit'
Patch 'native/sampraknet_bridge.cpp' @'
            :(std::max)(-1.48352986f,
                (std::min)(1.48352986f,s.renderPitch));
'@ @'
            :(std::max)(-1.55334306f,
                (std::min)(1.55334306f,s.renderPitch));
'@ 'upright camera render pitch limit'
# Do not discard user input from high-DPI mice by clipping EVERY render frame
# to 1000 device counts. Reject only extreme discontinuities from device/focus.
Patch 'native/sampraknet_bridge.cpp' @'
            const float mx=float((std::max)(-1000L,(std::min)(1000L,dx)));
            const float my=float((std::max)(-1000L,(std::min)(1000L,dy)));
'@ @'
            const float mx=float((std::max)(-12000L,(std::min)(12000L,dx)));
            const float my=float((std::max)(-12000L,(std::min)(12000L,dy)));
'@ 'prevent artificial high-DPI mouse saturation'
Patch 'native/sampraknet_bridge.cpp' @'
        if(dx>-2000 && dx<2000 && dy>-2000 && dy<2000){
'@ @'
        if(dx>-12000 && dx<12000 && dy>-12000 && dy<12000){
'@ 'accept high-DPI relative hardware packets'
# Explain the two distinct camera modes to the player *in-game*.
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0518] F11 camera mode: %s",
                    s.fullVertical?"FULL_VERTICAL_360":"HORIZON_LOCK");
'@ @'
                Log("[PGRP FC v0519] F11 camera mode: %s",
                    s.fullVertical?"FULL_VERTICAL_360":"UPRIGHT_360_YAW");
                g_chat.PushLineAsync(s.fullVertical
                    ? "[PGRP FreeCam] FULL VERTICAL 360: upside-down world after 90 deg is expected. F11 for upright."
                    : "[PGRP FreeCam] UPRIGHT: 360 yaw, +/-89 pitch, no upside-down world. F11 for vertical loops.");
'@ 'make F11 mode discoverable in the game HUD'
Write-Host 'PGRP v0.5.19: corrected W/S, upright +/-89deg pitch, no raw-mouse saturation, explicit vertical-spin toggle.'

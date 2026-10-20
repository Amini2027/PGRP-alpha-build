param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
    $full=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
    $s=[IO.File]::ReadAllText($full)
    $n=([regex]::Matches($s,[regex]::Escape($before))).Count
    if($n -ne 1){throw "PGRP v0.5.23 $label: expected one anchor, found $n"}
    [IO.File]::WriteAllText($full,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0.5.23 PATCH OK: $label"
}
# The v0522 log confirmed that FULL_VERTICAL_360 is an actual source of
# upside-down camera roll. The user does not want intentional inversion.
# Remove the vertical-spin path altogether, including Ctrl+F11 activation.
Patch 'native/sampraknet_bridge.cpp' @'
            const bool ctrlPressed=(GetAsyncKeyState(VK_CONTROL)&0x8000)!=0;
            if(f11Pressed && !s.lastF11){
                // F11 always returns to stable upright mode. Full vertical
                // inversion is available ONLY after explicit Ctrl+F11.
                s.fullVertical=ctrlPressed ? !s.fullVertical : false;
'@ @'
            if(f11Pressed && !s.lastF11){
                // F11 only reasserts upright horizon. Ctrl+F11 cannot
                // enable inverted flight (Ctrl remains the descent key).
                s.fullVertical=false;
'@ 'disable full vertical mode even with Ctrl+F11'
Patch 'native/sampraknet_bridge.cpp' @'
            if(s.fullVertical){
                s.pitch=std::remainder(s.pitch-my*mouseScale,6.283185307f);
            }else{
                s.pitch=(std::max)(-1.55334306f,
                    (std::min)(1.55334306f,s.pitch-my*mouseScale));
            }
'@ @'
            // Never wrap pitch through the poles: horizon must remain upright.
            s.fullVertical=false;
            s.pitch=(std::max)(-1.3962634f,
                (std::min)(1.3962634f,s.pitch-my*mouseScale));
'@ 'force +/-80 degree stable camera at every mouse event'
Patch 'native/sampraknet_bridge.cpp' @'
        const float pitch=s.fullVertical
            ?s.renderPitch
            :(std::max)(-1.55334306f,
                (std::min)(1.55334306f,s.renderPitch));
'@ @'
        const float pitch=(std::max)(-1.3962634f,
            (std::min)(1.3962634f,s.renderPitch));
'@ 'render with the same upright pitch clamp as the input controller'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0521] Camera mode: %s",
                    s.fullVertical?"FULL_VERTICAL_360":"UPRIGHT_360_YAW");
'@ @'
                Log("[PGRP FC v0523] Camera mode: UPRIGHT_LOCKED");
'@ 'never advertise or log a vertical-spin mode'
Patch 'native/sampraknet_bridge.cpp' @'
        g_chat.PushLineAsync(spinning
            ? std::string("[PGRP FreeCam] FULL VERTICAL 360: inversion beyond 90 is expected. F11 resets.")
            : std::string("[PGRP FreeCam v0.5.22] UPRIGHT: full 360 yaw, +/-89 pitch. Ctrl+F11 enters vertical spin."));
'@ @'
        (void)spinning;
        g_chat.PushLineAsync(std::string(
            "[PGRP FreeCam v0.5.23] UPRIGHT LOCKED: 360 yaw, +/-80 pitch. W/S follows view. F11 resets."));
'@ 'show correct locked camera mode in in-game chat'
# Guard against a pitch inherited from the original GTA camera when starting.
Patch 'native/sampraknet_bridge.cpp' @'
        st.pitch=(std::max)(-1.55334306f,(std::min)(1.55334306f,st.pitch));
'@ @'
        st.pitch=(std::max)(-1.3962634f,(std::min)(1.3962634f,st.pitch));
'@ 'start freecam in upright safe range'
# The F11 rescue clamp is a separate occurrence with the same original limit.
Patch 'native/sampraknet_bridge.cpp' @'
                    s.pitch=(std::max)(-1.55334306f,
                        (std::min)(1.55334306f,s.pitch));
'@ @'
                    s.pitch=(std::max)(-1.3962634f,
                        (std::min)(1.3962634f,s.pitch));
'@ 'F11 restores safe pitch even after old camera state'
# Mouse packets are consumed once per render. Clamp the angular impulse
# further; no buffering or delayed spin. Keep 360-degree horizontal yaw.
Patch 'native/sampraknet_bridge.cpp' @'
            constexpr float mouseScale=.00090f;
            const float mx=(std::max)(-280.f,(std::min)(280.f,float(dx)));
            const float my=(std::max)(-280.f,(std::min)(280.f,float(dy)));
'@ @'
            constexpr float mouseScale=.00065f;
            const float mx=(std::max)(-140.f,(std::min)(140.f,float(dx)));
            const float my=(std::max)(-140.f,(std::min)(140.f,float(dy)));
            s.lastRawDx=dx;s.lastRawDy=dy;
'@ 'cap mouse to 5.2 degrees/frame with no deferred backlog'
# v0521 state has a raw-mouse note between renderYaw and lastF11.
Patch 'native/sampraknet_bridge.cpp' @'
        float renderYaw=0,renderPitch=0;
        // Raw deltas are consumed only once per camera update; no input backlog.
        bool lastF11=false;
'@ @'
        float renderYaw=0,renderPitch=0;
        // Diagnostics: raw impulses actually consumed by the camera hook.
        long lastRawDx=0,lastRawDy=0;
        // Raw deltas are consumed only once per camera update; no input backlog.
        bool lastF11=false;
'@ 'record exact raw mouse impulses used in frame'
# Reset debug deltas on alt-tab/chat, so the log never implies stale input.
Patch 'native/sampraknet_bridge.cpp' @'
        }else{
            pgrpfc::ClearMouse();
        }
        // QueryPerformanceCounter has sub-millisecond resolution
'@ @'
        }else{
            pgrpfc::ClearMouse();
            s.lastRawDx=0;s.lastRawDy=0;
        }
        // QueryPerformanceCounter has sub-millisecond resolution
'@ 'clear raw debug values when input is not active'
# Diagnostic marker allows proof of *which DLL* GTA actually loaded.
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0522] BUILD=matrixfix-20261020 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0523] BUILD=upright-rawguard-20261020 DLL=%s",dllPath);
'@ 'identify loaded DLL absolute path'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0522] BUILD=matrixfix-20261020 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0523] BUILD=upright-rawguard-20261020 DLL_PATH_UNAVAILABLE");
'@ 'identify diagnostic fallback when DLL path unavailable'
# Add runtime telemetry at 2 Hz rather than the old 1 sample per 240 frames.
Patch 'native/sampraknet_bridge.cpp' @'
        if((matrixCheckCount % 240)==0) {
'@ @'
        if((matrixCheckCount % 120)==0) {
'@ 'sample camera data twice per 60fps second'
Patch 'native/sampraknet_bridge.cpp' @'
            Log("[PGRP FC v0522] frame=%u yaw=%.4f pitch=%.4f pos=(%.2f,%.2f,%.2f) forward=(%.3f,%.3f,%.3f) up=(%.3f,%.3f,%.3f) matrixDotF=%.5f matrixDotU=%.5f",
                matrixCheckCount,s.yaw,s.pitch,s.x,s.y,s.z,forward[0],forward[1],forward[2],
                up[0],up[1],up[2],dotFF,dotUU);
'@ @'
            Log("[PGRP FC v0523] frame=%u raw=(%ld,%ld) yaw=%.4f pitch=%.4f pos=(%.2f,%.2f,%.2f) forward=(%.3f,%.3f,%.3f) up=(%.3f,%.3f,%.3f) matrixDotF=%.5f matrixDotU=%.5f mode=UPRIGHT_LOCKED",
                matrixCheckCount,s.lastRawDx,s.lastRawDy,s.yaw,s.pitch,s.x,s.y,s.z,
                forward[0],forward[1],forward[2],up[0],up[1],up[2],dotFF,dotUU);
'@ 'log live input and basis to diagnose any remaining flutter'
# Raw packet integrity: reject corrupt >1500 HID events and cap input
# accumulation so pathological WM_INPUT bursts cannot overflow signed long.
Patch 'native/sampraknet_bridge.cpp' @'
        if(dx>-1500 && dx<1500 && dy>-1500 && dy<1500){
            pgrpfc::rawX.fetch_add(dx,std::memory_order_relaxed);
            pgrpfc::rawY.fetch_add(dy,std::memory_order_relaxed);
        }
'@ @'
        if(dx>-1500 && dx<1500 && dy>-1500 && dy<1500){
            // Keep at most one reasonable frame's worth of pending motion.
            // The render hook exchange(0) remains the only consumer.
            auto boundedAdd=[](std::atomic<long>& slot,long value) {
                long current=slot.load(std::memory_order_relaxed);
                long next;
                do {
                    next=(std::max)(-280L,(std::min)(280L,current+value));
                } while(!slot.compare_exchange_weak(current,next,
                         std::memory_order_relaxed,std::memory_order_relaxed));
            };
            boundedAdd(pgrpfc::rawX,dx);
            boundedAdd(pgrpfc::rawY,dy);
        }
'@ 'bound accumulated WM_INPUT deltas before consumption'
Write-Host 'PGRP v0.5.23: no full-vertical inversion, safe pitch, bounded mouse input, runtime diagnostics.'

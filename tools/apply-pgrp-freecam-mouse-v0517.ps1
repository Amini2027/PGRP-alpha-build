param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$file,[string]$before,[string]$after,[string]$tag){
 $p=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
 $s=[IO.File]::ReadAllText($p)
 $matches=([regex]::Matches($s,[regex]::Escape($before))).Count
 if($matches -ne 1){throw ("v0517 "+$tag+": expected 1 anchor, got "+$matches)}
 [IO.File]::WriteAllText($p,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
 Write-Host ("PGRP v0517 PATCH OK "+$tag)
}
# Render hook owns mouse look, never the network/controller tick. Using
# per-render raw relative deltas avoids 30/60 Hz input quantisation and
# mouse-movement jumps when rendering faster than the flight simulation.
Patch 'native/sampraknet_bridge.cpp' @'
            const long dx=rawX.exchange(0,std::memory_order_relaxed);
            const long dy=rawY.exchange(0,std::memory_order_relaxed);
            // Reduce mouse sensitivity and clamp rare large device deltas.
            // Mouse stays device-relative; no Windows cursor warping.
            // Stable zero-roll mouse look. Keep pitch a safe distance
            // from +/-90 degrees: horizon never overturns at the poles.
            // Wrap yaw so extremely long flights cannot lose precision.
            const float mouseScale=0.00098f;
            const float deltaX=float((std::max)(-220L,(std::min)(220L,dx)));
            const float deltaY=float((std::max)(-220L,(std::min)(220L,dy)));
            st.yaw=std::remainder(st.yaw+deltaX*mouseScale,6.283185307f);
            st.pitch=(std::max)(-1.20f,
                (std::min)(1.20f,st.pitch-deltaY*mouseScale));
'@ @'
            // Mouse rotation is consumed by PgrpFreeCamAfterCameraProcess()
            // at actual render frame rate, not by this capped movement tick.
            // W/S still uses the most recent view yaw for ground-plane flight.
'@ 'remove 60Hz mouse look and cumulative input clipping'
Patch 'native/sampraknet_bridge.cpp' @'
        st.pitch=(std::max)(-1.20f,(std::min)(1.20f,st.pitch));
'@ @'
        // Allow near-vertical sight (+/-89 degrees) without crossing over
        // the top/bottom and inverting the fixed world-up.
        st.pitch=(std::max)(-1.553343f,(std::min)(1.553343f,st.pitch));
'@ 'freecam start angle nearly full pitch'
Patch 'native/sampraknet_bridge.cpp' @'
        const DWORD now=GetTickCount();
        float dt=(std::min)(.050f,float(now-s.lastRenderTick)*.001f);
        if(dt<0.f)dt=0.f;
        s.lastRenderTick=now;
        const float positionAlpha=1.f-std::exp(-dt*16.f);
        const float rotationAlpha=1.f-std::exp(-dt*22.f);
        s.renderX+=(s.x-s.renderX)*positionAlpha;
        s.renderY+=(s.y-s.renderY)*positionAlpha;
        s.renderZ+=(s.z-s.renderZ)*positionAlpha;
        s.renderYaw+=std::remainder(s.yaw-s.renderYaw,6.283185307f)*rotationAlpha;
        s.renderPitch+=(s.pitch-s.renderPitch)*rotationAlpha;
        const float pitch=(std::max)(-1.20f,(std::min)(1.20f,s.renderPitch));
'@ @'
        // Collect real device-relative mouse movement at the exact camera
        // render cadence. No cursor warps, no fixed 30/60Hz look sampling,
        // no deliberate rotational latency. Only the flight mouse mode
        // receives these deltas; ordinary GTA input remains untouched.
        const HWND fg=GetForegroundWindow();
        const bool focused=(g_hwnd && IsWindow(g_hwnd) &&
             (fg==g_hwnd || fg==GetAncestor(g_hwnd,GA_ROOT)));
        const bool modal=g_chat.IsActive() ||
            opensamp::gui::Dialog::Get().IsActive();
        if(focused && !modal && !s.exitPending){
            const long dx=pgrpfc::rawX.exchange(0,std::memory_order_relaxed);
            const long dy=pgrpfc::rawY.exchange(0,std::memory_order_relaxed);
            constexpr float mouseScale=.00108f;
            // Avoid single-frame overflow after display transitions, while
            // allowing a full high-DPI flick without a 220-count ceiling.
            const float mx=float((std::max)(-1000L,(std::min)(1000L,dx)));
            const float my=float((std::max)(-1000L,(std::min)(1000L,dy)));
            s.yaw=std::remainder(s.yaw+mx*mouseScale,6.283185307f);
            s.pitch=(std::max)(-1.553343f,
                (std::min)(1.553343f,s.pitch-my*mouseScale));
        }else{
            pgrpfc::ClearMouse();
        }
        // QueryPerformanceCounter has sub-millisecond resolution, unlike
        // GetTickCount() whose 15.6ms quantisation caused visibly stepped
        // camera interpolation on 60/120/144Hz displays.
        static LARGE_INTEGER qpcFrequency{};
        if(!qpcFrequency.QuadPart) QueryPerformanceFrequency(&qpcFrequency);
        LARGE_INTEGER counter{};
        QueryPerformanceCounter(&counter);
        static LONGLONG previousCounter=0;
        const double frameSeconds=previousCounter && qpcFrequency.QuadPart
            ? double(counter.QuadPart-previousCounter)/double(qpcFrequency.QuadPart)
            : 1.0/60.0;
        previousCounter=counter.QuadPart;
        const float dt=(std::max)(0.f,
            (std::min)(.050f,float(frameSeconds)));
        const float positionAlpha=1.f-std::exp(-dt*20.f);
        s.renderX+=(s.x-s.renderX)*positionAlpha;
        s.renderY+=(s.y-s.renderY)*positionAlpha;
        s.renderZ+=(s.z-s.renderZ)*positionAlpha;
        // Raw Input comes in already as device-relative impulses; do not
        // smooth it a second time (that lagged and fluttered the view).
        s.renderYaw=s.yaw;
        s.renderPitch=s.pitch;
        const float pitch=(std::max)(-1.553343f,
            (std::min)(1.553343f,s.renderPitch));
'@ 'high-resolution render cadence, independent mouse look, full pitch'
Write-Host 'PGRP v0.5.17 camera now supports smooth 360 degree yaw, near vertical look.'

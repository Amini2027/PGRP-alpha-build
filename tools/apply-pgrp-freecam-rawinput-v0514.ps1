param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$file,[string]$before,[string]$after,[string]$label){
 $p=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
 $s=[IO.File]::ReadAllText($p)
 $n=([regex]::Matches($s,[regex]::Escape($before))).Count
 if($n -ne 1){throw ("FreeCam 0.5.14 "+$label+" expected 1 match, found "+$n)}
 [IO.File]::WriteAllText($p,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
 Write-Host ("PGRP v0.5.14 PATCH OK "+$label)
}
Patch 'native/sampraknet_bridge.cpp' @'
#include <algorithm>
#include <cstring>
'@ @'
#include <algorithm>
#include <atomic>
#include <cstring>
'@ 'atomic raw mouse buffers'
Patch 'native/sampraknet_bridge.h' @'
    bool PgrpFreeCamIsActive();
'@ @'
    bool PgrpFreeCamIsActive();
    void PgrpFreeCamRawMouse(long dx,long dy);
    void PgrpFreeCamResetRawMouse();
'@ 'export low-overhead mouse queue'
Patch 'native/sampraknet_bridge.cpp' @'
namespace pgrpfc {
    struct State {
'@ @'
namespace pgrpfc {
    // WM_INPUT reports actual device-relative motion; no cursor warping,
    // no feedback loop with DirectInput or GTA's own mouse recenter.
    static std::atomic<long> rawX{0},rawY{0};
    static void ClearMouse(){
        rawX.store(0,std::memory_order_relaxed);
        rawY.store(0,std::memory_order_relaxed);
    }
    struct State {
'@ 'mouse queue once for each native frame'
Patch 'native/sampraknet_bridge.cpp' @'
        st=State{};
        st.x=x;st.y=y;st.z=z;
'@ @'
        st=State{};
        ClearMouse();
        st.x=x;st.y=y;st.z=z;
'@ 'reset on freecam entry'
Patch 'native/sampraknet_bridge.cpp' @'
        st.active=false;
        if(auto* ped=gta::sa::GetLocalPlayerPed())
'@ @'
        st.active=false;
        ClearMouse();
        if(auto* ped=gta::sa::GetLocalPlayerPed())
'@ 'reset on freecam release'
Patch 'native/sampraknet_bridge.cpp' @'
            RECT rect{};
            if(GetClientRect(g_hwnd,&rect)) {
                POINT origin{(rect.right-rect.left)/2,(rect.bottom-rect.top)/2};
                ClientToScreen(g_hwnd,&origin);
                POINT current{};
                if(GetCursorPos(&current)) {
                    const LONG dx=current.x-origin.x,dy=current.y-origin.y;
                    if(std::abs(dx)<400 && std::abs(dy)<400) {
                        st.yaw+=float(dx)*0.0028f;
                        st.pitch-=float(dy)*0.0028f;
                        if(st.pitch>1.48f)st.pitch=1.48f;
                        if(st.pitch<-1.48f)st.pitch=-1.48f;
                    }
                    SetCursorPos(origin.x,origin.y);
                }
            }
            auto held=[](int vk){return (GetAsyncKeyState(vk)&0x8000)!=0;};
            const float cp=std::cos(st.pitch),sp=std::sin(st.pitch);
            const float fx=cp*std::cos(st.yaw),fy=cp*std::sin(st.yaw),fz=sp;
            const float rx=-std::sin(st.yaw),ry=std::cos(st.yaw);
            float vx=0,vy=0,vz=0;
            const bool ahead=held('W')||held(VK_UP),back=held('S')||held(VK_DOWN);
            const bool left=held('A')||held(VK_LEFT),right=held('D')||held(VK_RIGHT);
            if(ahead){vx+=fx;vy+=fy;vz+=fz;}
            if(back){vx-=fx;vy-=fy;vz-=fz;}
            if(right){vx+=rx;vy+=ry;}
            if(left){vx-=rx;vy-=ry;}
            if(held(VK_SPACE))vz+=1.f;
            if(held(VK_CONTROL))vz-=1.f;
'@ @'
            // Raw Input is device-relative, independent of cursor position,
            // resolution, Windows pointer acceleration and GTA recentering.
            // Consume at most 400 counts/tick to reject monitor-focus spikes.
            const long dx=rawX.exchange(0,std::memory_order_relaxed);
            const long dy=rawY.exchange(0,std::memory_order_relaxed);
            const float mouseScale=0.00165f;
            st.yaw += float((std::max)(-400L,(std::min)(400L,dx)))*mouseScale;
            st.pitch -= float((std::max)(-400L,(std::min)(400L,dy)))*mouseScale;
            st.pitch=(std::max)(-1.48f,(std::min)(1.48f,st.pitch));

            auto held=[](int vk){return (GetAsyncKeyState(vk)&0x8000)!=0;};
            // FreeCam = ground-plane travel relative to horizontal LOOK.
            // Looking up/down must never change W/S height. Only Space and
            // Control affect altitude, independently from camera pitch.
            const float fx=std::cos(st.yaw),fy=std::sin(st.yaw);
            const float rx=-std::sin(st.yaw),ry=std::cos(st.yaw);
            float vx=0.f,vy=0.f,vz=0.f;
            const bool ahead=held('W')||held(VK_UP),back=held('S')||held(VK_DOWN);
            const bool left=held('A')||held(VK_LEFT),right=held('D')||held(VK_RIGHT);
            if(ahead){vx+=fx;vy+=fy;}
            if(back){vx-=fx;vy-=fy;}
            if(right){vx+=rx;vy+=ry;}
            if(left){vx-=rx;vy-=ry;}
            if(held(VK_SPACE))vz+=1.f;
            if(held(VK_CONTROL))vz-=1.f;
'@ 'level WASD flight and jitter-free raw mouse look'
Patch 'native/sampraknet_bridge.cpp' @'
        }
        // SCM opcodes 015F and 0160 update position and target of camera.
'@ @'
        }
        else
        {
            // Drop queued mouse deltas on alt-tab, chat, settings or when
            // waiting for the final server teleport. No deferred spin.
            ClearMouse();
        }
        // SCM opcodes 015F and 0160 update position and target of camera.
'@ 'discard stale delta while unfocused or modal'
Patch 'native/sampraknet_bridge.cpp' @'
    bool PgrpFreeCamIsActive(){
        return g_pgrpEndpoint && iAreWeConnected && pgrpfc::st.active;
    }
'@ @'
    bool PgrpFreeCamIsActive(){
        return g_pgrpEndpoint && iAreWeConnected && pgrpfc::st.active;
    }
    void PgrpFreeCamRawMouse(long dx,long dy){
        if(!PgrpFreeCamIsActive())return;
        if(dx>-2000 && dx<2000 && dy>-2000 && dy<2000){
            pgrpfc::rawX.fetch_add(dx,std::memory_order_relaxed);
            pgrpfc::rawY.fetch_add(dy,std::memory_order_relaxed);
        }
    }
    void PgrpFreeCamResetRawMouse(){pgrpfc::ClearMouse();}
'@ 'bridge windows input callback'
Patch 'native/gui/imgui_manager.cpp' @'
    g_hwnd=hwnd;
    g_dev=dev;
    IMGUI_CHECKVERSION();
'@ @'
    g_hwnd=hwnd;
    g_dev=dev;
    // Windows Raw Input (foreground only); do NOT warp the OS cursor.
    // Registration only adds low-cost WM_INPUT packets to GTA's HWND.
    RAWINPUTDEVICE mouse{};
    mouse.usUsagePage=0x01; // Generic Desktop
    mouse.usUsage=0x02;     // Mouse
    mouse.dwFlags=0;        // Foreground: never capture on Alt-Tab
    mouse.hwndTarget=hwnd;
    if(!RegisterRawInputDevices(&mouse,1,sizeof(mouse)))
        OutputDebugStringA("[FreeCam] Raw mouse registration failed\n");
    IMGUI_CHECKVERSION();
'@ 'register actual relative mouse source'
Patch 'native/gui/imgui_manager.cpp' @'
    if (g_imgui_init)
    {
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
'@ @'
    if (g_imgui_init)
    {
        // A raw mouse packet is measured by the hardware and cannot include
        // synthetic SetCursorPos events or accumulated Win32 mouse motion.
        if(msg==WM_INPUT && opensamp::bridge::PgrpFreeCamIsActive())
        {
            RAWINPUT packet{};
            UINT bytes=sizeof(packet);
            if(GetRawInputData(reinterpret_cast<HRAWINPUT>(lParam),RID_INPUT,
                    &packet,&bytes,sizeof(RAWINPUTHEADER))==bytes &&
               packet.header.dwType==RIM_TYPEMOUSE &&
               !(packet.data.mouse.usFlags&MOUSE_MOVE_ABSOLUTE))
            {
                opensamp::bridge::PgrpFreeCamRawMouse(
                    packet.data.mouse.lLastX,packet.data.mouse.lLastY);
            }
        }
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
'@ 'listen to real mouse device WM_INPUT'
Write-Host 'PGRP v0.5.14 FreeCam now uses level-plane WASD and independent raw mouse input.'

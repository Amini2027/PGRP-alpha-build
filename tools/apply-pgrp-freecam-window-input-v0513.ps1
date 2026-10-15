param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$relative,[string]$before,[string]$after,[string]$label){
 $file=(Resolve-Path -LiteralPath (Join-Path $Root $relative)).Path
 $source=[IO.File]::ReadAllText($file)
 $count=([regex]::Matches($source,[regex]::Escape($before))).Count
 if($count -ne 1){throw ("PGRP 0.5.13 "+$label+" anchor count "+$count)}
 [IO.File]::WriteAllText($file,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
 Write-Host ("PATCH OK 0.5.13 "+$label)
}
# ROOT CAUSE: the GUI's global g_hwnd was always nullptr, while d3d.cpp
# has a *different static* g_hwnd. Native FreeCam's input path required the
# GUI global hwnd to be foreground, therefore every key/mouse was ignored.
Patch 'native/gui/imgui_manager.cpp' @'
void im_gui_init(HWND hwnd, IDirect3DDevice9* dev)
{
    IMGUI_CHECKVERSION();
'@ @'
void im_gui_init(HWND hwnd, IDirect3DDevice9* dev)
{
    // d3d.cpp has a separate static g_hwnd: previous code never copied it
    // into this module. This left the FreeCam foreground test permanently
    // false and also broke keyboard-release / shutdown window ownership.
    g_hwnd=hwnd;
    g_dev=dev;
    IMGUI_CHECKVERSION();
'@ 'initialize real game HWND'
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamAfterCameraProcess();
'@ @'
    void PgrpFreeCamAfterCameraProcess();
    bool PgrpFreeCamIsActive();
'@ 'expose freecam input state'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamAfterCameraProcess(){
'@ @'
    bool PgrpFreeCamIsActive(){
        return g_pgrpEndpoint && iAreWeConnected && pgrpfc::st.active;
    }
    void PgrpFreeCamAfterCameraProcess(){
'@ 'public local freecam state'
Patch 'native/gui/imgui_manager.cpp' @'
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();

        // In PGRP the native TAB scoreboard is disabled for ordinary players.
'@ @'
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
        // Native FreeCam polls physical keys (GetAsyncKeyState), not the GTA
        // on-foot controller. Prevent the normal ped state from consuming
        // those keys while flying; KEYUP is always delivered to avoid sticky
        // controls when exiting FreeCam.
        if(opensamp::bridge::PgrpFreeCamIsActive() &&
           !g_chat.IsModal() && !dialog_active)
        {
            if((msg==WM_KEYDOWN || msg==WM_SYSKEYDOWN) &&
               IsPgrpMovementKey(wParam)) return 0;
            if((msg==WM_KEYUP || msg==WM_SYSKEYUP) &&
               IsPgrpMovementKey(wParam))
               return CallWindowProc(g_orig_wnd_proc,hWnd,msg,wParam,lParam);
        }

        // In PGRP the native TAB scoreboard is disabled for ordinary players.
'@ 'route flight keys separately from ped movement'
Patch 'native/sampraknet_bridge.cpp' @'
#include "gui/dialog.hpp"
'@ @'
#include "gui/dialog.hpp"
#include "gui/gui.h"
'@ 'declare ReleaseGameMovementKeys correctly'
Patch 'native/sampraknet_bridge.cpp' @'
        st.active=true;
        if(auto* ped=gta::sa::GetLocalPlayerPed())
'@ @'
        st.active=true;
        // Flush game movement keys stuck before spectator mode. The FreeCam
        // then uses raw physical keys, while the ordinary ped stays frozen.
        ReleaseGameMovementKeys();
        Log("[PGRP FC 0.5.13] BEGIN hwnd=%p foreground=%p at %.3f %.3f %.3f",
            g_hwnd,GetForegroundWindow(),st.x,st.y,st.z);
        if(auto* ped=gta::sa::GetLocalPlayerPed())
'@ 'release sticky controls at activation'
Patch 'native/sampraknet_bridge.cpp' @'
        const bool focus=(g_hwnd != nullptr &&
            (GetForegroundWindow()==g_hwnd ||
             GetForegroundWindow()==GetAncestor(g_hwnd,GA_ROOT)));
'@ @'
        const HWND foreground=GetForegroundWindow();
        // Use the GUI's now-initialized actual GTA HWND. A separate D3D
        // static g_hwnd previously masked this zero-global bug.
        const bool focus=(g_hwnd && IsWindow(g_hwnd) &&
             (foreground==g_hwnd || foreground==GetAncestor(g_hwnd,GA_ROOT) ||
              IsChild(g_hwnd,foreground)));
'@ 'fixed focus acquisition for raw WASD and mouse'
Patch 'native/sampraknet_bridge.cpp' @'
            ped->bIsVisible=false;
            ped->SetPosition(st.x,st.y,st.z-2.f);
'@ @'
            // GTA can reset entity render flags during its world update;
            // suppress it continuously while local FreeCam is active.
            ped->bIsVisible=false;
            ped->SetPosition(st.x,st.y,st.z-2.f);
'@ 'maintain ped hidden while flying'
Patch 'native/sampraknet_bridge.cpp' @'
        if(now-st.lastDiagnostic>=1000)
        {
            st.lastDiagnostic=now;
            Log("[PGRP FC v0511] camera=(%.2f %.2f %.2f) yaw=%.2f pitch=%.2f focus=%u",
                st.x,st.y,st.z,st.yaw,st.pitch,unsigned(focus));
        }
'@ @'
        if(now-st.lastDiagnostic>=1000)
        {
            st.lastDiagnostic=now;
            auto* ped=gta::sa::GetLocalPlayerPed();
            Log("[PGRP FC v0513] cam=(%.2f %.2f %.2f) dir=(%.2f %.2f) HWND=%p focus=%u ped=%p hidden=%u",
                st.x,st.y,st.z,st.yaw,st.pitch,g_hwnd,unsigned(focus),ped,
                unsigned(ped ? !ped->bIsVisible : 0));
        }
'@ 'log window, camera, ped hiding for one-pass diagnostic'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamAfterCameraProcess(){
        if(!pgrpfc::st.active || !g_pgrpEndpoint || !iAreWeConnected)
            return;
'@ @'
    void PgrpFreeCamAfterCameraProcess(){
        if(!pgrpfc::st.active || !g_pgrpEndpoint || !iAreWeConnected)
            return;
        static unsigned renderTick=0;
        if((++renderTick % 120)==0)
            Log("[PGRP FC v0513] post-camera hook rendering frame %u",renderTick);
'@ 'prove actual GTA camera process hook fires'
Write-Host 'PGRP 0.5.13: GTA window ownership, camera input and ped visibility fixed.'

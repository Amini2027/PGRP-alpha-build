param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label) {
    $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
    $source=[IO.File]::ReadAllText($file)
    $count=([regex]::Matches($source,[regex]::Escape($before))).Count
    if($count -ne 1) { throw "FreeCam 0.5.15 '$label' anchor count: $count (must equal 1)" }
    [IO.File]::WriteAllText($file,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0.5.15 PATCH OK: $label"
}
# Camera's rendered front vector in the GTA custom fixed-camera frame is
# opposite the controller's +XY convention in v0.5.14. Correct W/S only.
Patch 'native/sampraknet_bridge.cpp' @'
            if(ahead){vx+=fx;vy+=fy;}
            if(back){vx-=fx;vy-=fy;}
'@ @'
            if(ahead){vx-=fx;vy-=fy;}
            if(back){vx+=fx;vy+=fy;}
'@ 'invert W/S without changing A/D or altitude'
Patch 'native/sampraknet_bridge.cpp' @'
            const float mouseScale=0.00165f;
            st.yaw += float((std::max)(-400L,(std::min)(400L,dx)))*mouseScale;
            st.pitch -= float((std::max)(-400L,(std::min)(400L,dy)))*mouseScale;
'@ @'
            // Reduce mouse sensitivity and clamp rare large device deltas.
            // Mouse stays device-relative; no Windows cursor warping.
            const float mouseScale=0.00118f;
            st.yaw += float((std::max)(-225L,(std::min)(225L,dx)))*mouseScale;
            st.pitch -= float((std::max)(-225L,(std::min)(225L,dy)))*mouseScale;
'@ 'calm device-relative mouse look'
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamResetRawMouse();
'@ @'
    void PgrpFreeCamResetRawMouse();
    bool PgrpFreeCamWantsRawMouse();
'@ 'expose active flight mouse lifecycle'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamResetRawMouse(){pgrpfc::ClearMouse();}
'@ @'
    void PgrpFreeCamResetRawMouse(){pgrpfc::ClearMouse();}
    bool PgrpFreeCamWantsRawMouse(){
        return PgrpFreeCamIsActive() && !pgrpfc::st.exitPending;
    }
'@ 'no input capture while waiting for exit teleport'

# Fix root cause of mouse broken OUTSIDE FreeCam. Prior installer registered a
# raw mouse at ImGui INIT and never unregistered it, overwriting GTA's own
# process-global raw HID registration for the lifetime of the game.
Patch 'native/gui/imgui_manager.cpp' @'
#include <d3d9.h>
'@ @'
#include <d3d9.h>
#include <array>
'@ 'mouse registration snapshot storage'
Patch 'native/gui/imgui_manager.cpp' @'
    // Windows Raw Input (foreground only); do NOT warp the OS cursor.
    // Registration only adds low-cost WM_INPUT packets to GTA's HWND.
    RAWINPUTDEVICE mouse{};
    mouse.usUsagePage=0x01; // Generic Desktop
    mouse.usUsage=0x02;     // Mouse
    mouse.dwFlags=0;        // Foreground: never capture on Alt-Tab
    mouse.hwndTarget=hwnd;
    if(!RegisterRawInputDevices(&mouse,1,sizeof(mouse)))
        OutputDebugStringA("[FreeCam] Raw mouse registration failed\n");
'@ @'
    // Never register a new raw mouse device at startup. It replaces the
    // process's existing GTA mouse registration even in ordinary play.
    // FreeCam input ownership is switched in draw_ui(), and restored on exit.
'@ 'remove global Raw Input hijack'
Patch 'native/gui/imgui_manager.cpp' @'
HWND g_hwnd = nullptr;
IDirect3DDevice9* g_dev = nullptr;
'@ @'
HWND g_hwnd = nullptr;
IDirect3DDevice9* g_dev = nullptr;

// Raw Input registration is process-global for each HID usage pair.
// Capture its original state on FIRST entering FreeCam, install our device
// for flight only, then restore the original exactly on exit/focus loss.
// Ordinary GTA mode must not see any Raw Input registration changes.
static bool g_pgrpRawInFlight=false;
static bool g_pgrpHadMouseRegistration=false;
static RAWINPUTDEVICE g_pgrpPreviousMouseRegistration{};

static void PgrpRestoreNormalMouse()
{
    if(!g_pgrpRawInFlight) return;
    RAWINPUTDEVICE original{};
    if(g_pgrpHadMouseRegistration) {
        original=g_pgrpPreviousMouseRegistration;
    } else {
        original.usUsagePage=0x01;
        original.usUsage=0x02;
        original.dwFlags=RIDEV_REMOVE;
        original.hwndTarget=nullptr; // required when RIDEV_REMOVE
    }
    if(!RegisterRawInputDevices(&original,1,sizeof(original)))
        OutputDebugStringA("[PGRP Mouse] warning: could not restore previous raw mouse registration\n");
    g_pgrpRawInFlight=false;
    opensamp::bridge::PgrpFreeCamResetRawMouse();
}

static void PgrpUpdateFlightMouse()
{
    const HWND foreground=GetForegroundWindow();
    const bool focused=g_hwnd && IsWindow(g_hwnd) &&
        (foreground==g_hwnd || foreground==GetAncestor(g_hwnd,GA_ROOT));
    const bool wants=focused && opensamp::bridge::PgrpFreeCamWantsRawMouse();
    if(!wants) {PgrpRestoreNormalMouse();return;}
    if(g_pgrpRawInFlight) return;

    // Snapshot all process registrations, keeping the exact previous mouse
    // usage/flags/target, not just whether a registration happened to exist.
    UINT count=0;
    if(GetRegisteredRawInputDevices(nullptr,&count,sizeof(RAWINPUTDEVICE)) == UINT(-1)
       || count>32) return;
    std::array<RAWINPUTDEVICE,32> registrations{};
    if(count &&
       GetRegisteredRawInputDevices(registrations.data(),&count,
                                   sizeof(RAWINPUTDEVICE))==UINT(-1)) return;
    g_pgrpHadMouseRegistration=false;
    for(UINT i=0;i<count;++i) {
        if(registrations[i].usUsagePage==0x01 &&
           registrations[i].usUsage==0x02) {
            g_pgrpPreviousMouseRegistration=registrations[i];
            g_pgrpHadMouseRegistration=true;
            break;
        }
    }
    RAWINPUTDEVICE fly{};
    fly.usUsagePage=0x01;
    fly.usUsage=0x02;
    fly.dwFlags=0; // foreground only; preserve legacy cursor/button messages
    fly.hwndTarget=g_hwnd;
    if(RegisterRawInputDevices(&fly,1,sizeof(fly))) {
        g_pgrpRawInFlight=true;
        opensamp::bridge::PgrpFreeCamResetRawMouse();
    } else {
        OutputDebugStringA("[PGRP Mouse] FreeCam Raw Input capture failed\n");
    }
}
'@ 'scope mouse ownership and exact GTA registration restoration'
Patch 'native/gui/imgui_manager.cpp' @'
static void im_gui_shutdown() // @todo
{
    if (!g_imgui_init) return;
'@ @'
static void im_gui_shutdown() // @todo
{
    PgrpRestoreNormalMouse();
    if (!g_imgui_init) return;
'@ 'restore normal mouse during shutdown'
Patch 'native/gui/imgui_manager.cpp' @'
LRESULT CALLBACK HookWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (g_imgui_init)
'@ @'
LRESULT CALLBACK HookWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if(msg==WM_KILLFOCUS || msg==WM_DESTROY || msg==WM_NCDESTROY)
        PgrpRestoreNormalMouse();
    if (g_imgui_init)
'@ 'immediate restore on game focus loss'
Patch 'native/gui/imgui_manager.cpp' @'
        if(msg==WM_INPUT && opensamp::bridge::PgrpFreeCamIsActive())
'@ @'
        if(g_pgrpRawInFlight && msg==WM_INPUT &&
           opensamp::bridge::PgrpFreeCamWantsRawMouse())
'@ 'only consume Raw Input while flight owns mouse'
Patch 'native/gui/imgui_manager.cpp' @'
void draw_ui()
{
    // GTA hides the system cursor in-game.
'@ @'
void draw_ui()
{
    // Rendering updates the game input mode even when there are no Win32
    // mouse events (e.g. keyboard-only /freecam or /exitfreecam).
    PgrpUpdateFlightMouse();
    // GTA hides the system cursor in-game.
'@ 'reacquire raw input only in FreeCam; restore in normal gameplay'
Write-Host 'PGRP v0.5.15: W forward, S backward; scoped Raw Input restored to GTA on exit.'

param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$name,[string]$needle,[string]$replacement,[string]$tag){
  $file=(Resolve-Path -LiteralPath (Join-Path $Root $name)).Path
  $text=[IO.File]::ReadAllText($file)
  $matches=([regex]::Matches($text,[regex]::Escape($needle))).Count
  if($matches -ne 1){throw "RealFreeCam $tag anchor count $matches"}
  [IO.File]::WriteAllText($file,$text.Replace($needle,$replacement),[Text.UTF8Encoding]::new($false))
  Write-Host "PATCH OK PGRP v0.5.6: $tag"
}
Patch 'native/sampraknet_bridge.cpp' @'
#include "game/game.h"
'@ @'
#include "game/game.h"
#include <cmath>
#include <cstdio>
#include <windows.h>

// GTA window is owned by the existing D3D9 GUI manager.
extern HWND g_hwnd;
'@ 'add native camera dependencies'
Patch 'native/sampraknet_bridge.cpp' @'
void ClientMessage(RPCParameters* rpcParams)
'@ @'
// -------- Native PGRP FreeCam v0.5.6 --------
// Runs in the game/render thread; all commands are standard ordered SA-MP
// RakNet ServerCommand RPCs, so no custom network/plugin dependency exists.
namespace pgrpfc {
    struct State {
        bool active=false,exitPending=false;
        float x=0,y=0,z=0,yaw=0,pitch=0;
        DWORD lastTick=0,lastReport=0,lastStream=0;
        float streamX=0,streamY=0;
        POINT center{};
    };
    static State st{};

    static bool IsFiniteWorld(float x,float y,float z) {
        return std::isfinite(x)&&std::isfinite(y)&&std::isfinite(z) &&
            std::fabs(x)<19500.f&&std::fabs(y)<19500.f&&z>-500.f&&z<9000.f;
    }
    static void Report() {
        if(!st.active || !iAreWeConnected || !g_pgrpEndpoint) return;
        char cmd[110]{};
        sprintf_s(cmd,sizeof(cmd),"/pgrpfcpos %.4f %.4f %.4f",st.x,st.y,st.z);
        ::sendServerCommand(cmd);
        st.lastReport=GetTickCount();
    }
    static void End() {
        if(!st.active) return;
        st.active=false;
        gta::sa::CameraRestore();
        Log("[PGRP FC v056] camera restored at %.3f %.3f %.3f",st.x,st.y,st.z);
    }
    static void Begin(float x,float y,float z) {
        if(!g_pgrpEndpoint || !iAreWeConnected || !IsFiniteWorld(x,y,z)) return;
        st=State{};
        st.x=x;st.y=y;st.z=z;
        st.yaw=0.0f;st.pitch=0.0f;
        st.lastTick=GetTickCount();
        st.streamX=x;st.streamY=y;
        st.lastStream=st.lastTick;
        st.active=true;
        Log("[PGRP FC v056] native camera activated at %.3f %.3f %.3f",x,y,z);
        Report();
    }
    static void Tick() {
        if(!st.active || !iAreWeConnected || !g_pgrpEndpoint) return;
        const DWORD now=GetTickCount();
        // Native camera SCM update <=30 FPS; don't dispatch 120+ opcodes/s
        // on PCs with low CPU or integrated graphics.
        if(now-st.lastTick < 32) return;
        float dt=float(now-st.lastTick)*0.001f;
        st.lastTick=now;
        if(dt<0.0f)dt=0.0f;
        if(dt>0.055f)dt=0.055f; // no camera warp during window stalls
        const bool focus=(g_hwnd != nullptr && GetForegroundWindow()==g_hwnd);
        const bool modal=g_chat.IsActive() || opensamp::gui::Dialog::Get().IsActive();
        if(focus&&!modal&&!st.exitPending) {
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
            const float mag=std::sqrt(vx*vx+vy*vy+vz*vz);
            if(mag>0.001f){
                const float speed=held(VK_SHIFT)?72.f:26.f;
                const float dist=dt*speed/mag;
                const float nx=st.x+vx*dist,ny=st.y+vy*dist,nz=st.z+vz*dist;
                if(IsFiniteWorld(nx,ny,nz)){st.x=nx;st.y=ny;st.z=nz;}
            }
        }
        // SCM opcodes 015F and 0160 update position and target of camera.
        // Both dispatches are from the game thread; no background memory hooks.
        gta::sa::scm::reset(0x015F);
        gta::sa::scm::push_float(st.x);
        gta::sa::scm::push_float(st.y);
        gta::sa::scm::push_float(st.z);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::exec();
        gta::sa::scm::reset(0x0160);
        gta::sa::scm::push_float(st.x+std::cos(st.pitch)*std::cos(st.yaw)*30.f);
        gta::sa::scm::push_float(st.y+std::cos(st.pitch)*std::sin(st.yaw)*30.f);
        gta::sa::scm::push_float(st.z+std::sin(st.pitch)*30.f);
        gta::sa::scm::push_int(2);
        gta::sa::scm::exec();
        if(!st.exitPending && now-st.lastReport >= 300) Report();
        // Stream surrounding map only after appreciable travel and rate-limit
        // the expensive native streaming refresh to help low-end PCs.
        if(now-st.lastStream>2300){
            const float dx=st.x-st.streamX,dy=st.y-st.streamY;
            if(dx*dx+dy*dy>110.f*110.f){
                // Refresh distant collision/terrain without creating an
                // object per node. Rate-limited because the SCM streamer
                // can hitch on PCs with slow storage.
                gta::sa::RefreshStreamingAt(st.x,st.y);
                st.streamX=st.x;st.streamY=st.y;
            }
            st.lastStream=now;
        }
    }
}
void ClientMessage(RPCParameters* rpcParams)
'@ 'add client-side free-camera renderer/physics'
Patch 'native/sampraknet_bridge.cpp' @'
    bsData.Read(szMsg, dwStrLen);
    szMsg[dwStrLen] = 0;
'@ @'
    bsData.Read(szMsg, dwStrLen);
    szMsg[dwStrLen] = 0;
    // This private control message comes from the authenticated SA-MP server,
    // not a chat line. Never show the packet to ordinary players.
    float fcX=0,fcY=0,fcZ=0;
    if(g_pgrpEndpoint &&
       std::sscanf(szMsg,"PGRP_FC_BEGIN %f %f %f",&fcX,&fcY,&fcZ)==3) {
        pgrpfc::Begin(fcX,fcY,fcZ);
        return;
    }
'@ 'authorize freecam from PGRP server packet'
Patch 'native/sampraknet_bridge.cpp' @'
        UpdateNetwork(pRakClient);

        // Issue RakNet connect once the Connect() caller has queued a request.
'@ @'
        UpdateNetwork(pRakClient);
        pgrpfc::Tick();

        // Issue RakNet connect once the Connect() caller has queued a request.
'@ 'run real freecam input/SCM on main game tick'
Patch 'native/sampraknet_bridge.cpp' @'
    void SendCommand(const char* utf8_command)
    {
        if (!utf8_command || !iAreWeConnected) return;
        // Server expects CP-1251 — same convention as chat (see sendChat).
'@ @'
    void SendCommand(const char* utf8_command)
    {
        if (!utf8_command || !iAreWeConnected) return;
        // Same ordered RakNet channel: final precise client camera position
        // arrives before /exitfreecam and is used as server spawn target.
        if(pgrpfc::st.active &&
            (_stricmp(utf8_command,"/exitfreecam")==0)){
            pgrpfc::Report();
            // Freeze camera at the exact requested exit point until the
            // server confirms spectator release. Avoid briefly exposing
            // the old player coordinates before server teleport arrives.
            pgrpfc::st.exitPending=true;
        }
        // Server expects CP-1251 — same convention as chat (see sendChat).
'@ 'deliver final camera coords before /exitfreecam'
Patch 'native/sampraknet_bridge.cpp' @'
    void Disconnect()
    {
        if (!s_initialized) return;
'@ @'
    void Disconnect()
    {
        pgrpfc::End();
        if (!s_initialized) return;
'@ 'restore camera on disconnect'
# When server clears spectator after successful /exitfreecam, restore the GTA
# view even if command was initiated by a different UI module.
Patch 'native/sampraknet_bridge.cpp' @'
    if (g_pgrpEndpoint)
    {
        // The server may release an already-spawned admin from FreeCam.
'@ @'
    if (g_pgrpEndpoint)
    {
        if(!bToggle && pgrpfc::st.active) pgrpfc::End();
        // The server may release an already-spawned admin from FreeCam.
'@ 'restore state on server-side spectator release'
Write-Host 'PGRP Native FreeCam v0.5.6 patched: client 6-axis movement; final server teleport.'

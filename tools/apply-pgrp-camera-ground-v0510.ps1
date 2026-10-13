param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$file,[string]$before,[string]$after,[string]$tag){
 $p=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
 $s=[IO.File]::ReadAllText($p)
 $n=([regex]::Matches($s,[regex]::Escape($before))).Count
 if($n -ne 1){throw ("Camera v0510 "+$tag+" anchor count "+$n)}
 [IO.File]::WriteAllText($p,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
 Write-Host ("PGRP PATCH OK "+$tag)
}
Patch 'native/sampraknet_bridge.cpp' @'
// -------- Native PGRP FreeCam v0.5.6 --------
'@ @'
static int try_stream_load_scene(float x,float y,float z);
// -------- Native PGRP FreeCam v0.5.6 --------
'@ 'forward declaration of exception-safe world stream loader'
# GTA SA CCamera::TakeControlNoEntity changes *mode*; it does not update the
# FIXED camera source. The missing US 1.0 method is 0x50BEC0.
Patch 'native/game/game.h' @'
    inline void CameraRestore()
'@ @'
    inline void CameraSetFixedModePosition(float x,float y,float z)
    {
        struct V3 {float x,y,z;};
        V3 pos{x,y,z},offset{0.f,0.f,0.f};
        using Fn=void(__thiscall*)(void*,V3*,V3*);
        reinterpret_cast<Fn>(0x50BEC0)(
            reinterpret_cast<void*>(offsets::VAR_TheCamera),&pos,&offset);
    }

    inline void CameraRestore()
'@ 'actual fixed camera position'
Patch 'native/game/game.h' @'
        // Opaque CPhysical + CPed header. We touch fields through typed helpers.
'@ @'
        // Opaque CPhysical + CPed header. We touch fields through typed helpers.
        Vec3& MoveSpeed(){return field<Vec3>(0x44);}
'@ 'physical ped velocity'
Patch 'native/sampraknet_bridge.cpp' @'
static bool g_pgrpServerWorldReady = false;
'@ @'
static bool g_pgrpServerWorldReady = false;
static float g_pgrpSpawnTarget[3]{};
static DWORD g_pgrpGroundLockUntil=0;
'@ 'spawn ground state'
Patch 'native/sampraknet_bridge.cpp' @'
        g_pgrpServerWorldReady = false;

        s_serverPassword[0] = 0;
'@ @'
        g_pgrpServerWorldReady = false;
        g_pgrpGroundLockUntil=0;

        s_serverPassword[0] = 0;
'@ 'reset ground state'
Patch 'native/sampraknet_bridge.cpp' @'
    RakNet::BitStream bsSendRequestSpawn;
'@ @'
    // Server-authenticated spawn info has been received. Stream collision and
    // surrounding IPLs BEFORE moving the physical GTA bootstrap character.
    if(g_pgrpEndpoint && std::isfinite(fNormalModePos[0]) &&
       std::isfinite(fNormalModePos[1]) && std::isfinite(fNormalModePos[2]) &&
       std::fabs(fNormalModePos[0])<19500.f && std::fabs(fNormalModePos[1])<19500.f)
    {
        g_pgrpSpawnTarget[0]=fNormalModePos[0];
        g_pgrpSpawnTarget[1]=fNormalModePos[1];
        g_pgrpSpawnTarget[2]=fNormalModePos[2];
        if(!try_stream_load_scene(fNormalModePos[0],fNormalModePos[1],fNormalModePos[2]))
            Log("[PGRP v0510] initial terrain preload exception");
        gta::sa::RefreshStreamingAt(fNormalModePos[0],fNormalModePos[1]);
        g_pgrpGroundLockUntil=GetTickCount()+8000;
    }
    RakNet::BitStream bsSendRequestSpawn;
'@ 'stream before initial spawn teleport'
Patch 'native/sampraknet_bridge.cpp' @'
        ped->SetHeading(fNormalModeRot);
        ped->Health() = 100.0f;
'@ @'
        ped->SetHeading(fNormalModeRot);
        if(g_pgrpEndpoint) ped->MoveSpeed()={0.f,0.f,0.f};
        ped->Health() = 100.0f;
'@ 'clear falling velocity during spawn'
Patch 'native/sampraknet_bridge.cpp' @'
        bool active=false,exitPending=false;
'@ @'
        bool active=false,exitPending=false,originalPedVisible=true;
'@ 'preserve ped visibility'
Patch 'native/sampraknet_bridge.cpp' @'
        st.active=true;
        // Preload actual terrain and buildings at the starting camera cell;
'@ @'
        st.active=true;
        if(auto* ped=gta::sa::GetLocalPlayerPed())
        {
            st.originalPedVisible=ped->bIsVisible;
            ped->bIsVisible=false;
            ped->MoveSpeed()={0.f,0.f,0.f};
        }
        // Preload actual terrain and buildings at the starting camera cell;
'@ 'hide body during free camera'
Patch 'native/sampraknet_bridge.cpp' @'
        st.active=false;
        gta::sa::CameraRestore();
'@ @'
        st.active=false;
        if(auto* ped=gta::sa::GetLocalPlayerPed())
        {
            ped->bIsVisible=st.originalPedVisible;
            ped->MoveSpeed()={0.f,0.f,0.f};
        }
        gta::sa::CameraRestore();
'@ 'restore ped visibility after camera exit'
Patch 'native/sampraknet_bridge.cpp' @'
        gta::sa::CameraSetPosition(x,y,z);
        Log("[PGRP FC v058] native camera + terrain activated at %.3f %.3f %.3f",x,y,z);
'@ @'
        // Switch to fixed camera mode ONCE, then update its source each tick.
        gta::sa::CameraSetPosition(x,y,z);
        gta::sa::CameraSetFixedModePosition(x,y,z);
        if(!try_stream_load_scene(x,y,z))
            Log("[PGRP FC v0510] first camera scene preload exception");
        Log("[PGRP FC v0510] control acquired %.3f %.3f %.3f",x,y,z);
'@ 'enter GTA fixed camera without resetting it each frame'
Patch 'native/sampraknet_bridge.cpp' @'
        // For PGRP spectating, the engine owns the active camera. Reassert
        // native control over the new world position every 33ms *before*
        // targeting it: the old opcode-only path moved the radar position
        // while the camera stayed stuck over unloaded/white terrain.
        gta::sa::CameraSetPosition(st.x,st.y,st.z);
        gta::sa::scm::reset(0x0160);
'@ @'
        // Unlike TakeControlNoEntity, SetCamPositionForFixedMode changes
        // render-space camera coordinates instead of merely resetting mode.
        gta::sa::CameraSetFixedModePosition(st.x,st.y,st.z);
        gta::sa::scm::reset(0x015F);
        gta::sa::scm::push_float(st.x);
        gta::sa::scm::push_float(st.y);
        gta::sa::scm::push_float(st.z);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::exec();
        gta::sa::scm::reset(0x0160);
'@ 'real camera source + lookAt update every 33ms'
Patch 'native/sampraknet_bridge.cpp' @'
        if(!st.exitPending && now-st.lastReport >= 300) Report();
'@ @'
        // The GTA model streamer normally follows the ped, not the free
        // camera. Keep the invisible local ped at camera world coordinates,
        // while outgoing on-foot sync remains disabled by spectator state.
        if(auto* ped=gta::sa::GetLocalPlayerPed())
        {
            ped->bIsVisible=false;
            ped->SetPosition(st.x,st.y,st.z-2.f);
            ped->MoveSpeed()={0.f,0.f,0.f};
        }
        if(!st.exitPending && now-st.lastReport >= 300) Report();
'@ 'make city/collision streaming follow free camera'
Patch 'native/sampraknet_bridge.cpp' @'
                gta::sa::RefreshStreamingAt(st.x,st.y);
                st.streamX=st.x;st.streamY=st.y;
'@ @'
                if(!try_stream_load_scene(st.x,st.y,st.z))
                    gta::sa::RefreshStreamingAt(st.x,st.y);
                st.streamX=st.x;st.streamY=st.y;
'@ 'load terrain buildings around new camera cell'
Patch 'native/sampraknet_bridge.cpp' @'
            gta::sa::RefreshStreamingAt(fcX,fcY);
            g_pgrpServerWorldReady=true;
'@ @'
            if(!try_stream_load_scene(fcX,fcY,fcZ))
                gta::sa::RefreshStreamingAt(fcX,fcY);
            if(auto* ped=gta::sa::GetLocalPlayerPed())
            {
                ped->SetPosition(fcX,fcY,fcZ);
                ped->MoveSpeed()={0.f,0.f,0.f};
            }
            g_pgrpGroundLockUntil=0;
            g_pgrpServerWorldReady=true;
'@ 'ack ready only after collision and position reconcile'
Patch 'native/sampraknet_bridge.cpp' @'
        pgrpfc::Tick();

        // Issue RakNet connect once the Connect() caller has queued a request.
'@ @'
        pgrpfc::Tick();
        // Hold a fresh logged-in ped on the authoritative spawn point until
        // world-ready arrives. The bounded lock prevents physical skyfall
        // while terrain/colmodels are asynchronously materializing.
        if(g_pgrpEndpoint && iSpawned && !bIsSpectating &&
           !g_pgrpServerWorldReady && g_pgrpGroundLockUntil)
        {
            if(GetTickCount()<g_pgrpGroundLockUntil)
            {
                if(auto* ped=gta::sa::GetLocalPlayerPed())
                {
                    ped->SetPosition(g_pgrpSpawnTarget[0],
                                     g_pgrpSpawnTarget[1],
                                     g_pgrpSpawnTarget[2]);
                    ped->MoveSpeed()={0.f,0.f,0.f};
                }
            }
            else g_pgrpGroundLockUntil=0;
        }

        // Issue RakNet connect once the Connect() caller has queued a request.
'@ 'prevent gravity until authenticated ground collision ready'
Write-Host 'PGRP 0.5.10 fixed camera and collision-safe spawn source patched.'

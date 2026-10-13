param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$file,[string]$old,[string]$new,[string]$label){
 $p=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
 $s=[IO.File]::ReadAllText($p)
 $matches=([regex]::Matches($s,[regex]::Escape($old))).Count
 if($matches -ne 1){throw ("v058 native fix "+$label+" expected 1 got "+$matches)}
 [IO.File]::WriteAllText($p,$s.Replace($old,$new),[Text.UTF8Encoding]::new($false))
 Write-Host ("PGRP v058 PATCH OK "+$label)
}
Patch 'native/sampraknet_bridge.cpp' @'
static DWORD g_pgrpSpawnVisualHoldMs = 0;
'@ @'
static DWORD g_pgrpSpawnVisualHoldMs = 0;
static bool g_pgrpServerWorldReady = false;
'@ 'world-ready flag'
Patch 'native/sampraknet_bridge.cpp' @'
        g_pgrpSpawnVisualHoldMs = 0;

        s_serverPassword[0] = 0;
'@ @'
        g_pgrpSpawnVisualHoldMs = 0;
        g_pgrpServerWorldReady = false;

        s_serverPassword[0] = 0;
'@ 'reset ready on reconnect'
Patch 'native/sampraknet_bridge.cpp' @'
        if (!iSpawned || g_pgrpSpawnVisualHoldMs == 0) return false;
        return (GetTickCount() - g_pgrpSpawnVisualHoldMs) >= 1800;
'@ @'
        if (!iSpawned || g_pgrpSpawnVisualHoldMs == 0) return false;
        const DWORD elapsed=GetTickCount()-g_pgrpSpawnVisualHoldMs;
        // Do not reveal the sky-fall temporary spawn before server confirms
        // it has reconciled the physical ped and refreshed the camera.
        // 8s fallback keeps older servers from leaving the player stuck.
        return elapsed > 800 && (g_pgrpServerWorldReady || elapsed > 8000);
'@ 'keep login mask until authoritative stream completes'
Patch 'native/sampraknet_bridge.cpp' @'
        g_pgrpSpawnVisualHoldMs = GetTickCount();
        s_spawnStage = SpawnStage::Done;
'@ @'
        g_pgrpSpawnVisualHoldMs = GetTickCount();
        g_pgrpServerWorldReady = false;
        s_spawnStage = SpawnStage::Done;
'@ 'spawn transition'
Patch 'native/sampraknet_bridge.cpp' @'
        st.active=true;
        Log("[PGRP FC v056] native camera activated at %.3f %.3f %.3f",x,y,z);
'@ @'
        st.active=true;
        // Preload actual terrain and buildings at the starting camera cell;
        // previously the first stream refresh waited for >110m movement.
        gta::sa::RefreshStreamingAt(x,y);
        gta::sa::CameraSetPosition(x,y,z);
        Log("[PGRP FC v058] native camera + terrain activated at %.3f %.3f %.3f",x,y,z);
'@ 'preload initial camera cell'
Patch 'native/sampraknet_bridge.cpp' @'
        gta::sa::scm::reset(0x015F);
        gta::sa::scm::push_float(st.x);
        gta::sa::scm::push_float(st.y);
        gta::sa::scm::push_float(st.z);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::push_float(0.f);
        gta::sa::scm::exec();
'@ @'
        // For PGRP spectating, the engine owns the active camera. Reassert
        // native control over the new world position every 33ms *before*
        // targeting it: the old opcode-only path moved the radar position
        // while the camera stayed stuck over unloaded/white terrain.
        gta::sa::CameraSetPosition(st.x,st.y,st.z);
'@ 'use native camera control rather than stale SCM camera position'
Patch 'native/sampraknet_bridge.cpp' @'
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
'@ @'
        // Nearby road/building cells must follow camera coordinates, not the
        // hidden old ped position. Limit synchronous streaming to 1/s and
        // >=18 metres traveled to avoid hitching on low-end PCs.
        if(now-st.lastStream>1000){
            const float dx=st.x-st.streamX,dy=st.y-st.streamY;
            if(dx*dx+dy*dy>18.f*18.f){
                gta::sa::RefreshStreamingAt(st.x,st.y);
                st.streamX=st.x;st.streamY=st.y;
                Log("[PGRP FC v058] stream at %.1f %.1f %.1f",st.x,st.y,st.z);
            }
            st.lastStream=now;
        }
'@ 'refresh map around camera instead of origin'
Patch 'native/sampraknet_bridge.cpp' @'
    if(g_pgrpEndpoint &&
       std::sscanf(szMsg,"PGRP_FC_BEGIN %f %f %f",&fcX,&fcY,&fcZ)==3) {
'@ @'
    if(g_pgrpEndpoint && iSpawned &&
       std::sscanf(szMsg,"PGRP_WORLD_READY %f %f %f",&fcX,&fcY,&fcZ)==3) {
        if(pgrpfc::IsFiniteWorld(fcX,fcY,fcZ)){
            gta::sa::RefreshStreamingAt(fcX,fcY);
            g_pgrpServerWorldReady=true;
            Log("[PGRP v058] world ready at %.1f %.1f %.1f",fcX,fcY,fcZ);
        }
        return;
    }
    if(g_pgrpEndpoint &&
       std::sscanf(szMsg,"PGRP_FC_BEGIN %f %f %f",&fcX,&fcY,&fcZ)==3) {
'@ 'server world settled handshake'
Write-Host 'PGRP v058 native camera and post-login rendering fixes applied.'

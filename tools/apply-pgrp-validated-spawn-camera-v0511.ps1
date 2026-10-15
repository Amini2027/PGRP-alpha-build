param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$file,[string]$before,[string]$after,[string]$name) {
  $p=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
  $data=[IO.File]::ReadAllText($p)
  $n=([regex]::Matches($data,[regex]::Escape($before))).Count
  if($n -ne 1){throw ("PGRP v0511 "+$name+": expected exactly 1 occurrence, found "+$n)}
  [IO.File]::WriteAllText($p,$data.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host ("PGRP v0511 PATCH OK "+$name)
}
Patch 'native/sampraknet_bridge.cpp' @'
static int try_stream_load_scene(float x, float y, float z)
{
    __try
    {
        gta::sa::StreamingLoadScene(x, y, z);
        return 1;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return 0;
    }
}
'@ @'
static int try_stream_load_scene(float x, float y, float z)
{
    // Direct CStreaming::LoadScene AVs reliably in this bootstrap client.
    // Use the GTA SCM 04E4 refresh; calling it on a valid location avoids
    // aborting camera setup and spawn teleport on a swallowed exception.
    if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(z)) return 0;
    if(std::fabs(x)>19500.f||std::fabs(y)>19500.f||std::fabs(z)>9000.f) return 0;
    __try
    {
        gta::sa::RefreshStreamingAt(x,y);
        return 1;
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {return 0;}
}
'@ 'remove faulty scene loader'
Patch 'native/sampraknet_bridge.cpp' @'
        g_pgrpSpawnInfoReady = true;
        Log("[PGRP Spawn] Server info pos=(%.3f,%.3f,%.3f) angle=%.1f",
'@ @'
        if(std::fabs(SpawnInfo.vecPos[0])<20.f &&
           std::fabs(SpawnInfo.vecPos[1])<20.f &&
           SpawnInfo.vecPos[2]>-100.f && SpawnInfo.vecPos[2]<100.f)
        {
            g_pgrpSpawnInfoReady=false;
            Log("[PGRP v0511] REFUSED invalid bootstrap SpawnInfo (%.3f,%.3f,%.3f); upgrade server",
                SpawnInfo.vecPos[0],SpawnInfo.vecPos[1],SpawnInfo.vecPos[2]);
            return;
        }
        g_pgrpSpawnInfoReady = true;
        Log("[PGRP Spawn] Server info pos=(%.3f,%.3f,%.3f) angle=%.1f",
'@ 'reject invalid server origin before spawn'
Patch 'native/sampraknet_bridge.cpp' @'
    Log("[Camera] lookAt (%.1f, %.1f, %.1f) — @todo PointCamera invocation",
        x, y, z);
    // @todo CCamera::PointCamera (0x50AD60). The thiscall signature isn't
    //       fully reversed in mod_s0beit_sa; need a separate exploration pass.
'@ @'
    gta::sa::scm::reset(0x0160);
    gta::sa::scm::push_float(x);
    gta::sa::scm::push_float(y);
    gta::sa::scm::push_float(z);
    gta::sa::scm::push_int(2);
    gta::sa::scm::exec();
    Log("[Camera] lookAt implemented at %.1f %.1f %.1f",x,y,z);
'@ 'implement auth camera look-at'
Patch 'native/sampraknet_bridge.cpp' @'
        DWORD lastTick=0,lastReport=0,lastStream=0;
'@ @'
        DWORD lastTick=0,lastReport=0,lastStream=0,lastDiagnostic=0;
'@ 'add camera diagnostic timing'
Patch 'native/sampraknet_bridge.cpp' @'
        if(!st.exitPending && now-st.lastReport >= 300) Report();
'@ @'
        if(now-st.lastDiagnostic>=1000)
        {
            st.lastDiagnostic=now;
            Log("[PGRP FC v0511] camera=(%.2f %.2f %.2f) yaw=%.2f pitch=%.2f focus=%u spectator=%u",
                st.x,st.y,st.z,st.yaw,st.pitch,unsigned(focus),unsigned(bIsSpectating));
        }
        if(!st.exitPending && now-st.lastReport >= 300) Report();
'@ 'log real camera movement each second'
Write-Host 'PGRP v0511 FreeCam and spawn safety patch complete.'

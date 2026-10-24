param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$old,[string]$new,[string]$label){
  $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $src=[IO.File]::ReadAllText($file)
  $n=([regex]::Matches($src,[regex]::Escape($old))).Count
  if($n -ne 1){throw "PGRP v0.5.28 $label expected one anchor; got $n"}
  [IO.File]::WriteAllText($file,$src.Replace($old,$new),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v0.5.28 PATCH OK $label"
}
# Confirmed from user: v0.5.27 FreeCam moves horizontally opposite the
# desired mouse direction. Change only horizontal input polarity while
# preserving v0.5.25 anti-inversion and mouse-delta clamping.
Patch 'native/sampraknet_bridge.cpp' @'
            s.yaw=std::remainder(s.yaw-mx*mouseScale,6.283185307f);
'@ @'
            // PGRP user-calibrated horizontal Raw Input direction.
            // Only invert horizontal; retain vertical/pitch and raw limiting.
            s.yaw=std::remainder(s.yaw+mx*mouseScale,6.283185307f);
'@ 'correct reversed left/right mouse direction'
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamAfterRenderList();
'@ @'
    void PgrpFreeCamAfterRenderList();
    void PgrpFreeCamRoadPass();
'@ 'declare road render-pass diagnostic'
Patch 'native/hooks.cpp' @'
static bool Install_CGameProcess_Hook()
'@ @'
// Verify GTA's dedicated CRenderer::RenderRoads pipeline actually executes.
// The renderer normally walks its visible-entity list separately for roads.
using RenderRoads_t=void(__cdecl*)();
static RenderRoads_t oPgrpRenderRoads=nullptr;
static void __cdecl hkPgrpRenderRoads(){
    if(oPgrpRenderRoads)oPgrpRenderRoads();
    opensamp::bridge::PgrpFreeCamRoadPass();
}
static bool Install_PgrpRenderRoads_Hook(){
    if(MH_CreateHook(reinterpret_cast<void*>(0x553A10),
        &hkPgrpRenderRoads,reinterpret_cast<void**>(&oPgrpRenderRoads))!=MH_OK)
        return false;
    return MH_EnableHook(reinterpret_cast<void*>(0x553A10))==MH_OK;
}

static bool Install_CGameProcess_Hook()
'@ 'instrument actual GTA RenderRoads pass'
Patch 'native/hooks.cpp' @'
    if(!Install_PgrpRenderList_Hook())
'@ @'
    if(!Install_PgrpRenderRoads_Hook())
        LogLine("[PGRP] WARNING road-render diagnostic hook unavailable\n");
    else
        LogLine("[PGRP] road-render pass diagnostic hook installed\n");

    if(!Install_PgrpRenderList_Hook())
'@ 'install road pass observer without changing original rendering'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamAfterRenderList(){
'@ @'
    static unsigned gPgrpRoadPasses=0;
    void PgrpFreeCamRoadPass(){
        if(PgrpFreeCamIsActive())++gPgrpRoadPasses;
    }
    void PgrpFreeCamAfterRenderList(){
'@ 'keep count of road-render passes separately from visible entity count'
Patch 'native/sampraknet_bridge.cpp' @'
            Log("[PGRP FC v0527 SCENE] visible=%u lods=%u pending=%u streamingDisabled=%u memUsed=%u memLimit=%u renderPosError=%.3f farClip=%.1f camera=(%.2f,%.2f,%.2f)",
                visibles,lods,pending,unsigned(disabled),memory,budget,
                renderDistance,farClip,s.renderX,s.renderY,s.renderZ);
'@ @'
            // Outside/tunnel flags determine which map buildings GTA culls.
            // The dedicated road-pass counter diagnoses a skipped RenderRoads
            // stage even when streaming requests have all drained.
            const unsigned outside=*reinterpret_cast<const unsigned char*>(0xB745C1);
            const unsigned tunnel=*reinterpret_cast<const unsigned char*>(0xB745C0);
            Log("[PGRP FC v0528 SCENE] visible=%u lods=%u pending=%u streamOff=%u mem=%u/%u roadPasses=%u outside=%u tunnel=%u renderErr=%.3f far=%.1f cam=(%.2f,%.2f,%.2f)",
                visibles,lods,pending,unsigned(disabled),memory,budget,
                gPgrpRoadPasses,outside,tunnel,renderDistance,farClip,
                s.renderX,s.renderY,s.renderZ);
            if(gPgrpRoadPasses==0)
                Log("[PGRP FC v0528 SCENE] ALERT RenderRoads was never called");
            if(!outside)
                Log("[PGRP FC v0528 SCENE] NOTE GTA disabled outside-world geometry for current zone");
'@ 'diagnose road pass and outside-world culling, not just streaming'
# The log from v0527 repeatedly showed farClip=150 while only 27-41
# visible entities and virtually no LODs were selected. With this small
# cap the engine rejects road and nearby building models early in culling.
# Increase the *active GTA RwCamera far clipping plane*, which is also used
# by CRenderer::ScanWorld, and return to its original value on leaving
# FreeCam. Do not modify global LOD settings or the user's GTA files.
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamBeforeRenderList(){
        if(!PgrpFreeCamIsActive())return;
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.renderX,s.renderY,s.renderZ))return;
        auto* camera=reinterpret_cast<void*>(0xB6F028);
'@ @'
    void PgrpFreeCamBeforeRenderList(){
        // GTA SA RW camera farPlane is at +0x84, verified against the
        // standard 32-bit RenderWare RwCamera memory layout.
        // Official GTA SA 1.0 US API RwCameraSetFarClipPlane = 0x7EE2A0.
        // Keep FreeCam increases bounded for low-end hardware.
        static bool hasOriginalFar=false;
        static float originalFar=150.f;
        static void* originalCameraRW=nullptr;
        auto* camera=reinterpret_cast<void*>(0xB6F028);
        if(!PgrpFreeCamIsActive()){
            if(hasOriginalFar && originalCameraRW){
                __try {
                    using SetFar=void*(__cdecl*)(void*,float);
                    reinterpret_cast<SetFar>(0x7EE2A0)(
                        originalCameraRW,originalFar);
                    Log("[PGRP FC v0528 FAR] restored GTA original %.1f",originalFar);
                } __except(EXCEPTION_EXECUTE_HANDLER){
                    Log("[PGRP FC v0528 FAR] original restore exception");
                }
            }
            hasOriginalFar=false;
            originalCameraRW=nullptr;
            return;
        }
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.renderX,s.renderY,s.renderZ))return;
        __try {
            auto* rw=*reinterpret_cast<void**>(
                reinterpret_cast<std::uint8_t*>(camera)+0x954);
            if(rw){
                const float prior=*reinterpret_cast<const float*>(
                    reinterpret_cast<const std::uint8_t*>(rw)+0x84);
                // Normal GTA camera sometimes clamps this to 150 each frame.
                // Restore the captured baseline when FreeCam ends.
                if(std::isfinite(prior) && prior>25.f && prior<320.f){
                    if(!hasOriginalFar || originalCameraRW!=rw){
                        originalFar=prior;
                        originalCameraRW=rw;
                        hasOriginalFar=true;
                        Log("[PGRP FC v0528 FAR] baseline=%.1f target=320.0",prior);
                    }
                    using SetFar=void*(__cdecl*)(void*,float);
                    reinterpret_cast<SetFar>(0x7EE2A0)(rw,320.f);
                }
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            static DWORD lastError=0;
            const DWORD now=GetTickCount();
            if(now-lastError>3000){
                lastError=now;
                Log("[PGRP FC v0528 FAR] bounded far clip update unavailable");
            }
        }
'@ 'expand too-short GTA FreeCam far clip without affecting normal gameplay'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0527] BUILD=street-streaming-diag-20261021 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0528] BUILD=road-pass-clip-mouse-20261021 DLL=%s",dllPath);
'@ 'new build identity with DLL absolute path'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0527] BUILD=street-streaming-diag-20261021 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0528] BUILD=road-pass-clip-mouse-20261021 DLL_PATH_UNAVAILABLE");
'@ 'new DLL identity fallback'
Write-Host 'PGRP v0.5.28: user-calibrated horizontal mouse, 320 GTA FreeCam far clip, diagnostic road pass and world/tunnel flags.'

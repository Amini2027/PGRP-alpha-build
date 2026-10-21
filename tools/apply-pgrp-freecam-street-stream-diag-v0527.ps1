param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
  $full=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $s=[IO.File]::ReadAllText($full)
  $count=([regex]::Matches($s,[regex]::Escape($before))).Count
  if($count -ne 1){throw "PGRP v0.5.27 $label expected 1 occurrence, found $count"}
  [IO.File]::WriteAllText($full,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v0.5.27 PATCH OK: $label"
}
# GTA SA renderer scans and requests models in two separate passes.
# Older PGRP patched try_stream_load_scene to run SCM refresh only,
# because the synchronous CStreaming::LoadScene AV'd in this client.
# RefreshStreamingAt is NOT a guarantee models for roads/buildings were
# requested or loaded. Re-request terrain and roads using the GTA renderer
# frustum request API, with bounded cadence and diagnostic counters.
# All GTA function offsets are for the supported GTA SA 1.0 US build:
# CRenderer::RequestObjectsInFrustum 0x555960
# RwFrameGetLTM 0x7F0990
# CStreaming::ms_numModelsRequested 0x8E4CB8
# CStreaming::ms_memoryUsed 0x8E4CB4
# CStreaming::ms_memoryAvailable 0x8A5A80
# CStreaming::ms_disableStreaming 0x9654B0
# CRenderer::ms_nNoOfVisibleEntities 0xB76844
# CRenderer::ms_nNoOfVisibleLods 0xB76840
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamBeforeRenderList();
'@ @'
    void PgrpFreeCamBeforeRenderList();
    void PgrpFreeCamAfterRenderList();
'@ 'declare safe renderer streaming diagnostics'
Patch 'native/hooks.cpp' @'
static void __cdecl hkPgrpConstructRenderList(){
    opensamp::bridge::PgrpFreeCamBeforeRenderList();
    if(oPgrpConstructRenderList)oPgrpConstructRenderList();
}
'@ @'
static void __cdecl hkPgrpConstructRenderList(){
    opensamp::bridge::PgrpFreeCamBeforeRenderList();
    if(oPgrpConstructRenderList)oPgrpConstructRenderList();
    opensamp::bridge::PgrpFreeCamAfterRenderList();
}
'@ 'count actually visible entities after GTA constructs the render list'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamBeforeRenderList(){
'@ @'
    // No waiting and no force-loading of every model on the render thread.
    // This is a bounded diagnostic and request pass only. GTA streaming
    // loads the requested objects via its existing normal update path.
    void PgrpFreeCamAfterRenderList(){
        if(!PgrpFreeCamIsActive())return;
        static DWORD last=0;
        const DWORD now=GetTickCount();
        if(now-last<2200)return;
        last=now;
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.renderX,s.renderY,s.renderZ))return;
        __try {
            const unsigned visibles=*reinterpret_cast<const unsigned*>(0xB76844);
            const unsigned lods=*reinterpret_cast<const unsigned*>(0xB76840);
            const unsigned pending=*reinterpret_cast<const unsigned*>(0x8E4CB8);
            const unsigned memory=*reinterpret_cast<const unsigned*>(0x8E4CB4);
            const unsigned budget=*reinterpret_cast<const unsigned*>(0x8A5A80);
            const unsigned char disabled=*reinterpret_cast<const unsigned char*>(0x9654B0);
            const auto* renderPos=reinterpret_cast<const float*>(0xB76870);
            const float rdx=renderPos[0]-s.renderX;
            const float rdy=renderPos[1]-s.renderY;
            const float rdz=renderPos[2]-s.renderZ;
            const float renderDistance=std::sqrt(rdx*rdx+rdy*rdy+rdz*rdz);
            const float farClip=*reinterpret_cast<const float*>(0xB76848);
            Log("[PGRP FC v0527 SCENE] visible=%u lods=%u pending=%u streamingDisabled=%u memUsed=%u memLimit=%u renderPosError=%.3f farClip=%.1f camera=(%.2f,%.2f,%.2f)",
                visibles,lods,pending,unsigned(disabled),memory,budget,
                renderDistance,farClip,s.renderX,s.renderY,s.renderZ);
            if(disabled && pending)
                Log("[PGRP FC v0527 SCENE] ALERT streaming disabled with pending model requests");
            if(renderDistance>15.f)
                Log("[PGRP FC v0527 SCENE] ALERT render origin mismatches free-camera location");
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            Log("[PGRP FC v0527 SCENE] diagnostic memory read unavailable");
        }
    }
    void PgrpFreeCamBeforeRenderList(){
'@ 'log rendering/culling counts and streaming queue after scene scan'
Patch 'native/sampraknet_bridge.cpp' @'
            reinterpret_cast<Derived>(0x5150E0)(camera,false,false);
            static unsigned renderLists=0;
'@ @'
            reinterpret_cast<Derived>(0x5150E0)(camera,false,false);
            // The original v0511 scene loader is deliberately disabled due
            // to bootstrap AVs. Request road/building models in the actual
            // RwCamera frustum instead of repeatedly issuing 04E4 refresh.
            // Limit to one request per 1250ms; no synchronous load or
            // CStreaming::LoadAllRequestedModels in this render callback.
            static DWORD lastFrustumRequest=0;
            const DWORD reqNow=GetTickCount();
            if(reqNow-lastFrustumRequest>=1250) {
                lastFrustumRequest=reqNow;
                __try {
                    auto* rw=*reinterpret_cast<void**>(
                        reinterpret_cast<std::uint8_t*>(camera)+0x954);
                    if(rw) {
                        auto* frame=*reinterpret_cast<void**>(
                            reinterpret_cast<std::uint8_t*>(rw)+0x04);
                        if(frame) {
                            using LTM=const void*(__cdecl*)(void*);
                            const auto* view=reinterpret_cast<LTM>(0x7F0990)(frame);
                            if(view) {
                                const unsigned pendingBefore=
                                    *reinterpret_cast<const unsigned*>(0x8E4CB8);
                                using RequestFrustum=void(__cdecl*)(const void*,int);
                                reinterpret_cast<RequestFrustum>(0x555960)(view,0);
                                const unsigned pendingAfter=
                                    *reinterpret_cast<const unsigned*>(0x8E4CB8);
                                static unsigned requestCount=0;
                                if((++requestCount % 2)==1 ||
                                   pendingAfter!=pendingBefore)
                                    Log("[PGRP FC v0527 REQUEST] scan=%u pendingBefore=%u pendingAfter=%u cam=(%.2f,%.2f,%.2f) yaw=%.3f pitch=%.3f",
                                        requestCount,pendingBefore,pendingAfter,
                                        s.renderX,s.renderY,s.renderZ,
                                        s.renderYaw,s.renderPitch);
                            }
                        }
                    }
                } __except(EXCEPTION_EXECUTE_HANDLER) {
                    static DWORD lastRequestError=0;
                    if(reqNow-lastRequestError>3500){
                        lastRequestError=reqNow;
                        Log("[PGRP FC v0527 REQUEST] WARNING frustum-model request unavailable");
                    }
                }
            }
            static unsigned renderLists=0;
'@ 'periodically request roads/buildings using actual stable render-camera frustum'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0526] BUILD=visibility-frustum-sync-20261021 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0527] BUILD=street-streaming-diag-20261021 DLL=%s",dllPath);
'@ 'trace absolute DLL path in street streaming build'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0526] BUILD=visibility-frustum-sync-20261021 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0527] BUILD=street-streaming-diag-20261021 DLL_PATH_UNAVAILABLE");
'@ 'trace fallback DLL build'
Write-Host 'PGRP v0.5.27: bounded model requests in valid frustum, scene/streaming diagnostic counters.'

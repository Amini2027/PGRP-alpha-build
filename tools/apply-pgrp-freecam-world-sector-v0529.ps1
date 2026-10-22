param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
  $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $source=[IO.File]::ReadAllText($file)
  $n=([regex]::Matches($source,[regex]::Escape($before))).Count
  if($n -ne 1){throw "PGRP v0.5.29 $label expected one anchor, got $n"}
  [IO.File]::WriteAllText($file,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v0.5.29 PATCH OK $label"
}
# GTA SA 1.0 US: RenderList (0x5556E0) recalculates outside/tunnel flags
# then calls CRenderer::ScanWorld (0x554FE0). Override flags only DURING
# that exact scan and restore immediately after, FreeCam outside world only.
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamRoadPass();
'@ @'
    void PgrpFreeCamRoadPass();
    bool PgrpFreeCamBeginWorldScan();
    void PgrpFreeCamEndWorldScan(bool activated);
'@ 'declare world scan only overrides'
Patch 'native/hooks.cpp' @'
static bool Install_CGameProcess_Hook()
'@ @'
using RendererScanWorld_t=void(__cdecl*)();
static RendererScanWorld_t oPgrpRendererScanWorld=nullptr;
static void __cdecl hkPgrpRendererScanWorld(){
    const bool changed=opensamp::bridge::PgrpFreeCamBeginWorldScan();
    if(oPgrpRendererScanWorld)oPgrpRendererScanWorld();
    opensamp::bridge::PgrpFreeCamEndWorldScan(changed);
}
static bool Install_PgrpWorldScan_Hook(){
    const auto addr=reinterpret_cast<void*>(0x554FE0);
    if(MH_CreateHook(addr,&hkPgrpRendererScanWorld,
            reinterpret_cast<void**>(&oPgrpRendererScanWorld))!=MH_OK)return false;
    return MH_EnableHook(addr)==MH_OK;
}

static bool Install_CGameProcess_Hook()
'@ 'hook map object sector scanning'
Patch 'native/hooks.cpp' @'
    if(!Install_PgrpRenderRoads_Hook())
'@ @'
    if(!Install_PgrpWorldScan_Hook())
        LogLine("[PGRP] WARNING FreeCam world sector scan hook unavailable\n");
    else
        LogLine("[PGRP] FreeCam world sector scan hook installed\n");

    if(!Install_PgrpRenderRoads_Hook())
'@ 'install map sector hook'
Patch 'native/sampraknet_bridge.cpp' @'
    static unsigned gPgrpRoadPasses=0;
'@ @'
    static unsigned char gPgrpSavedTunnels=0,gPgrpSavedExterior=0;
    static unsigned gPgrpWorldScanCount=0;
    static unsigned gPgrpRoadPasses=0;
'@ 'declare sector state before scene diagnostics'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamBeforeRenderList(){
'@ @'
    // CRenderer::ScanWorld uses these flags to omit candidate entities.
    // The GTA code sets them based on tunnel CullZones even for FreeCam.
    // Permit both kinds of map geometry while flying in normal area 0.
    bool PgrpFreeCamBeginWorldScan(){
        if(!PgrpFreeCamIsActive())return false;
        __try {
            const int area=*reinterpret_cast<const int*>(
                gta::sa::offsets::VAR_CurrentArea);
            if(area!=0)return false;
            gPgrpSavedTunnels=*reinterpret_cast<unsigned char*>(0xB745C0);
            gPgrpSavedExterior=*reinterpret_cast<unsigned char*>(0xB745C1);
            *reinterpret_cast<unsigned char*>(0xB745C0)=1;
            *reinterpret_cast<unsigned char*>(0xB745C1)=1;
            ++gPgrpWorldScanCount;
            if((gPgrpWorldScanCount%180)==1)
                Log("[PGRP FC v0529 WORLD] scan=%u originalTunnel=%u originalOutside=%u allowBoth=1",
                    gPgrpWorldScanCount,
                    unsigned(gPgrpSavedTunnels),unsigned(gPgrpSavedExterior));
            return true;
        } __except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    void PgrpFreeCamEndWorldScan(bool activated){
        if(!activated)return;
        __try{
            *reinterpret_cast<unsigned char*>(0xB745C0)=gPgrpSavedTunnels;
            *reinterpret_cast<unsigned char*>(0xB745C1)=gPgrpSavedExterior;
        } __except(EXCEPTION_EXECUTE_HANDLER){}
    }
    void PgrpFreeCamBeforeRenderList(){
'@ 'include exterior road buildings during GTA world scan'
# GTA SA CRenderer::RequestObjectsInDirection=0x555CB0;
# requesting only forward leaves terrain behind the flying camera absent.
# Request one quadrant/1.15s, using asynchronous streaming (not LoadScene).
Patch 'native/sampraknet_bridge.cpp' @'
            static unsigned renderLists=0;
'@ @'
            static DWORD lastWorldPrefetch=0;
            static unsigned worldPrefetchStage=0;
            const DWORD prefetchNow=GetTickCount();
            if(prefetchNow-lastWorldPrefetch>=1150){
                lastWorldPrefetch=prefetchNow;
                __try{
                    const unsigned requested=*reinterpret_cast<const unsigned*>(0x8E4CB8);
                    const unsigned used=*reinterpret_cast<const unsigned*>(0x8E4CB4);
                    const unsigned budget=*reinterpret_cast<const unsigned*>(0x8A5A80);
                    const unsigned char disabled=*reinterpret_cast<const unsigned char*>(0x9654B0);
                    if(!disabled && requested<48 && budget>0 &&
                       used<budget-(std::min)(budget/5,16000000u)){
                        struct Position{float x,y,z;} worldPos{s.renderX,s.renderY,s.renderZ};
                        static constexpr float pi=3.14159265358979323846f;
                        const float angle=s.renderYaw+float(worldPrefetchStage%4)*(pi*.5f);
                        using RequestDirection=void(__cdecl*)(const void*,float,int);
                        reinterpret_cast<RequestDirection>(0x555CB0)(&worldPos,angle,0);
                        const unsigned after=*reinterpret_cast<const unsigned*>(0x8E4CB8);
                        if((worldPrefetchStage%4)==0 || after>requested)
                            Log("[PGRP FC v0529 PREFETCH] quadrant=%u queue=%u->%u used=%u budget=%u pos=(%.1f,%.1f,%.1f)",
                                worldPrefetchStage%4,requested,after,used,budget,
                                s.renderX,s.renderY,s.renderZ);
                        ++worldPrefetchStage;
                    }
                }__except(EXCEPTION_EXECUTE_HANDLER){
                    static DWORD lastPrefetchError=0;
                    if(prefetchNow-lastPrefetchError>=4000){
                        lastPrefetchError=prefetchNow;
                        Log("[PGRP FC v0529 PREFETCH] sector request unavailable");
                    }
                }
            }
            static unsigned renderLists=0;
'@ 'request terrain/building assets in all quadrants with bounded memory'
Patch 'native/sampraknet_bridge.cpp' @'
            const unsigned lods=*reinterpret_cast<const unsigned*>(0xB76840);
'@ @'
            const unsigned lods=*reinterpret_cast<const unsigned*>(0xB76840);
            // ms_aVisibleEntityPtrs: fixed array at 0xB75898 (1000).
            // CEntity typeStatus low 3 bits at +0x36 (building=1).
            unsigned visibleBuildings=0,visibleOther=0;
            if(visibles<=1000){
                auto* entities=reinterpret_cast<void* const*>(0xB75898);
                for(unsigned i=0;i<visibles;i++){
                    const auto* entity=reinterpret_cast<const unsigned char*>(entities[i]);
                    if(!entity)continue;
                    if((entity[0x36]&7)==1)++visibleBuildings;
                    else ++visibleOther;
                }
            }
'@ 'count actually visible building entities, not just pending models'
Patch 'native/sampraknet_bridge.cpp' @'
            if(gPgrpRoadPasses==0)
'@ @'
            Log("[PGRP FC v0529 ENTITIES] buildings=%u other=%u visible=%u lods=%u sectorScans=%u requested=%u",
                visibleBuildings,visibleOther,visibles,lods,gPgrpWorldScanCount,pending);
            if(visibles>0 && visibleBuildings==0)
                Log("[PGRP FC v0529 ENTITIES] ALERT no buildings survived active sector scan");
            if(gPgrpRoadPasses==0)
'@ 'diagnose map sector filtering versus actual streaming'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0528] BUILD=road-pass-clip-mouse-20261021 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0529] BUILD=world-sector-visibility-20261022 DLL=%s",dllPath);
'@ 'identify new source DLL path'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0528] BUILD=road-pass-clip-mouse-20261021 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0529] BUILD=world-sector-visibility-20261022 DLL_PATH_UNAVAILABLE");
'@ 'identify fallback DLL'
Write-Host 'PGRP v0.5.29: correct world-sector exterior/tunnel culling and async full-angle asset prefetch.'

param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
  $full=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
  $s=[IO.File]::ReadAllText($full)
  $n=([regex]::Matches($s,[regex]::Escape($before))).Count
  if($n -ne 1){throw "PGRP v0.5.26 $label expected one unique anchor, found $n"}
  [IO.File]::WriteAllText($full,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v0.5.26 PATCH OK: $label"
}
# Renderer.cpp CRenderer::ScanWorld computes a polygon from TheCamera's
# RwMatrix and Camera::CalculateDerivedValues frustum data. v0.5.25 fixed
# RW display only AFTER the game copied camera matrices. That removed
# inverted display but left renderer's candidate-entity/visibility lists
# based on stale, inverted frustum when constructed at another point.
# Recalculate BOTH the RW display transform and engine visibility planes
# just before ConstructRenderList scans the world.
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamAfterRWCopy(void* camera);
'@ @'
    void PgrpFreeCamAfterRWCopy(void* camera);
    void PgrpFreeCamBeforeRenderList();
'@ 'declare pre-render visibility correction'
Patch 'native/hooks.cpp' @'
static bool Install_CGameProcess_Hook()
'@ @'
// CRenderer::ConstructRenderList 0x5556E0 builds visible objects based on
// TheCamera and its frustum. Ensure the final RW camera pose and derived
// culling/frustum calculations agree BEFORE the list is constructed.
using ConstructRenderList_t=void(__cdecl*)();
static ConstructRenderList_t oPgrpConstructRenderList=nullptr;
static void __cdecl hkPgrpConstructRenderList(){
    opensamp::bridge::PgrpFreeCamBeforeRenderList();
    if(oPgrpConstructRenderList)oPgrpConstructRenderList();
}
static bool Install_PgrpRenderList_Hook(){
    void* addr=reinterpret_cast<void*>(0x5556E0);
    if(MH_CreateHook(addr,&hkPgrpConstructRenderList,
            reinterpret_cast<void**>(&oPgrpConstructRenderList))!=MH_OK)
        return false;
    return MH_EnableHook(addr)==MH_OK;
}

static bool Install_CGameProcess_Hook()
'@ 'hook the actual entity visibility-list construction stage'
Patch 'native/hooks.cpp' @'
    if(!Install_PgrpCameraCopy_Hook())
'@ @'
    if(!Install_PgrpRenderList_Hook())
        LogLine("[PGRP] WARNING FreeCam visibility synchronization unavailable\n");
    else
        LogLine("[PGRP] FreeCam camera/frustum sync at renderer installed\n");

    if(!Install_PgrpCameraCopy_Hook())
'@ 'install pre-culling Frustum/RenderWare synchronization'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamAfterCameraProcess(){
'@ @'
    // This runs once as the renderer constructs the visible-entity list,
    // NOT for every mouse packet. No extra camera rotation or smoothing.
    // Keep v0525's proven RW-frame correction (RwFrameTransform) intact.
    void PgrpFreeCamBeforeRenderList(){
        if(!PgrpFreeCamIsActive())return;
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.renderX,s.renderY,s.renderZ))return;
        auto* camera=reinterpret_cast<void*>(0xB6F028);
        // Make CCamera, active CCam, and normal RW camera use the same
        // position and basis. Calling Copy invokes the 0.5.25 post-copy
        // hook, which corrects the actual RwFrame even if GTA flips it.
        PgrpFreeCamBeforeRWCopy(camera);
        __try {
            using CopyCamera=void(__thiscall*)(void*,bool);
            reinterpret_cast<CopyCamera>(0x50AFA0)(camera,true);
            // R* CalculateDerivedValues refreshes cached frustum planes,
            // view-related normals, and visibility state. Previously GTA
            // had computed these before our FreeCam override.
            using Derived=void(__thiscall*)(void*,bool,bool);
            reinterpret_cast<Derived>(0x5150E0)(camera,false,false);
            static unsigned renderLists=0;
            if((++renderLists % 180)==0){
                const auto basis=pgrpfc_math::BuildBasis(
                    s.renderYaw,s.renderPitch);
                Log("[PGRP FC v0526] visibility frustum synced lists=%u cam=(%.2f,%.2f,%.2f) yaw=%.4f pitch=%.4f front=(%.3f,%.3f,%.3f)",
                    renderLists,s.renderX,s.renderY,s.renderZ,
                    s.renderYaw,s.renderPitch,
                    basis.forward.x,basis.forward.y,basis.forward.z);
            }
        } __except(EXCEPTION_EXECUTE_HANDLER){
            static DWORD lastError=0;
            const DWORD now=GetTickCount();
            if(now-lastError>2500){
                lastError=now;
                Log("[PGRP FC v0526] WARNING frustum refresh unavailable");
            }
        }
    }
    void PgrpFreeCamAfterCameraProcess(){
'@ 'align frustum, RW LTM and GTA camera before object culling'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0525] BUILD=rw-frame-repair-20261021 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0526] BUILD=visibility-frustum-sync-20261021 DLL=%s",dllPath);
'@ 'new version fingerprint loaded DLL path'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0525] BUILD=rw-frame-repair-20261021 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0526] BUILD=visibility-frustum-sync-20261021 DLL_PATH_UNAVAILABLE");
'@ 'new version fingerprint fallback'
Write-Host 'PGRP v0.5.26: RenderWare orientation and GTA visible entity frustum use the same camera pose.'

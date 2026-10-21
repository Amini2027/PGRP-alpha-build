param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$name,[string]$old,[string]$new,[string]$label) {
  $file=(Resolve-Path -LiteralPath (Join-Path $Root $name)).Path
  $source=[IO.File]::ReadAllText($file)
  $hits=([regex]::Matches($source,[regex]::Escape($old))).Count
  if($hits -ne 1){throw "PGRP v0.5.24 patch $label expected 1 match, got $hits"}
  [IO.File]::WriteAllText($file,$source.Replace($old,$new),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v0.5.24 PATCH OK $label"
}
Patch 'native/sampraknet_bridge.h' @'
    void PgrpFreeCamAfterCameraProcess();
'@ @'
    void PgrpFreeCamAfterCameraProcess();
    void PgrpFreeCamBeforeRWCopy(void* camera);
    void PgrpFreeCamAfterRWCopy(void* camera);
'@ 'declare RW synchronization entry points'
Patch 'native/hooks.cpp' @'
static bool Install_CGameProcess_Hook()
'@ @'
// GTA sometimes copies CCamera into RenderWare outside CCamera::Process.
// Force the current FreeCam pose before every copy and inspect post-copy RW.
using CCameraCopy_t=void(__thiscall*)(void*,bool);
static CCameraCopy_t oPgrpCameraCopy=nullptr;
static void __fastcall hkPgrpCameraCopy(void* camera,void*,bool update){
    opensamp::bridge::PgrpFreeCamBeforeRWCopy(camera);
    if(oPgrpCameraCopy)oPgrpCameraCopy(camera,update);
    opensamp::bridge::PgrpFreeCamAfterRWCopy(camera);
}
static bool Install_PgrpCameraCopy_Hook(){
    void* addr=reinterpret_cast<void*>(0x50AFA0);
    if(MH_CreateHook(addr,&hkPgrpCameraCopy,
           reinterpret_cast<void**>(&oPgrpCameraCopy))!=MH_OK)return false;
    return MH_EnableHook(addr)==MH_OK;
}

static bool Install_CGameProcess_Hook()
'@ 'supervise final GTA RenderWare camera-copy path'
Patch 'native/hooks.cpp' @'
    if(!Install_CameraProcess_Hook())
'@ @'
    if(!Install_PgrpCameraCopy_Hook())
        LogLine("[PGRP] WARNING RW camera copy hook failed\n");
    else
        LogLine("[PGRP] RenderWare camera copy hook installed\n");

    if(!Install_CameraProcess_Hook())
'@ 'install RenderWare copy hook'
Patch 'native/gui/imgui_manager.cpp' @'
            return DefWindowProc(hWnd,msg,wParam,lParam);
'@ @'
            if(GET_RAWINPUT_CODE_WPARAM(wParam)==RIM_INPUT)
                DefWindowProc(hWnd,msg,wParam,lParam);
            return 0;
'@ 'raw input cleanup followed by standard zero return'
Patch 'native/gui/imgui_manager.cpp' @'
    fly.dwFlags=0; // foreground only; preserve legacy cursor/button messages
'@ @'
    fly.dwFlags=RIDEV_NOLEGACY; // disable legacy mouse only while flying
'@ 'remove legacy mouse motion competing with FreeCam'
Patch 'native/sampraknet_bridge.cpp' @'
    void PgrpFreeCamAfterCameraProcess(){
'@ @'
    // No input updates occur here. The already-rendered FreeCam basis is
    // enforced before every engine copy into the RenderWare camera.
    void PgrpFreeCamBeforeRWCopy(void* camera){
        if(!camera || camera!=reinterpret_cast<void*>(0xB6F028) ||
           !PgrpFreeCamIsActive())return;
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.renderX,s.renderY,s.renderZ))return;
        const float pitch=(std::max)(-1.3962634f,
                    (std::min)(1.3962634f,s.renderPitch));
        const auto basis=pgrpfc_math::BuildBasis(s.renderYaw,pitch);
        const float pos[3]={s.renderX,s.renderY,s.renderZ};
        const float front[3]={basis.forward.x,basis.forward.y,basis.forward.z};
        const float up[3]={basis.up.x,basis.up.y,basis.up.z};
        const float right[3]={basis.right.x,basis.right.y,basis.right.z};
        auto* c=reinterpret_cast<std::uint8_t*>(camera);
        const unsigned index=c[0x59];
        if(index>=3)return;
        auto put3=[](std::uint8_t* dst,const float* v){
            std::memcpy(dst,v,3*sizeof(float));
        };
        auto* active=c+0x174+index*0x238;
        put3(active+0x19C,pos);
        put3(active+0x190,front);
        put3(active+0x1B4,up);
        put3(c+0x908,pos);
        auto* m=c+0x974;
        put3(m+0x00,right);
        put3(m+0x10,front);
        put3(m+0x20,up);
        put3(m+0x30,pos);
    }
    // RenderWare RwCamera carries its RwFrame in RwObject::parent +0x04.
    // RwFrame::modelling is +0x10, with right/up/at/pos at 0/16/32/48.
    // Unlike v0523 diagnostics, compare AFTER CopyCameraMatrixToRWCam.
    void PgrpFreeCamAfterRWCopy(void* camera){
        if(!camera || camera!=reinterpret_cast<void*>(0xB6F028) ||
           !PgrpFreeCamIsActive())return;
        static unsigned copyCount=0;
        static DWORD lastLog=0;
        ++copyCount;
        const DWORD now=GetTickCount();
        if(now-lastLog<650)return;
        lastLog=now;
        const auto& s=pgrpfc::st;
        const float pitch=(std::max)(-1.3962634f,
                   (std::min)(1.3962634f,s.renderPitch));
        const auto basis=pgrpfc_math::BuildBasis(s.renderYaw,pitch);
        __try {
            auto* c=reinterpret_cast<const std::uint8_t*>(camera);
            auto* rw=*reinterpret_cast<const std::uint8_t* const*>(c+0x954);
            if(!rw)return;
            auto* frame=*reinterpret_cast<const std::uint8_t* const*>(rw+0x04);
            if(!frame)return;
            const auto* m=reinterpret_cast<const float*>(frame+0x10);
            const float dotUp=m[4]*basis.up.x+m[5]*basis.up.y+m[6]*basis.up.z;
            const float dotAt=m[8]*basis.forward.x+
                m[9]*basis.forward.y+m[10]*basis.forward.z;
            const float dotAltUp=m[8]*basis.up.x+
                m[9]*basis.up.y+m[10]*basis.up.z;
            const float dotAltF=m[4]*basis.forward.x+
                m[5]*basis.forward.y+m[6]*basis.forward.z;
            Log("[PGRP FC v0524 RW] copies=%u rw=%p frame=%p mUpZ=%.3f mAtZ=%.3f dotUp=%.4f dotAt=%.4f alternateUp=%.4f alternateF=%.4f yaw=%.4f pitch=%.4f",
                copyCount,rw,frame,m[6],m[10],dotUp,dotAt,dotAltUp,dotAltF,
                s.renderYaw,pitch);
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            Log("[PGRP FC v0524 RW] post-copy snapshot unavailable");
        }
    }
    void PgrpFreeCamAfterCameraProcess(){
'@ 'enforce single FreeCam pose at RW copy; inspect real post-copy basis'
Patch 'native/sampraknet_bridge.cpp' @'
[PGRP FC v0523] BUILD=upright-rawguard-20261020
'@ @'
[PGRP FC v0524] BUILD=rw-copy-supervised-20261021
'@ 'new DLL build fingerprint'
Write-Host 'PGRP v0.5.24: supervised camera copy, true RW matrix diagnostics, single-owner raw mouse.'

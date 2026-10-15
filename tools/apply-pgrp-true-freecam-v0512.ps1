param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label){
 $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
 $src=[IO.File]::ReadAllText($file)
 $count=([regex]::Matches($src,[regex]::Escape($before))).Count
 if($count -ne 1){throw "FreeCam v0512 $label anchor count $count"}
 [IO.File]::WriteAllText($file,$src.Replace($before,$after),[Text.UTF8Encoding]::new($false))
 Write-Host "PGRP v0512 PATCH OK: $label"
}
Patch 'native/game/game.h' @'
        void* m_rwObject;     // +0x18  RpClump*
'@ @'
        void* m_rwObject;     // +0x18  RpClump*
        // CPlaceable uses its matrix world position once a matrix exists,
        // not the inline position used by an uninitialised bootstrap ped.
        Vec3 GetWorldPosition() const {
            if(!m_matrix) return m_position;
            const float* v=reinterpret_cast<const float*>(
                reinterpret_cast<const std::uint8_t*>(m_matrix)+0x30);
            return {v[0],v[1],v[2]};
        }
'@ 'ped real CPlaceable matrix position'
Patch 'native/sampraknet_bridge.cpp' @'
            pofSync->vecPos[0] = playerInfo[g_myPlayerID].onfootData.vecPos[0] + static_cast<float>(0.5);
            pofSync->vecPos[1] = playerInfo[g_myPlayerID].onfootData.vecPos[1] + static_cast<float>(0.5);
            pofSync->vecPos[2] = playerInfo[g_myPlayerID].onfootData.vecPos[2];
'@ @'
            // Critical: never replace the real local ped coordinates with
            // stale playerInfo plus a fabricated 0.5 offset. That defect
            // kept the SERVER physical position at the original spawn and
            // caused /freecam to begin there even after the ped walked away.
            // onFootUpdateAtNormalPos already populated pofSync->vecPos.
'@ 'stop overwriting real on-foot coordinates'
Patch 'native/sampraknet_bridge.cpp' @'
            pofSync->vecMoveSpeed[0] = 0.5;
            pofSync->vecMoveSpeed[1] = 0.5;
            pofSync->vecMoveSpeed[2] = playerInfo[g_myPlayerID].onfootData.vecMoveSpeed[2];
'@ @'
            // Preserve the actual CPhysical movement speed (or zero).
            // Fabricated 0.5 speed made server velocity tests inconsistent.
'@ 'stop fabricating on-foot movement speed'
Patch 'native/sampraknet_bridge.cpp' @'
    ofSync.fQuaternion[3] = fNormalModeRot;
    ofSync.vecPos[0] = fNormalModePos[0];
'@ @'
    const float half=fNormalModeRot*.5f;
    ofSync.fQuaternion[0]=std::cos(half);
    ofSync.fQuaternion[3]=std::sin(half);
    if(auto* ped=gta::sa::GetLocalPlayerPed()){
        const auto v=ped->MoveSpeed();
        ofSync.vecMoveSpeed[0]=v.x;
        ofSync.vecMoveSpeed[1]=v.y;
        ofSync.vecMoveSpeed[2]=v.z;
    }
    ofSync.vecPos[0] = fNormalModePos[0];
'@ 'send correct yaw quaternion and real velocity'
Patch 'native/sampraknet_bridge.cpp' @'
                fNormalModePos[0] = ped->m_position.x;
                fNormalModePos[1] = ped->m_position.y;
                fNormalModePos[2] = ped->m_position.z;
'@ @'
                auto pos=ped->GetWorldPosition();
                if(std::isfinite(pos.x)&&std::isfinite(pos.y)&&std::isfinite(pos.z)){
                    fNormalModePos[0]=pos.x;
                    fNormalModePos[1]=pos.y;
                    fNormalModePos[2]=pos.z;
                }
'@ 'sync actual matrix position'
Patch 'native/sampraknet_bridge.h' @'
    void PgrpTabDraw();
'@ @'
    void PgrpTabDraw();
    // Camera frame is overridden AFTER native CCamera::Process. This is
    // necessary because a SetCamPos opcode called from CGame::Process
    // is otherwise replaced by GTA's later camera update before rendering.
    void PgrpFreeCamAfterCameraProcess();
'@ 'declare post-process camera override'
Patch 'native/sampraknet_bridge.cpp' @'
        st.x=x;st.y=y;st.z=z;
        st.yaw=0.0f;st.pitch=0.0f;
'@ @'
        st.x=x;st.y=y;st.z=z;
        // Start at the player's real visible location, not the old spawn,
        // if it's consistent with the authoritative server position.
        if(auto* ped=gta::sa::GetLocalPlayerPed()){
            const auto pos=ped->GetWorldPosition();
            const float dx=pos.x-x,dy=pos.y-y,dz=pos.z-z+1.6f;
            if(IsFiniteWorld(pos.x,pos.y,pos.z) &&
               dx*dx+dy*dy+dz*dz < 15.f*15.f){
                st.x=pos.x;st.y=pos.y;st.z=pos.z+1.6f;
            }
        }
        // Keep the current viewing direction when entering free flight.
        auto* cam=reinterpret_cast<const std::uint8_t*>(0xB6F028);
        unsigned active=cam[0x59];
        st.yaw=0.f;st.pitch=0.f;
        if(active<3){
            const float* f=reinterpret_cast<const float*>(
                cam+0x174+active*0x238+0x190);
            const float len=std::sqrt(f[0]*f[0]+f[1]*f[1]+f[2]*f[2]);
            if(std::isfinite(len)&&len>.75f&&len<1.25f){
                st.yaw=std::atan2(f[1],f[0]);
                st.pitch=std::asin((std::max)(-.99f,(std::min)(.99f,f[2])));
            }
        }
'@ 'begin camera at physical player and preserve viewing angle'
Patch 'native/sampraknet_bridge.cpp' @'
        const bool focus=(g_hwnd != nullptr && GetForegroundWindow()==g_hwnd);
'@ @'
        const bool focus=(g_hwnd != nullptr &&
            (GetForegroundWindow()==g_hwnd ||
             GetForegroundWindow()==GetAncestor(g_hwnd,GA_ROOT)));
'@ 'use actual root game window focus'
Patch 'native/sampraknet_bridge.cpp' @'
    bool IsPgrpGameplayReady() {
'@ @'
    void PgrpFreeCamAfterCameraProcess(){
        if(!pgrpfc::st.active || !g_pgrpEndpoint || !iAreWeConnected)
            return;
        // Plugin-SDK GTA SA 1.0 documented CCamera/CCam offsets.
        // CCamera::Process runs AFTER our network tick; earlier SCM 015F/0160
        // positions were overwritten each frame. Inject the final renderer
        // camera transform HERE, between engine camera processing and render.
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.x,s.y,s.z))return;
        const float cp=std::cos(s.pitch),sp=std::sin(s.pitch);
        const float fx=cp*std::cos(s.yaw),fy=cp*std::sin(s.yaw),fz=sp;
        const float right[3]={-std::sin(s.yaw),std::cos(s.yaw),0.f};
        const float up[3]={-std::cos(s.yaw)*sp,-std::sin(s.yaw)*sp,cp};
        const float forward[3]={fx,fy,fz};
        const float pos[3]={s.x,s.y,s.z};
        std::uint8_t* camera=reinterpret_cast<std::uint8_t*>(0xB6F028);
        const unsigned index=camera[0x59];
        if(index>=3)return;
        auto put3=[](std::uint8_t* at,const float* v){
            std::memcpy(at,v,sizeof(float)*3);
        };
        // Active CCam::m_vecSource / m_vecFront / m_vecUp.
        auto* activeCam=camera+0x174+index*0x238;
        put3(activeCam+0x19C,pos);
        put3(activeCam+0x190,forward);
        put3(activeCam+0x1B4,up);
        // CCamera::m_vecGameCamPos + CMatrix right/up/at/position.
        put3(camera+0x908,pos);
        auto* m=camera+0x974;
        put3(m+0x00,right);
        put3(m+0x10,up);
        put3(m+0x20,forward);
        put3(m+0x30,pos);
        // Synchronise the RenderWare camera with the overridden GTA matrix.
        // Does not create a new camera, texture, entity or render target.
        using CopyFn=void(__thiscall*)(void*,bool);
        __try {
            reinterpret_cast<CopyFn>(0x50AFA0)(camera,true);
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            // Remain fail-safe on modified GTA builds; no crash loop.
        }
    }
    bool IsPgrpGameplayReady() {
'@ 'update the actual rendered camera after GTA camera Process'
Patch 'native/hooks.cpp' @'
static bool Install_CGameProcess_Hook()
'@ @'
// Native camera is updated by the engine after CGame::Process. Hook that
// stage as well, otherwise /freecam only moves its minimap/streaming origin.
using CCameraProcess_t=void(__thiscall*)(void*);
static CCameraProcess_t oCameraProcess=nullptr;
static void __fastcall hkCameraProcess(void* camera,void*){
    if(oCameraProcess)oCameraProcess(camera);
    opensamp::bridge::PgrpFreeCamAfterCameraProcess();
}
static bool Install_CameraProcess_Hook(){
    constexpr auto addr=reinterpret_cast<void*>(0x52B730);
    if(MH_CreateHook(addr,&hkCameraProcess,
         reinterpret_cast<void**>(&oCameraProcess))!=MH_OK)return false;
    return MH_EnableHook(addr)==MH_OK;
}

static bool Install_CGameProcess_Hook()
'@ 'hook final GTA camera processing stage'
Patch 'native/hooks.cpp' @'
    if (!Install_CGameProcess_Hook())
'@ @'
    if(!Install_CameraProcess_Hook())
        LogLine("[PGRP] WARNING CameraProcess hook failed; native freecam render may not track\n");
    else
        LogLine("[PGRP] Post-camera render hook installed\n");

    if (!Install_CGameProcess_Hook())
'@ 'enable post-process camera hook during bootstrap'
Write-Host 'PGRP 0.5.12 corrected local on-foot sync and native render camera.'

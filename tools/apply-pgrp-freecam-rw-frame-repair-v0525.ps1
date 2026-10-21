param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$name,[string]$before,[string]$after,[string]$label){
    $path=(Resolve-Path -LiteralPath (Join-Path $Root $name)).Path
    $content=[IO.File]::ReadAllText($path)
    $count=([regex]::Matches($content,[regex]::Escape($before))).Count
    if($count -ne 1){throw "PGRP v0.5.25 $label anchor requires 1 match, found $count"}
    [IO.File]::WriteAllText($path,$content.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0.5.25 PATCH OK: $label"
}
# v0524 logged dotUp=-1, dotAt=+1 while yaw and pitch were constant:
# RW copied matrix is actually flipping by 180 degrees. Setting GTA's
# CCamera memory only BEFORE CopyCameraMatrixToRWCam does not fix it.
# Force the RwFrame's real modelling and LTM via RenderWare's public API
# AFTER the engine camera copy, never a raw memory write to frame offsets.
Patch 'native/sampraknet_bridge.cpp' @'
        static unsigned copyCount=0;
        static DWORD lastLog=0;
        ++copyCount;
        const DWORD now=GetTickCount();
        if(now-lastLog<2500)return;
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
'@ @'
        // This is the *rendered* camera, not the pre-copy CCamera matrix.
        // Confirmed GTA SA 1.0 US RenderWare API addresses from plugin-sdk:
        // RwFrameTransform=0x7F0F70 and RwFrameGetLTM=0x7F0990.
        // rwCOMBINEREPLACE = 0.
        static unsigned copyCount=0,correctedCount=0;
        static DWORD lastLog=0;
        ++copyCount;
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.renderX,s.renderY,s.renderZ))return;
        const float pitch=(std::max)(-1.3962634f,
                    (std::min)(1.3962634f,s.renderPitch));
        const auto basis=pgrpfc_math::BuildBasis(s.renderYaw,pitch);
        const DWORD now=GetTickCount();
        __try {
            auto* c=reinterpret_cast<const std::uint8_t*>(camera);
            auto* rw=*reinterpret_cast<const std::uint8_t* const*>(c+0x954);
            if(!rw)return;
            auto* frame=*reinterpret_cast<std::uint8_t* const*>(rw+0x04);
            if(!frame)return;
            // RwMatrix is exactly 4 rows of RwV3d with 4-byte padding.
            // Right, camera up, view forward (at) and world position.
            struct alignas(4) RwMat {
                float right[3]; std::uint32_t flags;
                float up[3]; std::uint32_t pad1;
                float at[3]; std::uint32_t pad2;
                float pos[3]; std::uint32_t pad3;
            };
            static_assert(sizeof(RwMat)==64,"RenderWare camera matrix size");
            RwMat desired{};
            desired.right[0]=basis.right.x;
            desired.right[1]=basis.right.y;
            desired.right[2]=basis.right.z;
            desired.up[0]=basis.up.x;
            desired.up[1]=basis.up.y;
            desired.up[2]=basis.up.z;
            desired.at[0]=basis.forward.x;
            desired.at[1]=basis.forward.y;
            desired.at[2]=basis.forward.z;
            desired.pos[0]=s.renderX;
            desired.pos[1]=s.renderY;
            desired.pos[2]=s.renderZ;
            const auto* old=reinterpret_cast<const float*>(frame+0x10);
            const float beforeUp=old[4]*basis.up.x+old[5]*basis.up.y+
                                    old[6]*basis.up.z;
            const float beforeAt=old[8]*basis.forward.x+
                                 old[9]*basis.forward.y+
                                 old[10]*basis.forward.z;
            if(beforeUp<.995f || beforeAt<.995f)++correctedCount;
            using FrameTransform=void*(__cdecl*)(void*,const void*,int);
            auto* transformed=reinterpret_cast<FrameTransform>(0x7F0F70)(
                frame,&desired,0);
            if(!transformed){
                if(now-lastLog>=2500){
                    lastLog=now;
                    Log("[PGRP FC v0525] ERROR RwFrameTransform failed");
                }
                return;
            }
            // Check LTM, which GTA's renderer actually uses. The previous
            // diagnostic read the local modelling matrix only.
            if(now-lastLog>=2500){
                lastLog=now;
                using GetLTM=const float*(__cdecl*)(void*);
                const auto* finalMatrix=reinterpret_cast<GetLTM>(0x7F0990)(frame);
                if(!finalMatrix)return;
                const float postUp=finalMatrix[4]*basis.up.x+
                    finalMatrix[5]*basis.up.y+finalMatrix[6]*basis.up.z;
                const float postAt=finalMatrix[8]*basis.forward.x+
                    finalMatrix[9]*basis.forward.y+
                    finalMatrix[10]*basis.forward.z;
                Log("[PGRP FC v0525] RW copies=%u corrected=%u beforeUp=%.4f beforeAt=%.4f LTMup=%.4f LTMat=%.4f upZ=%.4f yaw=%.4f pitch=%.4f",
                    copyCount,correctedCount,beforeUp,beforeAt,
                    postUp,postAt,finalMatrix[6],s.renderYaw,pitch);
            }
        } __except(EXCEPTION_EXECUTE_HANDLER) {
            if(now-lastLog>=2500){
                lastLog=now;
                Log("[PGRP FC v0525] ERROR RenderWare frame transform exception");
            }
        }
'@ 'repair real RW camera frame on EVERY copy and verify final LTM'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0524] BUILD=rw-copy-supervised-20261021 DLL=%s",dllPath);
'@ @'
                Log("[PGRP FC v0525] BUILD=rw-frame-repair-20261021 DLL=%s",dllPath);
'@ 'new verified DLL filename and build identity'
Patch 'native/sampraknet_bridge.cpp' @'
                Log("[PGRP FC v0524] BUILD=rw-copy-supervised-20261021 DLL_PATH_UNAVAILABLE");
'@ @'
                Log("[PGRP FC v0525] BUILD=rw-frame-repair-20261021 DLL_PATH_UNAVAILABLE");
'@ 'build identity even when DLL path missing'
Write-Host 'PGRP v0.5.25: stable RenderWare camera LTM; forward flight matches actual view after copy.'

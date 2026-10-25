param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$path,[string]$before,[string]$after,[string]$label) {
    $file=(Resolve-Path -LiteralPath (Join-Path $Root $path)).Path
    $source=[IO.File]::ReadAllText($file)
    $count=([regex]::Matches($source,[regex]::Escape($before))).Count
    if($count -ne 1) {throw "FreeCam v0.5.16 '$label' anchor count $count"}
    [IO.File]::WriteAllText($file,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0.5.16 PATCH OK: $label"
}
# Store simulation pose and stable smoothed render pose separately.
Patch 'native/sampraknet_bridge.cpp' @'
        float streamX=0,streamY=0;
        POINT center{};
'@ @'
        float streamX=0,streamY=0;
        float velocityX=0,velocityY=0,velocityZ=0;
        float renderX=0,renderY=0,renderZ=0;
        float renderYaw=0,renderPitch=0;
        DWORD lastRenderTick=0;
        POINT center{};
'@ 'split simulation and presentation pose'
# Finalise initial freecam position after the v0.5.12 source fix has read
# the real local ped and camera forward vector. Initialise render pose to the
# exact actual starting location to avoid interpolation from the map origin.
Patch 'native/sampraknet_bridge.cpp' @'
        st.lastTick=GetTickCount();
        st.streamX=x;st.streamY=y;
'@ @'
        st.pitch=(std::max)(-1.20f,(std::min)(1.20f,st.pitch));
        st.renderX=st.x;st.renderY=st.y;st.renderZ=st.z;
        st.renderYaw=st.yaw;st.renderPitch=st.pitch;
        st.lastRenderTick=GetTickCount();
        st.lastTick=GetTickCount();
        st.streamX=x;st.streamY=y;
'@ 'initialize render pose and cap start pitch safely'
Patch 'native/sampraknet_bridge.cpp' @'
        // Native camera SCM update <=30 FPS; don't dispatch 120+ opcodes/s
        // on PCs with low CPU or integrated graphics.
        if(now-st.lastTick < 32) return;
'@ @'
        // Flight simulation can run at up to 60 Hz. The heavyweight old
        // camera SCM calls have been removed; final GTA camera matrix is
        // updated in the separate post-CameraProcess render hook.
        if(now-st.lastTick < 16) return;
'@ 'increase input simulation cadence with cheap rendering'
Patch 'native/sampraknet_bridge.cpp' @'
            const float mouseScale=0.00118f;
            st.yaw += float((std::max)(-225L,(std::min)(225L,dx)))*mouseScale;
            st.pitch -= float((std::max)(-225L,(std::min)(225L,dy)))*mouseScale;
            st.pitch=(std::max)(-1.48f,(std::min)(1.48f,st.pitch));
'@ @'
            // Stable zero-roll mouse look. Keep pitch a safe distance
            // from +/-90 degrees: horizon never overturns at the poles.
            // Wrap yaw so extremely long flights cannot lose precision.
            const float mouseScale=0.00098f;
            const float deltaX=float((std::max)(-220L,(std::min)(220L,dx)));
            const float deltaY=float((std::max)(-220L,(std::min)(220L,dy)));
            st.yaw=std::remainder(st.yaw+deltaX*mouseScale,6.283185307f);
            st.pitch=(std::max)(-1.20f,
                (std::min)(1.20f,st.pitch-deltaY*mouseScale));
'@ 'keep world upright even when looking sharply down'
Patch 'native/sampraknet_bridge.cpp' @'
            const float mag=std::sqrt(vx*vx+vy*vy+vz*vz);
            if(mag>0.001f){
                const float speed=held(VK_SHIFT)?72.f:26.f;
                const float dist=dt*speed/mag;
                const float nx=st.x+vx*dist,ny=st.y+vy*dist,nz=st.z+vz*dist;
                if(IsFiniteWorld(nx,ny,nz)){st.x=nx;st.y=ny;st.z=nz;}
            }
'@ @'
            // Damped linear velocity prevents abrupt 30Hz starts/stops,
            // diagonals stay normalized and Shift changes target speed.
            const float magnitude=std::sqrt(vx*vx+vy*vy+vz*vz);
            const float speed=held(VK_SHIFT)?72.f:26.f;
            const float inverse=magnitude>.001f ? (speed/magnitude) : 0.f;
            const float blend=1.f-std::exp(-dt*14.f);
            st.velocityX+=(vx*inverse-st.velocityX)*blend;
            st.velocityY+=(vy*inverse-st.velocityY)*blend;
            st.velocityZ+=(vz*inverse-st.velocityZ)*blend;
            const float nx=st.x+st.velocityX*dt;
            const float ny=st.y+st.velocityY*dt;
            const float nz=st.z+st.velocityZ*dt;
            if(IsFiniteWorld(nx,ny,nz)){st.x=nx;st.y=ny;st.z=nz;}
'@ 'smooth flying motion without floating-point overshoot'
Patch 'native/sampraknet_bridge.cpp' @'
            ClearMouse();
        }
        // SCM opcodes 015F and 0160 update position and target of camera.
'@ @'
            ClearMouse();
            st.velocityX=0.f;st.velocityY=0.f;st.velocityZ=0.f;
        }
        // Post-camera-process renderer is the only camera writer.
'@ 'stop drift while in chat or alt-tab'
Patch 'native/sampraknet_bridge.cpp' @'
        // Post-camera-process renderer is the only camera writer.
        // Both dispatches are from the game thread; no background memory hooks.
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
        gta::sa::scm::push_float(st.x+std::cos(st.pitch)*std::cos(st.yaw)*30.f);
        gta::sa::scm::push_float(st.y+std::cos(st.pitch)*std::sin(st.yaw)*30.f);
        gta::sa::scm::push_float(st.z+std::sin(st.pitch)*30.f);
        gta::sa::scm::push_int(2);
        gta::sa::scm::exec();
'@ @'
        // Flight controls affect only simulation state here. The sole writer
        // of the GTA camera is the post-CCamera::Process render override.
        // Do not send SCM 015F/0160 or reset fixed camera mode every frame.
'@ 'remove both competing SCM and fixed-camera writers'
Patch 'native/sampraknet_bridge.cpp' @'
        const auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.x,s.y,s.z))return;
        const float cp=std::cos(s.pitch),sp=std::sin(s.pitch);
        const float fx=cp*std::cos(s.yaw),fy=cp*std::sin(s.yaw),fz=sp;
        const float right[3]={-std::sin(s.yaw),std::cos(s.yaw),0.f};
        const float up[3]={-std::cos(s.yaw)*sp,-std::sin(s.yaw)*sp,cp};
        const float forward[3]={fx,fy,fz};
        const float pos[3]={s.x,s.y,s.z};
'@ @'
        auto& s=pgrpfc::st;
        if(!pgrpfc::IsFiniteWorld(s.x,s.y,s.z))return;
        // Separate visual camera updates from 30/60Hz movement tick. A
        // time-based exponential blend keeps camera smooth on slower PCs.
        const DWORD now=GetTickCount();
        float dt=(std::min)(.050f,float(now-s.lastRenderTick)*.001f);
        if(dt<0.f)dt=0.f;
        s.lastRenderTick=now;
        const float positionAlpha=1.f-std::exp(-dt*16.f);
        const float rotationAlpha=1.f-std::exp(-dt*22.f);
        s.renderX+=(s.x-s.renderX)*positionAlpha;
        s.renderY+=(s.y-s.renderY)*positionAlpha;
        s.renderZ+=(s.z-s.renderZ)*positionAlpha;
        s.renderYaw+=std::remainder(s.yaw-s.renderYaw,6.283185307f)*rotationAlpha;
        s.renderPitch+=(s.pitch-s.renderPitch)*rotationAlpha;
        const float pitch=(std::max)(-1.20f,(std::min)(1.20f,s.renderPitch));
        const float cp=std::cos(pitch),sp=std::sin(pitch);
        const float cy=std::cos(s.renderYaw),sy=std::sin(s.renderYaw);
        // Orthogonal basis derived from a fixed world-up. For any supported
        // pitch the up vector has positive Z, so the horizon cannot roll.
        const float right[3]={-sy,cy,0.f};
        const float up[3]={-cy*sp,-sy*sp,cp};
        const float forward[3]={cy*cp,sy*cp,sp};
        const float pos[3]={s.renderX,s.renderY,s.renderZ};
'@ 'smooth upright rendering using one orthonormal camera basis'
Write-Host 'PGRP v0.5.16 FreeCam camera has horizon lock and smooth single-writer render.'

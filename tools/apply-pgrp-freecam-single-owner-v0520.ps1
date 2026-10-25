param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$file,[string]$before,[string]$after,[string]$label){
  $path=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
  $src=[IO.File]::ReadAllText($path)
  $hits=([regex]::Matches($src,[regex]::Escape($before))).Count
  if($hits -ne 1){throw "PGRP 0.5.20 $label expects 1 anchor; got $hits"}
  [IO.File]::WriteAllText($path,$src.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP 0.5.20 PATCH OK: $label"
}
# Raw mouse packets must be owned by ONE consumer in flight. The old WndProc
# recorded each WM_INPUT and then passed it to GTA's original procedure,
# permitting its default camera controller to process the same mouse again.
Patch 'native/gui/imgui_manager.cpp' @'
                opensamp::bridge::PgrpFreeCamRawMouse(
                    packet.data.mouse.lLastX,packet.data.mouse.lLastY);
            }
        }
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
'@ @'
                opensamp::bridge::PgrpFreeCamRawMouse(
                    packet.data.mouse.lLastX,packet.data.mouse.lLastY);
            }
            // WM_INPUT cleanup belongs to DefWindowProc; never dispatch
            // this packet to the native GTA camera while FreeCam owns it.
            return DefWindowProc(hWnd,msg,wParam,lParam);
        }
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
'@ 'FreeCam consumes WM_INPUT once, not twice'
# GTA also processes the ordinary WM_MOUSEMOVE event and may shift camera mode
# before our native post-process view override. Suppress it during flight only.
Patch 'native/gui/imgui_manager.cpp' @'
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
        // Native FreeCam polls physical keys (GetAsyncKeyState), not the GTA
'@ @'
        const bool dialog_active = opensamp::gui::Dialog::Get().IsActive();
        if(g_pgrpRawInFlight && opensamp::bridge::PgrpFreeCamWantsRawMouse()
           && !g_chat.IsActive() && !dialog_active && msg==WM_MOUSEMOVE)
            return 0; // Only FreeCam gets motion. Retain mouse clicks.
        // Native FreeCam polls physical keys (GetAsyncKeyState), not the GTA
'@ 'avoid GTA legacy camera reacting during flight'
Patch 'native/gui/imgui_manager.cpp' @'
    const bool wants=focused && opensamp::bridge::PgrpFreeCamWantsRawMouse();
'@ @'
    const bool wants=focused && opensamp::bridge::PgrpFreeCamWantsRawMouse()
        && !g_chat.IsActive() && !opensamp::gui::Dialog::Get().IsActive();
'@ 'return raw input to GTA for chat and dialogs'
# v0519 erroneously admitted 12000 raw device counts per frame. With its
# sensitivity one rogue packet could rotate the view many times in a frame.
# Retain moderate impulses with a bounded carry across frames rather than
# discarding entire fast swipes, and discard corrupt very large packets.
Patch 'native/sampraknet_bridge.cpp' @'
        if(dx>-12000 && dx<12000 && dy>-12000 && dy<12000){
            pgrpfc::rawX.fetch_add(dx,std::memory_order_relaxed);
            pgrpfc::rawY.fetch_add(dy,std::memory_order_relaxed);
        }
'@ @'
        if(dx>-4000 && dx<4000 && dy>-4000 && dy<4000){
            pgrpfc::rawX.fetch_add(dx,std::memory_order_relaxed);
            pgrpfc::rawY.fetch_add(dy,std::memory_order_relaxed);
        }
'@ 'discard corrupt HID bursts before accumulation'
Patch 'native/sampraknet_bridge.cpp' @'
        float renderYaw=0,renderPitch=0;
'@ @'
        float renderYaw=0,renderPitch=0;
        float pendingMouseX=0,pendingMouseY=0; // deferred bounded input
        bool lastF11=false;
'@ 'introduce bounded mouse backlog and session-local toggle latch'
Patch 'native/sampraknet_bridge.cpp' @'
            const float mx=float((std::max)(-12000L,(std::min)(12000L,dx)));
            const float my=float((std::max)(-12000L,(std::min)(12000L,dy)));
'@ @'
            s.pendingMouseX=(std::max)(-1800.f,
                (std::min)(1800.f,s.pendingMouseX+float(dx)));
            s.pendingMouseY=(std::max)(-1800.f,
                (std::min)(1800.f,s.pendingMouseY+float(dy)));
            // Each frame moves at most ~9 degrees. Even a huge valid
            // swipe is released smoothly rather than flipping the scene.
            const float mx=(std::max)(-145.f,(std::min)(145.f,s.pendingMouseX));
            const float my=(std::max)(-145.f,(std::min)(145.f,s.pendingMouseY));
            s.pendingMouseX-=mx;
            s.pendingMouseY-=my;
'@ 'bounded angular velocity and buffered high-DPI mouse input'
Patch 'native/sampraknet_bridge.cpp' @'
            static bool wasF11Pressed=false;
            const bool f11Pressed=(GetAsyncKeyState(VK_F11)&0x8000)!=0;
            if(f11Pressed && !wasF11Pressed){
                s.fullVertical=!s.fullVertical;
                if(!s.fullVertical){
                    s.pitch=(std::max)(-1.55334306f,
                        (std::min)(1.55334306f,s.pitch));
                }
                Log("[PGRP FC v0519] F11 camera mode: %s",
                    s.fullVertical?"FULL_VERTICAL_360":"UPRIGHT_360_YAW");
                pgrpfc::ShowMode(s.fullVertical);
            }
            wasF11Pressed=f11Pressed;
'@ @'
            const bool f11Pressed=(GetAsyncKeyState(VK_F11)&0x8000)!=0;
            const bool ctrlPressed=(GetAsyncKeyState(VK_CONTROL)&0x8000)!=0;
            if(f11Pressed && !s.lastF11){
                // F11 always returns to stable upright mode. Full vertical
                // inversion is available ONLY after explicit Ctrl+F11.
                s.fullVertical=ctrlPressed ? !s.fullVertical : false;
                if(!s.fullVertical){
                    s.pitch=(std::max)(-1.3962634f,
                        (std::min)(1.3962634f,s.pitch));
                }
                s.pendingMouseX=0.f;s.pendingMouseY=0.f;
                Log("[PGRP FC v0520] Camera mode: %s",
                    s.fullVertical?"FULL_VERTICAL_360":"UPRIGHT_360_YAW");
                pgrpfc::ShowMode(s.fullVertical);
            }
            s.lastF11=f11Pressed;
'@ 'F11 rescue-to-upright, deliberate Ctrl+F11 full-vertical mode'
Patch 'native/sampraknet_bridge.cpp' @'
                s.pitch=(std::max)(-1.55334306f,
                    (std::min)(1.55334306f,s.pitch-my*mouseScale));
'@ @'
                s.pitch=(std::max)(-1.3962634f,
                    (std::min)(1.3962634f,s.pitch-my*mouseScale));
'@ 'upright mode stays away from engine camera poles'
Patch 'native/sampraknet_bridge.cpp' @'
            :(std::max)(-1.55334306f,
                (std::min)(1.55334306f,s.renderPitch));
'@ @'
            :(std::max)(-1.3962634f,
                (std::min)(1.3962634f,s.renderPitch));
'@ 'enforce upright pitch at render not just input'
Patch 'native/sampraknet_bridge.cpp' @'
        st.pitch=(std::max)(-1.55334306f,(std::min)(1.55334306f,st.pitch));
'@ @'
        st.pitch=(std::max)(-1.3962634f,(std::min)(1.3962634f,st.pitch));
'@ 'safe 80-degree camera startup'
Patch 'native/sampraknet_bridge.cpp' @'
            ? std::string("[PGRP FreeCam] FULL VERTICAL 360: horizon inverts naturally past 90 deg. F11 = upright.")
            : std::string("[PGRP FreeCam] UPRIGHT: 360 yaw, +/-89 pitch. F11 = vertical loops."));
'@ @'
            ? std::string("[PGRP FreeCam] FULL VERTICAL 360: inversion beyond 90 is expected. F11 resets.")
            : std::string("[PGRP FreeCam] UPRIGHT: full 360 yaw, +/-80 pitch. Ctrl+F11 enters vertical spin."));
'@ 'accurate on-screen user controls'
# Avoid stale input after focus change/modal; flushing queued impulses is
# essential to stop camera jumping when user returns from Alt-Tab or chat.
Patch 'native/sampraknet_bridge.cpp' @'
        }else{
            pgrpfc::ClearMouse();
        }
        // QueryPerformanceCounter has sub-millisecond resolution
'@ @'
        }else{
            pgrpfc::ClearMouse();
            s.pendingMouseX=0.f;s.pendingMouseY=0.f;
        }
        // QueryPerformanceCounter has sub-millisecond resolution
'@ 'clear input backlog during focus changes'
Write-Host 'PGRP v0.5.20: single mouse consumer, capped slew, upright rescue, no native GTA mouse race.'

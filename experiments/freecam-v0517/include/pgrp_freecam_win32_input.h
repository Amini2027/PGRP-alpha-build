#pragma once
// Example WM_INPUT collector. The host game's existing WindowProc and
// raw-input registration are authoritative. This helper NEVER registers,
// unregisters, captures, warps or hides the mouse by itself.
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "pgrp_freecam_controller.h"
namespace pgrp {
class RawMouseFrame {
public:
    void reset() { dx_ = 0; dy_ = 0; }
    void handle(HRAWINPUT handle, bool allowInput) {
        if (!allowInput) return;
        // GTA is Win32 x86; a statically sized RAWINPUT is sufficient for a
        // RIM_TYPEMOUSE packet (for arbitrary HID reports use a dynamic buffer).
        RAWINPUT input{};
        UINT size=sizeof(input);
        const UINT copied=GetRawInputData(handle,RID_INPUT,&input,&size,sizeof(RAWINPUTHEADER));
        if(copied==static_cast<UINT>(-1) || copied<sizeof(RAWINPUT))return;
        if(input.header.dwType!=RIM_TYPEMOUSE)return;
        if((input.data.mouse.usFlags&MOUSE_MOVE_ABSOLUTE)!=0)return;
        dx_+=input.data.mouse.lLastX;
        dy_+=input.data.mouse.lLastY;
    }
    void flush(Controls& c,bool windowForeground) {
        // Consume and clear regardless of focus; prevents delayed spike after Alt+Tab.
        if(windowForeground){c.mouse_dx+=dx_;c.mouse_dy+=dy_;}
        reset();
    }
private:
    double dx_=0.0,dy_=0.0;
};
} // namespace pgrp
#endif

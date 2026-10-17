#ifdef _WIN32
#include "../include/pgrp_freecam_win32_input.h"
int main() {
    pgrp::RawMouseFrame frame;
    pgrp::Controls control{};
    frame.flush(control, false);
    return (control.mouse_dx == 0 && control.mouse_dy == 0) ? 0 : 1;
}
#else
int main() { return 0; }
#endif

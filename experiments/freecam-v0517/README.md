# PGRP FreeCam Core — v0.5.17 candidate

**Scope:** Platform-independent C++17 camera math and tests, plus an optional Windows raw-mouse input collector. This is **not** a Windows installer or a patch directly applied to the user's latest 0.5.16 source. It is safe to review and integrate in a dedicated version branch.

- `include/pgrp_freecam_controller.h`: quaternion-based unrestricted 6-DOF rotation, relative mouse deltas, movement and focus handling.
- `include/pgrp_freecam_win32_input.h`: lightweight WM_INPUT packet reader that does not change GTA's global mouse registration.
- `tests/test_freecam.cpp`: runnable unit tests for 360-degree vertical rotation, focus transitions, no flip/pole singularity, W/S directions and NaN guard.
- `docs/INTEGRATION_FA.md`: Persian integration and acceptance checklist.

Tested here with GCC C++17 and AddressSanitizer/UBSan on Linux. Windows/MSVC and actual in-game tests **remain pending** because latest native v0.5.16 source/install assets are not available to this execution environment.

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pedantic tests/test_freecam.cpp -o freecam_test
./freecam_test
```

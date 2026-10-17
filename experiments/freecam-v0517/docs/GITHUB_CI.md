## CI gate
- Ubuntu: compile/run quaternion physics unit tests with GCC17.
- Windows x86: compile/run same unit tests with MSVC, plus compile Windows RAWINPUT helper against user32.
- This CI **does not run real GTA, injector, RenderWare camera hooks, open.mp networking or the v0.5.16 setup**. Those must be tested in the full native-client integration pipeline.

param([string]$Root = 'upstream')
$ErrorActionPreference = 'Stop'
$nl = [Environment]::NewLine
function Replace-Exact([string]$Relative, [string]$Before, [string]$After) {
    $path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing source: $Relative" }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $source = [IO.File]::ReadAllText($resolved)
    $hits = ([regex]::Matches($source,[regex]::Escape($Before))).Count
    if ($hits -ne 1) { throw "Unexpected match count $hits in $Relative for: $Before" }
    [IO.File]::WriteAllText($resolved, $source.Replace($Before,$After), [Text.UTF8Encoding]::new($false))
    Write-Host "TRACE PATCH OK $Relative : $Before"
}
$nativeTrace = @'
static void PgrpTrace(const char* message)
{
    HANDLE h = CreateFileW(L"PGRP_Native_Init.log", FILE_APPEND_DATA,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD written = 0;
    WriteFile(h, message, static_cast<DWORD>(strlen(message)), &written, nullptr);
    const char newline[] = "\r\n";
    WriteFile(h, newline, 2, &written, nullptr);
    CloseHandle(h);
}
'@
Replace-Exact 'native/dllmain.cpp' '#include <stdio.h>' ('#include <stdio.h>'+$nl+'#include <cstring>')
Replace-Exact 'native/dllmain.cpp' 'DWORD WINAPI MainThread(LPVOID)' ($nativeTrace+$nl+'DWORD WINAPI MainThread(LPVOID)')
Replace-Exact 'native/dllmain.cpp' '    InstallCrashHandler();' ('    PgrpTrace("01 Native main thread entered");'+$nl+'    InstallCrashHandler();'+$nl+'    PgrpTrace("02 Crash handler installed");')
Replace-Exact 'native/dllmain.cpp' '    ApplyBaseMemoryPatches();' ('    PgrpTrace("03 Applying base memory patches");'+$nl+'    ApplyBaseMemoryPatches();'+$nl+'    PgrpTrace("04 Base memory patches completed");')
Replace-Exact 'native/dllmain.cpp' '    MH_Initialize();' ('    if (MH_Initialize() != MH_OK) { PgrpTrace("ERROR MinHook init failed"); return 2; }'+$nl+'    PgrpTrace("05 MinHook initialized");')
Replace-Exact 'native/dllmain.cpp' '    GameReady_Install();' ('    PgrpTrace("06 Starting GameReady_Install");'+$nl+'    if (!GameReady_Install()) { PgrpTrace("ERROR GameReady_Install failed"); return 3; }'+$nl+'    PgrpTrace("07 GameReady_Install completed");')
Replace-Exact 'native/dllmain.cpp' '    D3D_Start();' ('    PgrpTrace("08 Starting D3D_Start");'+$nl+'    D3D_Start();'+$nl+'    PgrpTrace("09 D3D_Start completed - waiting for GTA game loop");')
$launcherTrace = @'
static void PgrpLaunchTrace(const char* message)
{
    HANDLE h = CreateFileW(L"PGRP_Launcher_Trace.log", FILE_APPEND_DATA,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD written = 0;
    WriteFile(h, message, static_cast<DWORD>(strlen(message)), &written, nullptr);
    const char newline[] = "\r\n";
    WriteFile(h, newline, 2, &written, nullptr);
    CloseHandle(h);
}
'@
Replace-Exact 'launcher/inject.h' 'inline int run_game()' ($launcherTrace+$nl+'inline int run_game()')
Replace-Exact 'launcher/inject.h' '        const std::wstring game_dir = get_exe_dir();' ('        const std::wstring game_dir = get_exe_dir();'+$nl+'        PgrpLaunchTrace("01 Launcher start; resolving game files");')
Replace-Exact 'launcher/inject.h' '        h_process = pi.hProcess;' ('        PgrpLaunchTrace("02 GTA CreateProcessW succeeded");'+$nl+'        h_process = pi.hProcess;')
Replace-Exact 'launcher/inject.h' '        wait_for_process_ready(pid, 15000);' ('        PgrpLaunchTrace("03 Waiting for GTA process readiness");'+$nl+'        wait_for_process_ready(pid, 15000);'+$nl+'        PgrpLaunchTrace("04 GTA process ready; preparing DLL injection");')
Replace-Exact 'launcher/inject.h' '            inject_dll_load_library_w(pid, dllPath.wstring());' ('        {'+$nl+'            PgrpLaunchTrace("05 Injecting Client.Native.dll via LoadLibraryW");'+$nl+'            inject_dll_load_library_w(pid, dllPath.wstring());'+$nl+'            PgrpLaunchTrace("06 DLL LoadLibraryW returned successfully");'+$nl+'        }')
Replace-Exact 'launcher/inject.h' '        if (WaitForSingleObject(h_process, 4000) == WAIT_OBJECT_0)' ('        PgrpLaunchTrace("07 Observing GTA process for four seconds");'+$nl+'        if (WaitForSingleObject(h_process, 4000) == WAIT_OBJECT_0)')
Write-Host 'PGRP launch/native tracing patch applied'

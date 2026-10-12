param([string]$Root="upstream")
$ErrorActionPreference="Stop"

function Patch([string]$rel,[string]$from,[string]$to) {
  $p=Join-Path $Root $rel
  $s=[IO.File]::ReadAllText((Resolve-Path $p).Path)
  $hits=([regex]::Matches($s,[regex]::Escape($from))).Count
  if($hits -ne 1) { throw "Unsafe patch for $rel expected 1 hit got $hits of: $from" }
  [IO.File]::WriteAllText($p,$s.Replace($from,$to),[Text.UTF8Encoding]::new($false))
  Write-Host "PATCH OK: $rel"
}

$launcherHelpers=@'
static void pgrp_startup_trace(const char* message)
{
    const HANDLE file = CreateFileA("PGRP_PC1_Startup.log", FILE_APPEND_DATA, FILE_SHARE_READ,
                                   nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    const std::string line = std::to_string(GetTickCount()) + " " + message + "\r\n";
    DWORD written = 0;
    WriteFile(file, line.c_str(), static_cast<DWORD>(line.size()), &written, nullptr);
    CloseHandle(file);
}

struct PgrpWindowProbe
{
    DWORD pid;
    bool found;
};

static BOOL CALLBACK pgrp_enum_gta_windows(HWND hwnd, LPARAM data)
{
    auto& state = *reinterpret_cast<PgrpWindowProbe*>(data);
    DWORD owner = 0;
    GetWindowThreadProcessId(hwnd, &owner);
    if (owner != state.pid || !IsWindowVisible(hwnd)) return TRUE;
    RECT client{};
    if (!GetClientRect(hwnd, &client)) return TRUE;
    if (client.right - client.left < 320 || client.bottom - client.top < 200) return TRUE;
    state.found = true;
    return FALSE;
}

static bool pgrp_wait_for_render_window(DWORD pid, HANDLE process, DWORD maxMilliseconds)
{
    const DWORD start = GetTickCount();
    while (GetTickCount() - start < maxMilliseconds)
    {
        if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
        {
            pgrp_startup_trace("ERROR game exited before render window was ready");
            throw std::runtime_error("GTA exited before showing a render window");
        }
        PgrpWindowProbe probe{pid, false};
        EnumWindows(pgrp_enum_gta_windows, reinterpret_cast<LPARAM>(&probe));
        if (probe.found)
        {
            pgrp_startup_trace("GTA render window visible; allowing 2000ms settle");
            Sleep(2000);
            if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
                throw std::runtime_error("GTA exited while stabilizing");
            return true;
        }
        Sleep(150);
    }
    pgrp_startup_trace("ERROR render window not visible before timeout; will not inject DLL");
    return false;
}

'@
Patch "launcher/inject.h" "static void try_kill_process(const HANDLE h_process)" ($launcherHelpers+"static void try_kill_process(const HANDLE h_process)")
Patch "launcher/inject.h" @'
    try
    {
        const std::wstring game_dir = get_exe_dir();
'@ @'
    try
    {
        pgrp_startup_trace("START v0.4.6 Win32 PC1 compatibility launcher");
        const std::wstring game_dir = get_exe_dir();
'@
Patch "launcher/inject.h" @'
        wait_for_process_ready(pid, 15000);

        for (const auto& dllPath : dlls)
            inject_dll_load_library_w(pid, dllPath.wstring());
'@ @'
        pgrp_startup_trace("CreateProcessW GTA pid acquired");
        wait_for_process_ready(pid, 15000);
        pgrp_startup_trace("GTA module enumeration ready");
        if (!pgrp_wait_for_render_window(pid, h_process, 30000))
            throw std::runtime_error("GTA window not ready in 30 seconds; injection not attempted");

        for (const auto& dllPath : dlls)
        {
            pgrp_startup_trace("Inject Client.Native.dll BEGIN");
            inject_dll_load_library_w(pid, dllPath.wstring());
            pgrp_startup_trace("Inject Client.Native.dll LoadLibraryW SUCCESS");
        }
'@
Patch "launcher/inject.h" @'
    catch (const std::exception& ex)
    {
        try_kill_process(h_process);
'@ @'
    catch (const std::exception& ex)
    {
        pgrp_startup_trace(ex.what());
        try_kill_process(h_process);
'@

$nativeTrace=@'
static void pgrp_native_trace(const char* message)
{
    const HANDLE file = CreateFileA("PGRP_Native_Startup.log", FILE_APPEND_DATA, FILE_SHARE_READ,
                                   nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    char line[320]{};
    sprintf_s(line, "%lu %s\r\n", GetTickCount(), message);
    DWORD written=0;
    WriteFile(file, line, static_cast<DWORD>(strlen(line)), &written, nullptr);
    CloseHandle(file);
}

'@
Patch "native/dllmain.cpp" "DWORD WINAPI MainThread(LPVOID)" ($nativeTrace+"DWORD WINAPI MainThread(LPVOID)")
Patch "native/dllmain.cpp" @'
    InstallCrashHandler();
    ApplyBaseMemoryPatches();
    MH_Initialize();
    GameReady_Install();
    D3D_Start();
    return 0;
'@ @'
    pgrp_native_trace("MainThread entered");
    InstallCrashHandler();
    pgrp_native_trace("Crash handler installed");
    ApplyBaseMemoryPatches();
    pgrp_native_trace("Memory patches complete");
    const auto mh = MH_Initialize();
    pgrp_native_trace(mh == MH_OK ? "MinHook initialized" : "ERROR MinHook initialization");
    if (mh != MH_OK) return 1;
    const bool ready = GameReady_Install();
    pgrp_native_trace(ready ? "GameReady hooks installed" : "ERROR GameReady hooks failed");
    if (!ready) return 2;
    D3D_Start();
    pgrp_native_trace("Direct3D hook thread started");
    return 0;
'@

$patchTrace=@'
static void pgrp_patch_trace(const char* stage)
{
    const HANDLE file = CreateFileA("PGRP_Native_Startup.log", FILE_APPEND_DATA, FILE_SHARE_READ,
                                   nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    char line[260]{};
    sprintf_s(line, "%lu PATCH %s\r\n", GetTickCount(), stage);
    DWORD written=0;
    WriteFile(file, line, static_cast<DWORD>(strlen(line)), &written, nullptr);
    CloseHandle(file);
}

'@
Patch "native/patches.cpp" "void ApplyBaseMemoryPatches()" ($patchTrace+"void ApplyBaseMemoryPatches()")
Patch "native/patches.cpp" @'
    LoadLegacyPatchLimit();
    ApplyLegacyBasePatches();
'@ @'
    pgrp_patch_trace("begin legacy");
    LoadLegacyPatchLimit();
    ApplyLegacyBasePatches();
    pgrp_patch_trace("legacy done");
'@
foreach($name in @('ApplyPoolLimits','ApplyCrashFixes','ApplyIntroSkipPatches','ApplyMultiplayerPatches','ApplyBehaviorPatches','ApplyFilesystemPatches','RelocatePedsListHack','RelocateScanListHack')) {
  $before='    '+$name+'();'
  $after='    pgrp_patch_trace("'+$name+' BEGIN");'+[Environment]::NewLine+$before+[Environment]::NewLine+'    pgrp_patch_trace("'+$name+' DONE");'
  Patch "native/patches.cpp" $before $after
}
Patch "native/dllmain.cpp" @'
        MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(),
                          hFile,
                          static_cast<MINIDUMP_TYPE>(
                              MiniDumpWithFullMemory |
                              MiniDumpWithIndirectlyReferencedMemory |
                              MiniDumpWithThreadInfo |
                              MiniDumpWithProcessThreadData),
                          &mei, nullptr, nullptr);
'@ @'
        MEMORYSTATUSEX mem{};
        mem.dwLength = sizeof(mem);
        const bool isLowMemory = GlobalMemoryStatusEx(&mem) &&
            (mem.ullAvailPhys < 1024ULL * 1024ULL * 1024ULL);
        const MINIDUMP_TYPE dumpType = isLowMemory
            ? MiniDumpWithThreadInfo
            : static_cast<MINIDUMP_TYPE>(
                  MiniDumpWithFullMemory |
                  MiniDumpWithIndirectlyReferencedMemory |
                  MiniDumpWithThreadInfo |
                  MiniDumpWithProcessThreadData);
        MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(),
                          hFile, dumpType, &mei, nullptr, nullptr);
'@
Write-Host 'PGRP PC1 v0.4.6 window-ready injection and stage trace patch applied.'

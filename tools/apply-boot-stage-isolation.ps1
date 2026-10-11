param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Replace-Exact([string]$p,[string]$a,[string]$b) {
 $f=(Resolve-Path (Join-Path $Root $p)).Path
 $s=[IO.File]::ReadAllText($f)
 $n=([regex]::Matches($s,[regex]::Escape($a))).Count
 if($n -ne 1) {throw "Patch mismatch in $p : $a; matches=$n"}
 [IO.File]::WriteAllText($f,$s.Replace($a,$b),[Text.UTF8Encoding]::new($false))
 Write-Host "PATCH OK: $p"
}
$nl=[Environment]::NewLine
$stage=@'
    char stageBuffer[16]{};
    const DWORD len = GetEnvironmentVariableA("PGRP_BOOT_STAGE",stageBuffer,sizeof(stageBuffer));
    const int stage = (len > 0 && len < sizeof(stageBuffer)) ? atoi(stageBuffer) : 3;
    if (stage == 0) {
        PgrpTrace("MODE 0: DLL loaded without memory patches or hooks");
        return 0;
    }
    PgrpTrace("MODE: memory patches enabled");
'@
Replace-Exact 'native/dllmain.cpp' '    PgrpTrace("03 Applying base memory patches");' ($stage+$nl+'    PgrpTrace("03 Applying base memory patches");')
Replace-Exact 'native/dllmain.cpp' '    PgrpTrace("04 Base memory patches completed");' ('    PgrpTrace("04 Base memory patches completed");'+$nl+'    if (stage == 1) { PgrpTrace("MODE 1: patches only, no hooks"); return 0; }')
Replace-Exact 'native/dllmain.cpp' '    PgrpTrace("07 GameReady_Install completed");' ('    PgrpTrace("07 GameReady_Install completed");'+$nl+'    if (stage == 2) { PgrpTrace("MODE 2: game hooks installed, no D3D"); return 0; }')
Replace-Exact 'native/dllmain.cpp' '#include <cstring>' ('#include <cstring>'+$nl+'#include <cstdlib>')
$check=@'
static DWORD PgrpExistingGamePid() {
    HANDLE h=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    if(h==INVALID_HANDLE_VALUE)return 0;
    PROCESSENTRY32W e{}; e.dwSize=sizeof(e);
    DWORD found=0;
    if(Process32FirstW(h,&e)) {
        do {
            if(lstrcmpiW(e.szExeFile,L"gta_sa.exe")==0) {
                found=e.th32ProcessID; break;
            }
        }while(Process32NextW(h,&e));
    }
    CloseHandle(h); return found;
}
'@
Replace-Exact 'launcher/inject.h' 'static void PgrpLaunchTrace(const char* message)' ($check+$nl+'static void PgrpLaunchTrace(const char* message)')
Replace-Exact 'launcher/inject.h' '        PgrpLaunchTrace("01 Launcher start; resolving game files");' ('        PgrpLaunchTrace("01 Launcher start; resolving game files");'+$nl+'        if (DWORD other=PgrpExistingGamePid())'+$nl+'            throw std::runtime_error("An existing gta_sa.exe is already running; PID: "+std::to_string(other)+". Close it in Task Manager, then retry PGRP.");'+$nl+'        PgrpLaunchTrace("01a No previous GTA process found");')

# Control experiment: launch GTA with CreateProcessW, but DO NOT load Client.Native.dll at all.
# This distinguishes a plain Windows process-launch problem from DLL injection or game hooks.
$skipInjection=@'
        char skipInjectionFlag[8]{};
        const DWORD skipLen = GetEnvironmentVariableA("PGRP_SKIP_INJECTION", skipInjectionFlag, sizeof(skipInjectionFlag));
        if (skipLen > 0 && skipLen < sizeof(skipInjectionFlag) && skipInjectionFlag[0] == '1')
        {
            PgrpLaunchTrace("CONTROL: no DLL injection requested; waiting four seconds");
            const DWORD result = WaitForSingleObject(h_process, 4000);
            if (result == WAIT_OBJECT_0)
            {
                DWORD exitCode = 0xFFFFFFFF;
                GetExitCodeProcess(h_process, &exitCode);
                PgrpLaunchTrace("CONTROL: GTA exited without any injected DLL");
                throw std::runtime_error(
                    "CONTROL TEST: gta_sa.exe exited without DLL injection. Exit code: " +
                    std::to_string(exitCode) + ". Investigate CreateProcess versus normal Explorer launch.");
            }
            if (result != WAIT_TIMEOUT)
                throw std::runtime_error("CONTROL TEST: WaitForSingleObject failed");
            PgrpLaunchTrace("CONTROL PASS: GTA alive after 4 seconds WITHOUT DLL injection");
            CloseHandle(h_process);
            h_process = nullptr;
            return 0;
        }
'@
Replace-Exact 'launcher/inject.h' '        PgrpLaunchTrace("04 GTA process ready; preparing DLL injection");' ('        PgrpLaunchTrace("04 GTA process ready; preparing DLL injection");'+$nl+$skipInjection)

# Passive DLL test: LoadLibrary succeeds but no initialization thread is started.
# This isolates remote LoadLibrary itself from OpenSAMP native startup work.
$passive=@'
    char passiveFlag[8]{};
    const DWORD passiveLen = GetEnvironmentVariableA("PGRP_DLL_PASSIVE", passiveFlag, sizeof(passiveFlag));
    if (passiveLen > 0 && passiveLen < sizeof(passiveFlag) && passiveFlag[0] == '1')
        return true;
'@
Replace-Exact 'native/dllmain.cpp' '    DisableThreadLibraryCalls(hModule);' ('    DisableThreadLibraryCalls(hModule);'+$nl+$passive)

# Delay injection until GTA has run on its own, avoiding the earliest process startup window.
$delayBlock=@'
        char delayBuffer[16]{};
        const DWORD delayLen = GetEnvironmentVariableA("PGRP_INJECT_DELAY_MS",delayBuffer,sizeof(delayBuffer));
        if (delayLen > 0 && delayLen < sizeof(delayBuffer))
        {
            const unsigned long delayMs = std::min(std::stoul(delayBuffer), 30000UL);
            if (delayMs > 0)
            {
                PgrpLaunchTrace("DELAY: waiting before Client.Native.dll injection");
                const DWORD waitResult = WaitForSingleObject(h_process, static_cast<DWORD>(delayMs));
                if (waitResult == WAIT_OBJECT_0)
                {
                    DWORD exitCode=0xFFFFFFFF;
                    GetExitCodeProcess(h_process,&exitCode);
                    throw std::runtime_error("GTA exited BEFORE delayed injection. Exit code="+std::to_string(exitCode));
                }
                if (waitResult != WAIT_TIMEOUT)
                    throw std::runtime_error("Delay wait failed before injection");
                PgrpLaunchTrace("DELAY: GTA survived; starting Client.Native.dll injection");
            }
        }
'@
Replace-Exact 'launcher/inject.h' '        for (const auto& dllPath : dlls)' ($delayBlock+$nl+'        for (const auto& dllPath : dlls)')
Replace-Exact 'launcher/inject.h' '            const DWORD result = WaitForSingleObject(h_process, 4000);' '            const DWORD result = WaitForSingleObject(h_process, 12000);'

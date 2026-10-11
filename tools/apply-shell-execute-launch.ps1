param([string]$Root = "upstream")
$ErrorActionPreference = "Stop"
function Patch-Once([string]$relative,[string]$before,[string]$after) {
  $full=(Resolve-Path -LiteralPath (Join-Path $Root $relative)).Path
  $s=[IO.File]::ReadAllText($full)
  $n=([regex]::Matches($s,[regex]::Escape($before))).Count
  if($n -ne 1){throw ("Expected exactly one match in " + $relative + "; count=" + $n)}
  [IO.File]::WriteAllText($full,$s.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host ("SHELL-LAUNCH PATCH OK: " + $relative)
}
$before=@'
        STARTUPINFOW si{};
        si.cb = sizeof(si);
        PROCESS_INFORMATION pi{};

        std::wstring cmd = L"\"" + exe_path.wstring() + L"\"";

        if (!CreateProcessW(
            exe_path.c_str(),
            cmd.data(),
            nullptr, nullptr,
            FALSE,
            0,
            nullptr,
            game_dir.c_str(),
            &si, &pi))
        {
            throw std::runtime_error("Failed to start gta_sa.exe");
        }
'@
$after=@'
        // Use the same Windows Shell launch path as double-clicking gta_sa.exe.
        // Raw CreateProcess bypasses ShellExecute app compatibility and elevation
        // handling; on the target PC standalone GTA works but raw launch exits 0.
        SHELLEXECUTEINFOW shellInfo{};
        shellInfo.cbSize = sizeof(shellInfo);
        shellInfo.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
        shellInfo.lpVerb = L"open";
        shellInfo.lpFile = exe_path.c_str();
        shellInfo.lpDirectory = game_dir.c_str();
        shellInfo.nShow = SW_SHOWNORMAL;
        if (!ShellExecuteExW(&shellInfo) || !shellInfo.hProcess)
        {
            const DWORD launchError = GetLastError();
            throw std::runtime_error(
                "ShellExecuteExW could not start GTA; GetLastError=" + std::to_string(launchError));
        }

        PROCESS_INFORMATION pi{};
        pi.hProcess = shellInfo.hProcess;
        pi.hThread = nullptr;
        pi.dwProcessId = GetProcessId(shellInfo.hProcess);
        if (!pi.dwProcessId)
        {
            CloseHandle(shellInfo.hProcess);
            throw std::runtime_error("ShellExecuteExW returned a process without a valid PID");
        }
'@
Patch-Once 'launcher/inject.h' $before $after
Patch-Once 'launcher/inject.h' '        CloseHandle(h_thread);' '        if (h_thread) CloseHandle(h_thread);'
Patch-Once 'launcher/inject.h' '#include <windows.h>' ("#include <windows.h>"+[Environment]::NewLine+"#include <shellapi.h>"+[Environment]::NewLine+'#pragma comment(lib, "shell32.lib")')
Patch-Once 'launcher/inject.h' '        PgrpLaunchTrace("02 GTA CreateProcessW succeeded");' '        PgrpLaunchTrace("02 GTA ShellExecuteExW succeeded");'
Write-Host 'Original GTA game files remain unchanged.'

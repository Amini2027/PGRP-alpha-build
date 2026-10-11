param(
    [Parameter(Mandatory=$false)][string]$Root = "upstream"
)
$ErrorActionPreference = 'Stop'
$changed = New-Object 'System.Collections.Generic.List[string]'

function Replace-Exact([string]$Relative, [string]$Before, [string]$After) {
    $path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing upstream source: $Relative"
    }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $source = [System.IO.File]::ReadAllText($resolved)
    $hits = ([regex]::Matches($source, [regex]::Escape($Before))).Count
    if ($hits -ne 1) {
        throw "Refusing unsafe upstream patch: $Relative; expected one match, found $hits; search: $Before"
    }
    $updated = $source.Replace($Before, $After)
    [System.IO.File]::WriteAllText($resolved, $updated, (New-Object System.Text.UTF8Encoding($false)))
    $script:changed.Add($Relative)
    Write-Host "PATCH OK $Relative : $Before"
}

# PGRP baseline-compatibility experiment:
# Temporarily retain upstream's original Direct3D / borderless settings.
# Earlier client entered the game with these settings; the alpha display override
# has not yet been proven compatible with the user's GTA install.
# Keep all UI identity and diagnostic fixes while isolating the rendering regression.

# Stable window ID and distinct IDs for both buttons, even when the server labels match.
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::Begin(title, nullptr, flags);' ('const std::string stableTitle = std::string(title) + "###pgrp_server_dialog";' + [Environment]::NewLine + '        ImGui::Begin(stableTitle.c_str(), nullptr, flags);')
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::Button(m_btn1.empty() ? "OK" : m_btn1.c_str(), ImVec2(btnW, 0))' 'ImGui::Button((std::string(m_btn1.empty() ? "OK" : m_btn1.c_str()) + "##pgrp_btn_primary").c_str(), ImVec2(btnW, 0))'
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::Button(m_btn2.c_str(), ImVec2(btnW, 0))' 'ImGui::Button((m_btn2 + "##pgrp_btn_secondary").c_str(), ImVec2(btnW, 0))'
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::SetNextWindowSize(ImVec2(kDialogWidth, 0.0f), ImGuiCond_Always);' 'ImGui::SetNextWindowSize(ImVec2(std::min(kDialogWidth, std::max(260.0f, io.DisplaySize.x - 32.0f)), 0.0f), ImGuiCond_Always);'

# Remove permanent debug overlay and repetitive synchronous SKY/STATE writes in the game render loop.
Replace-Exact 'native/gui/imgui_manager.cpp' '    draw_net_debug();' '    // PGRP alpha: debug net overlay disabled by default to avoid obscuring the game.'
Replace-Exact 'native/hooks.cpp' 'if ((g_totalFrames % 120) == 0)' 'if (false && (g_totalFrames % 120) == 0) // PGRP alpha: diagnostics available via //compat, not every frame'


# Keep a readable error whenever the launcher cannot start GTA or inject the client DLL.
# The upstream catch handler currently swallows ex.what(), masking the actual cause.
Replace-Exact 'launcher/inject.h' 'catch (const std::exception& /*ex*/)' 'catch (const std::exception& ex)'
$launcherErrorReporting = @'
        const std::string details =
            std::string("PGRP OpenSAMP launcher error: ") + ex.what() +
            "\r\n\r\nInstall Visual C++ 2015-2022 Redistributable (x86) if missing. Check Windows Security protection history for blocked files.";
        try
        {
            const fs::path logPath = fs::path(get_exe_dir()) / L"PGRP_Launcher_Error.txt";
            const HANDLE log = CreateFileW(logPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                                           nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (log != INVALID_HANDLE_VALUE)
            {
                DWORD written = 0;
                WriteFile(log, details.data(), static_cast<DWORD>(details.size()), &written, nullptr);
                CloseHandle(log);
            }
        }
        catch (...) { }
        MessageBoxA(
'@
Replace-Exact 'launcher/inject.h' '        MessageBoxW(' $launcherErrorReporting
Replace-Exact 'launcher/inject.h' 'L"Launcher error.\n\n(See logs / debug build for details.)"' 'details.c_str()'
Replace-Exact 'launcher/inject.h' 'L"Launcher error",' '"PGRP Launcher error",'

# Launcher should not report a successful start if gta_sa.exe disappears immediately.
$earlyGameExitCheck = @'
            inject_dll_load_library_w(pid, dllPath.wstring());

        if (WaitForSingleObject(h_process, 4000) == WAIT_OBJECT_0)
        {
            DWORD exitCode = 0;
            if (!GetExitCodeProcess(h_process, &exitCode)) exitCode = 0xFFFFFFFF;
            throw std::runtime_error(
                "gta_sa.exe exited within 4 seconds. Exit code: " + std::to_string(exitCode) +
                ". Check Windows Event Viewer > Application and PGRP_Launcher_Error.txt.");
        }
'@
Replace-Exact 'launcher/inject.h' '            inject_dll_load_library_w(pid, dllPath.wstring());' $earlyGameExitCheck

$unique = @($changed | Sort-Object -Unique)
Write-Host "Applied fixes to $($unique.Count) unique source files."

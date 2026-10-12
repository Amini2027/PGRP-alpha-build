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



# The server sends SA-MP {RRGGBB} markup in dialog titles and button labels.
# Those strings are identifiers/widgets in ImGui, not formatted message text.
# Strip markup for labels; preserve colored dialog body handled separately.
$stripColorHelper = @'
        std::string StripPgrpDialogColorTags(const char* source)
        {
            if (!source) return {};
            std::string clean;
            for (const char* p = source; *p;)
            {
                std::uint32_t rgba = 0;
                int tagLen = 0;
                if (*p == '{' && opensamp::gui::color::ParseHexTag(p, rgba, tagLen))
                {
                    p += tagLen;
                    continue;
                }
                clean.push_back(*p++);
            }
            return clean;
        }

'@
Replace-Exact 'native/gui/dialog.cpp' '        constexpr float kDialogWidth = 480.0f;' ('        constexpr float kDialogWidth = 480.0f;'+[Environment]::NewLine+[Environment]::NewLine+$stripColorHelper)
Replace-Exact 'native/gui/dialog.cpp' 'm_title = title ? title : "";' 'm_title = StripPgrpDialogColorTags(title);'
Replace-Exact 'native/gui/dialog.cpp' 'm_btn1  = btn1  ? btn1  : "";' 'm_btn1  = StripPgrpDialogColorTags(btn1);'
Replace-Exact 'native/gui/dialog.cpp' 'm_btn2  = btn2  ? btn2  : "";' 'm_btn2  = StripPgrpDialogColorTags(btn2);'

# PGRP client presentation fixes v0.4.3.
# Do not stretch GTA's HWND to the desktop until its native D3D backbuffer
# has been recreated at the same size. This was the source of the top-left
# game viewport, black rest of monitor and persistent UI / mouse drawings.
Replace-Exact 'native/d3d.cpp' 'static bool g_borderlessEnabled = true;' 'static bool g_borderlessEnabled = false;  // PGRP: preserve GTA-native fullscreen/window dimensions'
Replace-Exact 'native/d3d.cpp' 'static bool g_forceResEnabled = true;' 'static bool g_forceResEnabled = false;  // PGRP: do not force an unsynchronised D3D resize'

# Render ONLY one cursor: prefer the Win32 hardware cursor while a dialog/chat
# is active. Old implementation drew an additional ImGui software cursor
# onto an undersized, uncleared backbuffer, creating ghost/trail pointers.
$cursorHandling = @'
    const bool modal_active =
        g_chat.IsActive() || opensamp::gui::Dialog::Get().IsActive();
    ImGui::GetIO().MouseDrawCursor = false;

    static bool wasModal = false;
    static RECT previousClip{};
    static bool havePreviousClip = false;
    static int showCursorCalls = 0;

    if (modal_active && !wasModal)
    {
        havePreviousClip = (GetClipCursor(&previousClip) != FALSE);
        ClipCursor(nullptr);
        // Keep a balanced count: avoid leaving a visible OS cursor behind
        // after the player closes the dialog or the chat prompt.
        for (int i = 0; i < 16; ++i)
        {
            ++showCursorCalls;
            if (ShowCursor(TRUE) >= 0) break;
        }
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
    }
    else if (!modal_active && wasModal)
    {
        if (havePreviousClip) ClipCursor(&previousClip);
        while (showCursorCalls > 0)
        {
            ShowCursor(FALSE);
            --showCursorCalls;
        }
    }

    if (modal_active)
        SetCursor(LoadCursorW(nullptr, IDC_ARROW));
    wasModal = modal_active;
'@
$oldCursorHandling = @'
    const bool modal_active =
        g_chat.IsActive() || opensamp::gui::Dialog::Get().IsActive();
    ImGui::GetIO().MouseDrawCursor = modal_active;
'@
Replace-Exact 'native/gui/imgui_manager.cpp' $oldCursorHandling $cursorHandling

# Prevent GTA's WM_SETCURSOR from hiding/resetting the pointer while
# interacting with the modal. One Win32 cursor is used, not an ImGui sprite.
$cursorWndProc = @'
        if (dialog_active && msg == WM_SETCURSOR && LOWORD(lParam) == HTCLIENT)
        {
            SetCursor(LoadCursorW(nullptr, IDC_ARROW));
            return TRUE;
        }
'@
Replace-Exact 'native/gui/imgui_manager.cpp' '        const bool imgui_handled = ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam);' ($cursorWndProc+[Environment]::NewLine+'        const bool imgui_handled = ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam);')

# The ImGui dialog ID is stable and buttons have distinct hidden IDs (above).
# Also ensure submit's input text is not lost: ImGui InputText is already bound
# to its unique ##dlg_input slot and server responses use the same dialog id.
Write-Host 'PGRP client presentation fixes v0.4.3 applied'

$unique = @($changed | Sort-Object -Unique)
Write-Host "Applied fixes to $($unique.Count) unique source files."

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

# Do not stretch the desktop-sized borderless window over a differently-sized GTA backbuffer.
# Original GTA presentation mode stays in charge unless a proper coordinated Reset is implemented.
Replace-Exact 'native/d3d.cpp' 'static bool g_borderlessEnabled = true;' 'static bool g_borderlessEnabled = false; // PGRP alpha: do not force borderless'
Replace-Exact 'native/d3d.cpp' 'static bool g_forceResEnabled = true;' 'static bool g_forceResEnabled = false; // PGRP alpha: do not override GTA resolution'
Replace-Exact 'native/d3d.cpp' 'if (pp)' 'if (pp && g_forceResEnabled)'

# Stable window ID and distinct IDs for both buttons, even when the server labels match.
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::Begin(title, nullptr, flags);' ('const std::string stableTitle = std::string(title) + "###pgrp_server_dialog";' + [Environment]::NewLine + '        ImGui::Begin(stableTitle.c_str(), nullptr, flags);')
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::Button(m_btn1.empty() ? "OK" : m_btn1.c_str(), ImVec2(btnW, 0))' 'ImGui::Button((std::string(m_btn1.empty() ? "OK" : m_btn1.c_str()) + "##pgrp_btn_primary").c_str(), ImVec2(btnW, 0))'
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::Button(m_btn2.c_str(), ImVec2(btnW, 0))' 'ImGui::Button((m_btn2 + "##pgrp_btn_secondary").c_str(), ImVec2(btnW, 0))'
Replace-Exact 'native/gui/dialog.cpp' 'ImGui::SetNextWindowSize(ImVec2(kDialogWidth, 0.0f), ImGuiCond_Always);' 'ImGui::SetNextWindowSize(ImVec2(std::min(kDialogWidth, std::max(260.0f, io.DisplaySize.x - 32.0f)), 0.0f), ImGuiCond_Always);'

# Remove permanent debug overlay and repetitive synchronous SKY/STATE writes in the game render loop.
Replace-Exact 'native/gui/imgui_manager.cpp' '    draw_net_debug();' '    // PGRP alpha: debug net overlay disabled by default to avoid obscuring the game.'
Replace-Exact 'native/hooks.cpp' 'if ((g_totalFrames % 120) == 0)' 'if (false && (g_totalFrames % 120) == 0) // PGRP alpha: diagnostics available via //compat, not every frame'

$unique = @($changed | Sort-Object -Unique)
Write-Host "Applied fixes to $($unique.Count) unique source files."

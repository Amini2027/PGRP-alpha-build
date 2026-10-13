param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$relative,[string]$before,[string]$after,[string]$tag) {
    $p=(Resolve-Path -LiteralPath (Join-Path $Root $relative)).Path
    $source=[IO.File]::ReadAllText($p)
    $hits=([regex]::Matches($source,[regex]::Escape($before))).Count
    if($hits -ne 1) {throw "PGRP v0.5.4 $tag expected one match; got $hits"}
    [IO.File]::WriteAllText($p,$source.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PGRP v0.5.4 PATCH OK: $tag"
}
Patch 'native/sampraknet_bridge.h' @'
    bool IsPgrpAdminTabAllowed();
'@ @'
    bool IsPgrpAdminTabAllowed();
    // Hide the GTA bootstrap ped, sky-fall and early streaming transition
    // behind an inexpensive ImGui loading/auth scene until login spawn settles.
    bool IsPgrpGameplayReady();
'@ 'expose client world-ready state'
Patch 'native/sampraknet_bridge.cpp' @'
static bool g_pgrpReleasedSpectator = false;
'@ @'
static bool g_pgrpReleasedSpectator = false;
static DWORD g_pgrpSpawnVisualHoldMs = 0;
'@ 'visual fade timing state'
Patch 'native/sampraknet_bridge.cpp' @'
        g_pgrpReleasedSpectator = false;

        s_serverPassword[0] = 0;
'@ @'
        g_pgrpReleasedSpectator = false;
        g_pgrpSpawnVisualHoldMs = 0;

        s_serverPassword[0] = 0;
'@ 'reset on each connection'
Patch 'native/sampraknet_bridge.cpp' @'
            sampSpawn();
            iSpawned = 1;
            s_spawnStage = SpawnStage::Done;
'@ @'
            sampSpawn();
            iSpawned = 1;
            // Keep a lightweight login card on top while GTA streams the first
            // collision/buildings. Never expose a falling bootstrap ped.
            g_pgrpSpawnVisualHoldMs = GetTickCount();
            s_spawnStage = SpawnStage::Done;
'@ 'hold initial scene while map loads'
Patch 'native/sampraknet_bridge.cpp' @'
    bool IsPgrpAdminTabAllowed() { return g_pgrpEndpoint && g_pgrpAdminTabAllowed && iSpawned && !bIsSpectating; }
'@ @'
    bool IsPgrpAdminTabAllowed() { return g_pgrpEndpoint && g_pgrpAdminTabAllowed && iSpawned && !bIsSpectating; }
    bool IsPgrpGameplayReady() {
        if (!g_pgrpEndpoint) return true;
        if (!iSpawned || bIsSpectating || g_pgrpSpawnVisualHoldMs == 0) return false;
        return (GetTickCount() - g_pgrpSpawnVisualHoldMs) >= 1800;
    }
'@ 'server-authenticated visual-ready getter'
Patch 'native/gui/imgui_manager.cpp' '#include <imgui.h>' "#include <imgui.h>`n#include <cfloat>" 'include FLT_MAX safely'
Patch 'native/gui/imgui_manager.cpp' @'
    g_chat.Draw();
    opensamp::gui::Dialog::Get().Draw();
'@ @'
    // A game-integrated PGRP authentication/loading scene, not the old bare
    // sky/falling CJ world. This uses only ImGui's existing D3D9 draw list:
    // zero new textures, shader passes, browser engines or external assets.
    if (opensamp::bridge::IsPgrpEndpoint() &&
        !opensamp::bridge::IsPgrpGameplayReady()) {
        ImGuiIO& io = ImGui::GetIO();
        if (io.DisplaySize.x > 1.0f && io.DisplaySize.y > 1.0f) {
            ImDrawList* draw = ImGui::GetBackgroundDrawList();
            const float w=io.DisplaySize.x, h=io.DisplaySize.y;
            draw->AddRectFilled(ImVec2(0,0),ImVec2(w,h),IM_COL32(11,15,22,248));
            draw->AddRectFilledMultiColor(ImVec2(0,0),ImVec2(w,5),
                IM_COL32(227,177,93,255),IM_COL32(102,174,176,255),
                IM_COL32(102,174,176,255),IM_COL32(227,177,93,255));
            const float center=w*0.5f, top=h*0.16f;
            const float half=ImMin(320.0f,w*0.46f);
            draw->AddRect(ImVec2(center-half,top),ImVec2(center+half,top+h*0.65f),
                IM_COL32(173,132,69,115),14.0f,0,1.4f);
            draw->AddLine(ImVec2(center-half+24,top+87),
                          ImVec2(center+half-24,top+87),IM_COL32(223,181,105,130),1.0f);
            const char* brand="PALADIN GUARD";
            float titleSize=ImMin(30.0f,w/27.0f);
            ImFont* font=ImGui::GetFont();
            const ImVec2 size=font->CalcTextSizeA(titleSize,FLT_MAX,0.0f,brand);
            draw->AddText(font,titleSize,ImVec2(center-size.x*0.5f,top+27),
                IM_COL32(233,191,115,255),brand);
            const char* sub="ROLEPLAY  /  SECURE SESSION";
            const ImVec2 subSize=font->CalcTextSizeA(15.0f,FLT_MAX,0.0f,sub);
            draw->AddText(font,15.0f,ImVec2(center-subSize.x*0.5f,top+103),
                IM_COL32(200,209,220,245),sub);
            const char* status="PLEASE COMPLETE LOGIN / REGISTRATION";
            if (opensamp::bridge::IsGameInited())
                status="AUTHENTICATION OR WORLD STREAMING";
            const ImVec2 stSize=font->CalcTextSizeA(14.0f,FLT_MAX,0.0f,status);
            draw->AddText(font,14.0f,
                ImVec2(center-stSize.x*0.5f,top+h*0.55f),
                IM_COL32(198,211,220,255),status);
            // Real server dialog is rendered *after* the backdrop so input
            // remains interactive and no login info is spoofed client-side.
        }
    }

    g_chat.Draw();
    opensamp::gui::Dialog::Get().Draw();
'@ 'paint no-sky lightweight authentication screen'
Write-Host 'PGRP v0.5.4 in-game auth scene ready: no extra assets, server-authoritative spawn unchanged.'

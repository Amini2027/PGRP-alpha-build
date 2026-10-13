param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$p,[string]$a,[string]$b,[string]$tag) {
  $path=(Resolve-Path -LiteralPath (Join-Path $Root $p)).Path
  $src=[IO.File]::ReadAllText($path)
  $count=([regex]::Matches($src,[regex]::Escape($a))).Count
  if ($count -ne 1) { throw ("PGRP v0.5.1 patch '"+$tag+"' matched "+$count+" times") }
  [IO.File]::WriteAllText($path,$src.Replace($a,$b),[Text.UTF8Encoding]::new($false))
  Write-Host "PATCH OK $tag"
}
Patch 'native/gui/gui.h' 'void draw_ui();' @'
void draw_ui();
void ReleaseGameMovementKeys();
'@ 'shared movement release'
Patch 'native/gui/imgui_manager.cpp' 'LRESULT CALLBACK HookWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)' @'
static bool IsPgrpMovementKey(WPARAM key) {
    switch(key) {
    case 'W': case 'A': case 'S': case 'D':
    case VK_UP: case VK_DOWN: case VK_LEFT: case VK_RIGHT:
    case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT:
    case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL:
    case VK_SPACE: return true;
    default: return false;
    }
}
void ReleaseGameMovementKeys() {
    if (!g_hwnd || !g_orig_wnd_proc) return;
    const WPARAM keys[] = {'W','A','S','D',VK_UP,VK_DOWN,VK_LEFT,VK_RIGHT,
                           VK_SHIFT,VK_CONTROL,VK_SPACE};
    for(WPARAM key: keys)
        CallWindowProc(g_orig_wnd_proc,g_hwnd,WM_KEYUP,key,0xC0000001L);
    CallWindowProc(g_orig_wnd_proc,g_hwnd,WM_LBUTTONUP,0,0);
    CallWindowProc(g_orig_wnd_proc,g_hwnd,WM_RBUTTONUP,0,0);
}
LRESULT CALLBACK HookWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
'@ 'clear held controls'
Patch 'native/gui/imgui_manager.cpp' @'
        if (opensamp::bridge::IsPgrpEndpoint() &&
            (msg == WM_KEYDOWN || msg == WM_KEYUP) && wParam == VK_TAB &&
            !dialog_active && !g_chat.IsActive())
        {
            if (msg == WM_KEYDOWN && (lParam & (1u << 30)) == 0 &&
                opensamp::bridge::IsPgrpAdminTabAllowed())
            {
                opensamp::bridge::SendCommand("/players");
            }
            return 0;
        }
'@ @'
        // TAB toggles only the administrator list (server dialog id 104).
        // Repeated key-down while TAB is held is intentionally ignored.
        if (opensamp::bridge::IsPgrpEndpoint() &&
            (msg == WM_KEYDOWN || msg == WM_KEYUP) && wParam == VK_TAB &&
            !g_chat.IsModal()) {
            if (msg == WM_KEYDOWN && (lParam & (1u << 30)) == 0 &&
                opensamp::bridge::IsPgrpAdminTabAllowed()) {
                auto& dlg=opensamp::gui::Dialog::Get();
                if (dlg.IsActive() && dlg.Id() == 104)
                    dlg.Cancel();
                else if (!dlg.IsActive()) {
                    ReleaseGameMovementKeys();
                    opensamp::bridge::SendCommand("/players");
                }
            }
            return 0;
        }
'@ 'TAB true open/close'
Patch 'native/gui/imgui_manager.cpp' @'
        if (msg == WM_KEYDOWN)
        {
            // Toggle chat with T
'@ @'
        if (msg == WM_KEYDOWN && wParam == VK_F7 &&
            (lParam & (1u << 30)) == 0 && !dialog_active) {
            if (!g_chat.IsActive()) {
                const bool open = !g_chat.IsHistoryOpen();
                if (open) ReleaseGameMovementKeys();
                g_chat.SetHistoryOpen(open);
            }
            return 0;
        }
        if (msg == WM_KEYDOWN && wParam == VK_ESCAPE && g_chat.IsHistoryOpen()) {
            g_chat.SetHistoryOpen(false);
            return 0;
        }
        if (msg == WM_KEYDOWN)
        {
            // Toggle chat with T
'@ 'F7 scrollable chat history'
Patch 'native/gui/imgui_manager.cpp' @'
                g_chat.SetActive(true);
                g_chat.RequestFocus();
'@ @'
                ReleaseGameMovementKeys();
                g_chat.SetHistoryOpen(false);
                g_chat.SetActive(true);
                g_chat.RequestFocus();
'@ 'chat opens safely'
Patch 'native/gui/imgui_manager.cpp' @'
        if (g_chat.IsActive() || dialog_active)
        {
            switch (msg)
'@ @'
        if (g_chat.IsModal() || dialog_active)
        {
            // Always pass KEYUP to GTA, never forward movement KEYDOWN.
            if (msg == WM_KEYUP && IsPgrpMovementKey(wParam))
                return CallWindowProc(g_orig_wnd_proc,hWnd,msg,wParam,lParam);
            switch (msg)
'@ 'prevent stuck movement'
Patch 'native/gui/imgui_manager.cpp' @'
            // Dialogs take mouse too — block game camera/fire.
            if (dialog_active && msg >= WM_MOUSEFIRST && msg <= WM_MOUSELAST)
'@ @'
            // Chat wheel/history/dialog input is exclusively routed to ImGui.
            if (msg >= WM_MOUSEFIRST && msg <= WM_MOUSELAST)
'@ 'route chat wheel'
Patch 'native/gui/imgui_manager.cpp' @'
        g_chat.IsActive() || opensamp::gui::Dialog::Get().IsActive();
'@ @'
        g_chat.IsModal() || opensamp::gui::Dialog::Get().IsActive();
'@ 'cursor visibility'
Patch 'native/input_guard.cpp' 'return opensamp::gui::Dialog::Get().IsActive() || g_chat.IsActive();' 'return opensamp::gui::Dialog::Get().IsActive() || g_chat.IsModal();' 'block gameplay input during history'
Patch 'native/gui/dialog.hpp' 'bool IsActive() const { return m_active; }' @'
        bool IsActive() const { return m_active; }
        std::uint16_t Id() const { return m_id; }
        void Cancel();
'@ 'admin dialog controls'
Patch 'native/gui/dialog.cpp' @'
    void Dialog::Hide()
    {
        m_active = false;
    }
'@ @'
    void Dialog::Hide()
    {
        m_active = false;
    }
    void Dialog::Cancel()
    {
        if (m_active) Respond(0);
    }
'@ 'cancel with server response'
Patch 'native/gui/dialog.cpp' @'
        m_active    = true;
'@ @'
        m_active    = true;
        ReleaseGameMovementKeys();
'@ 'release movement on any dialog'
Patch 'native/gui/dialog.cpp' '#include "colored_text.h"' @'
#include "colored_text.h"
// Forward declaration avoids Windows.h min/max macro pollution in this UI file.
void ReleaseGameMovementKeys();
'@ 'dialog release declaration'
Patch 'native/gui/chat.hpp' 'bool IsActive() const { return m_active; }' @'
    bool IsActive() const { return m_active; }
    bool IsHistoryOpen() const { return m_historyOpen; }
    bool IsModal() const { return m_active || m_historyOpen; }
    void SetHistoryOpen(bool value) { m_historyOpen=value; m_scrollToBottom=true; }
'@ 'chat history controls'
Patch 'native/gui/chat.hpp' 'bool m_active = false;' @'
    bool m_active = false;
    bool m_historyOpen = false;
'@ 'chat history state'
Patch 'native/gui/chat.cpp' @'
            for (auto& s : m_pending)
                m_lines.push_back(ChatLine{.textUtf8 = std::move(s), .tMs = NowMs()});
            m_pending.clear();
            m_scrollToBottom = true;
'@ @'
            for (auto& s : m_pending)
                m_lines.push_back(ChatLine{.textUtf8 = std::move(s), .tMs = NowMs()});
            m_pending.clear();
            while (m_lines.size() > m_maxLines) m_lines.pop_front();
            if (!IsModal()) m_scrollToBottom=true;
'@ 'bounded 200-line log'
Patch 'native/gui/chat.cpp' '    if (!m_active) flags |= ImGuiWindowFlags_NoInputs;' '    if (!IsModal()) flags |= ImGuiWindowFlags_NoInputs;' 'interactive chat scroll'
Patch 'native/gui/chat.cpp' '    ImGui::BeginChild("##chat_lines", ImVec2(0, -input_h), false);' @'
    ImGui::BeginChild("##chat_lines", ImVec2(0, -input_h), false,
        IsModal() ? ImGuiWindowFlags_AlwaysVerticalScrollbar :
                    (ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse));
'@ 'mouse scrolling'
Patch 'native/gui/chat.cpp' @'
    idx.reserve(static_cast<size_t>(linesToShow));

    for (int i = static_cast<int>(lines.size()) - 1; i >= 0 && std::cmp_less(idx.size(), linesToShow); --i)
'@ @'
    const int renderCount = IsModal() ? static_cast<int>(lines.size()) : linesToShow;
    idx.reserve(static_cast<size_t>(renderCount));

    for (int i = static_cast<int>(lines.size()) - 1; i >= 0 && std::cmp_less(idx.size(), renderCount); --i)
'@ 'render 200 historical messages'
Patch 'native/gui/chat.cpp' @'
    if (ImGui::GetScrollY() >= ImGui::GetScrollMaxY())
        m_scrollToBottom = true;

    if (m_scrollToBottom)
        ImGui::SetScrollHereY(1.0f);
'@ @'
    if (IsModal() && ImGui::IsWindowHovered(ImGuiHoveredFlags_AllowWhenBlockedByActiveItem) &&
        ImGui::GetIO().MouseWheel > 0.0f)
        m_scrollToBottom=false;
    else if (ImGui::GetScrollY() >= ImGui::GetScrollMaxY() - 2.0f)
        m_scrollToBottom=true;
    if (m_scrollToBottom)
        ImGui::SetScrollHereY(1.0f);
'@ 'preserve manual scroll position'
Patch 'native/sampraknet_bridge.cpp' @'
    const bool isEngineDiagnostic =
        std::strncmp(buffer, "[WorldTime]", 11) == 0 ||
        std::strncmp(buffer, "[Weather]", 9) == 0 ||
        std::strncmp(buffer, "[TEXTDRAW:EDIT]", 15) == 0 ||
        std::strncmp(buffer, "[Camera]", 8) == 0;
    if (!isEngineDiagnostic)
        g_chat.PushLineAsync(buffer);
'@ @'
    // Internal Log() messages go to OpenSamp.log only.
'@ 'stop diagnostic flood to chat'
Patch 'native/sampraknet_bridge.cpp' @'
    Log("%s", utf8.c_str());
}

void Chat(RPCParameters* rpcParams)
'@ @'
    g_chat.PushLineAsync(utf8);
    Log("[SERVER] %s", utf8.c_str());
}

void Chat(RPCParameters* rpcParams)
'@ 'keep actual server chat'
Patch 'native/sampraknet_bridge.cpp' '    Log("[CHAT] %s: %s", playerInfo[playerId].szPlayerName, utf8.c_str());' @'
    g_chat.PushLineAsync(std::string(playerInfo[playerId].szPlayerName) + ": " + utf8);
    Log("[CHAT] %s: %s", playerInfo[playerId].szPlayerName, utf8.c_str());
'@ 'keep player chat'
Patch 'native/gui/imgui_manager.cpp' '    ImGui::StyleColorsDark();' @'
    ImGui::StyleColorsDark();
    // PGRP lightweight black/gold interface, no blur, textures or shaders.
    auto& style=ImGui::GetStyle();
    style.WindowRounding=8.0f;
    style.ChildRounding=5.0f;
    style.FrameRounding=5.0f;
    style.ScrollbarRounding=4.0f;
    style.WindowBorderSize=1.0f;
    style.Colors[ImGuiCol_WindowBg]=ImVec4(0.055f,0.065f,0.079f,0.94f);
    style.Colors[ImGuiCol_ChildBg]=ImVec4(0.072f,0.082f,0.095f,0.75f);
    style.Colors[ImGuiCol_Border]=ImVec4(0.65f,0.49f,0.22f,0.58f);
    style.Colors[ImGuiCol_Button]=ImVec4(0.47f,0.31f,0.10f,0.97f);
    style.Colors[ImGuiCol_ButtonHovered]=ImVec4(0.72f,0.51f,0.19f,1.0f);
    style.Colors[ImGuiCol_ButtonActive]=ImVec4(0.62f,0.42f,0.13f,1.0f);
    style.Colors[ImGuiCol_Header]=ImVec4(0.43f,0.31f,0.14f,0.65f);
    style.Colors[ImGuiCol_HeaderHovered]=ImVec4(0.64f,0.47f,0.19f,0.86f);
    style.Colors[ImGuiCol_ScrollbarGrab]=ImVec4(0.55f,0.40f,0.17f,0.8f);
'@ 'design system v1'
Patch 'native/gui/dialog.cpp' '        ImGui::Begin(stableTitle.c_str(), nullptr, flags);' @'
        ImGui::Begin(stableTitle.c_str(), nullptr, flags);
        ImGui::TextColored(ImVec4(0.83f,0.65f,0.29f,1.0f),
                           "PGRP  /  PALADIN GUARD ROLEPLAY");
        ImGui::Separator();
'@ 'branded dialogs'
Patch 'native/gui/chat.cpp' '    ImGui::Begin("##samp_chat", nullptr, flags);' @'
    ImGui::Begin("##samp_chat", nullptr, flags);
    if (IsModal()) {
        ImGui::TextColored(ImVec4(0.83f,0.65f,0.29f,1.0f),
            m_historyOpen ? "PGRP / CHAT HISTORY  [F7: CLOSE]" :
                            "PGRP / CHAT  [ENTER: SEND]");
        ImGui::Separator();
    }
'@ 'branded chat'
Write-Host 'PGRP v0.5.1 client: TAB toggles, stuck keys released, chat wheel/history, no log spam, lightweight styling.'

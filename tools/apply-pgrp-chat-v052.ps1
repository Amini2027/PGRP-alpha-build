param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Replace-One([string]$relative,[string]$before,[string]$after,[string]$label) {
    $p=(Resolve-Path -LiteralPath (Join-Path $Root $relative)).Path
    $src=[IO.File]::ReadAllText($p)
    $count=([regex]::Matches($src,[regex]::Escape($before))).Count
    if($count -ne 1) { throw "PGRP v0.5.2 $label requires exactly one match; found $count" }
    [IO.File]::WriteAllText($p,$src.Replace($before,$after),[Text.UTF8Encoding]::new($false))
    Write-Host "PATCH OK: $label"
}
# The v0.5.1 global charcoal theme made every ImGui child non-transparent.
# Even though the chat window itself was transparent, ##chat_lines painted a
# full dark rectangle during normal gameplay. Override ChildBg locally.
Replace-One 'native/gui/chat.cpp' @'
    ImGui::PushStyleColor(ImGuiCol_WindowBg, IM_COL32(0, 0, 0, m_active ? 120 : 0));

    ImGui::Begin("##samp_chat", nullptr, flags);
'@ @'
    // Gameplay chat stays completely transparent. Only active input/history
    // has a contained charcoal background; no permanent dark screen block.
    ImGui::PushStyleColor(ImGuiCol_WindowBg, IM_COL32(0, 0, 0, IsModal() ? 155 : 0));
    ImGui::PushStyleColor(ImGuiCol_ChildBg, IM_COL32(0, 0, 0, IsModal() ? 145 : 0));

    ImGui::Begin("##samp_chat", nullptr, flags);
'@ 'transparent idle chat child'
Replace-One 'native/gui/chat.cpp' @'
    ImGui::PopStyleColor();
    ImGui::PopStyleVar(3);
'@ @'
    ImGui::PopStyleColor(2);
    ImGui::PopStyleVar(3);
'@ 'balanced ImGui style stack'
Replace-One 'native/gui/chat.cpp' @'
    const float height = lineH * static_cast<float>(m_visibleLines) + lineH * 2.2f;
'@ @'
    const float height = lineH * static_cast<float>(IsModal() ? m_visibleLines : 5) + lineH * 2.2f;
'@ 'compact in-game chat footprint'
Replace-One 'native/gui/chat.cpp' @'
    const int renderCount = IsModal() ? static_cast<int>(lines.size()) : linesToShow;
'@ @'
    const int renderCount = IsModal() ? static_cast<int>(lines.size()) : (linesToShow < 5 ? linesToShow : 5);
'@ 'max five live chat entries'
Replace-One 'native/gui/chat.cpp' @'
        DrawLineColored(lines[i].textUtf8, 1.0f);
'@ @'
        // Passive chat displays recent messages briefly; full retained history
        // remains accessible via F7 (no data discarded from the 200-line log).
        const uint64_t age = NowMs() - lines[i].tMs;
        if (!IsModal() && age >= 11000) continue;
        const float opacity = IsModal() || age < 8000 ? 1.0f :
            1.0f - static_cast<float>(age - 8000) / 3000.0f;
        DrawLineColored(lines[i].textUtf8, opacity);
'@ 'fade old messages in gameplay'
# Earlier v0.5.1 suppressed bridge diagnostics but netgame.cpp still directly
# enqueued all [NetGame] connection transitions into the public chat HUD.
# Send them to the existing global logger (OpenSamp.log) instead.
Replace-One 'native/net/netgame.cpp' @'
#include "../sampraknet_bridge.h"
#include "../gui/chat.hpp"
'@ @'
#include "../sampraknet_bridge.h"
#include "../gui/chat.hpp"

// Persistent disk logger in sampraknet_bridge.cpp; no public chat side effect.
extern void Log(const char* format, ...);
'@ 'netgame disk logger declaration'
Replace-One 'native/net/netgame.cpp' @'
            g_chat.PushLineAsync(buf);
'@ @'
            ::Log("%s", buf);
'@ 'netgame diagnostic routing'
# Optional automatic server join. Absence of this environment variable keeps
# the manual //connect behavior of the known-working client.
Replace-One 'native/net/netgame.cpp' @'
        m_initialized = true;
        m_state = NetState::None;
        m_stateEnterMs = NowMs();
'@ @'
        m_initialized = true;
        m_state = NetState::None;
        m_stateEnterMs = NowMs();

        // A PGRP launcher may opt into auto-connect. Reject malformed nicknames
        // rather than passing unchecked input into the legacy RakNet bridge.
        // Environment is read only once at process startup (no secrets stored).
        char nick[25]{};
        const DWORD nickLen = GetEnvironmentVariableA("PGRP_AUTOCONNECT_NICK",nick,sizeof(nick));
        if (nickLen >= 3 && nickLen <= 24) {
            bool valid=true;
            bool underscore=false;
            for (DWORD i=0;i<nickLen;++i) {
                const unsigned char c=static_cast<unsigned char>(nick[i]);
                if (c == '_') underscore=true;
                if (!((c>='A' && c<='Z') || (c>='a' && c<='z') ||
                      (c>='0' && c<='9') || c=='_')) {valid=false;break;}
            }
            if (valid && underscore) {
                ServerAddress addr{};
                addr.host="46.38.138.33";
                addr.port=7777;
                LocalInfo user{};
                user.nickname=nick;
                Log("[PGRP Launcher] Starting authorized auto-connect");
                Connect(std::move(addr),std::move(user));
            } else {
                Log("[PGRP Launcher] Ignoring invalid auto-connect nickname");
            }
        }
'@ 'opt-in auto-connect'
Write-Host 'PGRP v0.5.2: background-free chat; bounded HUD; disk-only diagnostics; opt-in launcher join.'

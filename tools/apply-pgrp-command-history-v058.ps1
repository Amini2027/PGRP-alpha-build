param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Replace-Exact([string]$file,[string]$before,[string]$after,[string]$label){
  $p=(Resolve-Path -LiteralPath (Join-Path $Root $file)).Path
  $src=[IO.File]::ReadAllText($p)
  $n=([regex]::Matches($src,[regex]::Escape($before))).Count
  if($n -ne 1){throw ("v058 history "+$label+": expected 1 anchor, found "+$n)}
  [IO.File]::WriteAllText($p,$src.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PGRP v058 CHAT OK: $label"
}
Replace-Exact 'native/gui/chat.cpp' @'
#include <utility>
'@ @'
#include <utility>
#include <deque>
'@ 'command history container'
Replace-Exact 'native/gui/chat.cpp' @'
namespace
{
    std::vector<std::string> SplitWhitespace(std::string_view s)
'@ @'
namespace
{
    // Only commands are retained. Bounded to 48 entries in memory,
    // never persisted to disk (commands may contain sensitive arguments).
    std::deque<std::string> g_history;
    int g_historyIndex = -1;
    std::string g_historyDraft;
    static int PgrpHistoryCallback(ImGuiInputTextCallbackData* data)
    {
        if(data->EventFlag != ImGuiInputTextFlags_CallbackHistory) return 0;
        if(g_history.empty()) return 0;
        if(data->EventKey == ImGuiKey_UpArrow)
        {
            if(g_historyIndex < 0) g_historyDraft.assign(data->Buf,data->BufTextLen);
            if(g_historyIndex+1 < static_cast<int>(g_history.size()))
                ++g_historyIndex;
        }
        else if(data->EventKey == ImGuiKey_DownArrow)
        {
            if(g_historyIndex>=0) --g_historyIndex;
        }
        else return 0;
        const std::string& selected = (g_historyIndex<0)
            ? g_historyDraft : g_history[static_cast<size_t>(g_historyIndex)];
        data->DeleteChars(0,data->BufTextLen);
        data->InsertChars(0,selected.c_str());
        return 0;
    }
    std::vector<std::string> SplitWhitespace(std::string_view s)
'@ 'up/down history with draft restoration'
Replace-Exact 'native/gui/chat.cpp' @'
        if (ImGui::InputText("##chat_input", m_input, sizeof(m_input),
                             ImGuiInputTextFlags_EnterReturnsTrue))
'@ @'
        if (ImGui::InputText("##chat_input", m_input, sizeof(m_input),
                             ImGuiInputTextFlags_EnterReturnsTrue |
                             ImGuiInputTextFlags_CallbackHistory,
                             PgrpHistoryCallback))
'@ 'ImGui editable command recall'
Replace-Exact 'native/gui/chat.cpp' @'
                if (!cmd.empty())
                {
                    RouteInput(cmd);
                }

                g_chat.SetActive(false);
'@ @'
                if (!cmd.empty())
                {
                    if(cmd[0]=='/')
                    {
                        if(g_history.empty() || g_history.front()!=cmd)
                            g_history.push_front(cmd);
                        if(g_history.size()>48) g_history.pop_back();
                    }
                    RouteInput(cmd);
                }
                g_historyIndex=-1;
                g_historyDraft.clear();
                g_chat.SetActive(false);
'@ 'bounded command storage after submit'
Write-Host 'PGRP v058 arrow keys navigate the latest commands; down restores the typed draft.'

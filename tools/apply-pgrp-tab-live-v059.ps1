param([string]$Root='upstream')
$ErrorActionPreference='Stop'
function Patch([string]$relative,[string]$before,[string]$after,[string]$tag){
 $p=(Resolve-Path -LiteralPath (Join-Path $Root $relative)).Path
 $src=[IO.File]::ReadAllText($p)
 $n=([regex]::Matches($src,[regex]::Escape($before))).Count
 if($n -ne 1){throw ("PGRP TAB v059 "+$tag+" expected 1 anchor, found "+$n)}
 [IO.File]::WriteAllText($p,$src.Replace($before,$after),[Text.UTF8Encoding]::new($false))
 Write-Host ("PGRP v059 PATCH OK "+$tag)
}
Patch 'native/sampraknet_bridge.cpp' @'
#include "sampraknet_bridge.h"
'@ @'
#include "sampraknet_bridge.h"
#include <imgui.h>
#include <string>
#include <cstdio>
'@ 'include ImGui native admin overlay'
Patch 'native/sampraknet_bridge.h' @'
    bool IsPgrpAdminTabAllowed();
'@ @'
    bool IsPgrpAdminTabAllowed();
    void PgrpTabToggle();
    void PgrpTabClear();
    void PgrpTabAdd(int id,int ping,const char* name);
    void PgrpTabDraw();
'@ 'public admin tab UI protocol'
Patch 'native/sampraknet_bridge.cpp' @'
static bool g_pgrpServerWorldReady = false;
'@ @'
static bool g_pgrpServerWorldReady = false;
struct PgrpTabRecord {int rpId=0;int ping=0;std::string name;};
static std::vector<PgrpTabRecord> g_pgrpTabRows;
static bool g_pgrpTabVisible=false;
'@ 'UI state independent of dialog'
Patch 'native/sampraknet_bridge.cpp' @'
    // This private control message comes from the authenticated SA-MP server,
'@ @'
    // Native TAB packets update rows without ShowPlayerDialog, so closing
    // the overlay never causes the server's ping refresh to reopen a dialog.
    if(g_pgrpEndpoint && g_pgrpAdminTabAllowed)
    {
        if(std::strcmp(szMsg,"PGRP_TAB_CLEAR")==0)
        {
            opensamp::bridge::PgrpTabClear();
            return;
        }
        int rp=0,ping=0;char name[25]{};
        if(std::sscanf(szMsg,"PGRP_TAB_ROW:%d:%d:%24s",&rp,&ping,name)==3)
        {
            opensamp::bridge::PgrpTabAdd(rp,ping,name);
            return;
        }
    }
    // This private control message comes from the authenticated SA-MP server,
'@ 'consume live ping packets (no chat noise)'
Patch 'native/sampraknet_bridge.cpp' @'
    bool IsPgrpGameplayReady() {
'@ @'
    void PgrpTabToggle()
    {
        if(!IsPgrpAdminTabAllowed()){g_pgrpTabVisible=false;return;}
        g_pgrpTabVisible=!g_pgrpTabVisible;
        g_pgrpTabRows.clear();
        SendCommand(g_pgrpTabVisible?"/players":"/closetab");
    }
    void PgrpTabClear()
    {
        if(g_pgrpTabVisible && IsPgrpAdminTabAllowed()) g_pgrpTabRows.clear();
    }
    void PgrpTabAdd(int id,int ping,const char* name)
    {
        if(!g_pgrpTabVisible || !IsPgrpAdminTabAllowed() || !name ||
           id<=0 || id>999999 || ping<0 || ping>99999 ||
           g_pgrpTabRows.size()>=100) return;
        g_pgrpTabRows.push_back({id,ping,std::string(name)});
    }
    void PgrpTabDraw()
    {
        if(!g_pgrpTabVisible || !IsPgrpAdminTabAllowed()) return;
        const ImGuiIO& io=ImGui::GetIO();
        const float w=(std::min)(600.f,(std::max)(320.f,io.DisplaySize.x-40.f));
        const float h=(std::min)(530.f,(std::max)(200.f,io.DisplaySize.y-80.f));
        ImGui::SetNextWindowPos(ImVec2((io.DisplaySize.x-w)*.5f,55.f),ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImVec2(w,h),ImGuiCond_Always);
        ImGui::PushStyleColor(ImGuiCol_WindowBg,IM_COL32(13,19,30,232));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding,9.f);
        ImGuiWindowFlags flags=ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoMove|
            ImGuiWindowFlags_NoSavedSettings|ImGuiWindowFlags_NoCollapse|
            ImGuiWindowFlags_NoFocusOnAppearing|ImGuiWindowFlags_NoInputs;
        if(ImGui::Begin("Paladin Guard Roleplay | Admin Players",nullptr,flags))
        {
            ImGui::TextUnformatted("ADMIN PLAYER LIST  |  TAB to close");
            ImGui::Text("Online: %u  |  Live ping refresh: 2 sec",
                static_cast<unsigned>(g_pgrpTabRows.size()));
            ImGui::Separator();
            ImGui::BeginChild("##pgplayers",ImVec2(0,-1),false);
            ImGui::Columns(3,"##pgrpcols",true);
            ImGui::TextUnformatted("RP ID");ImGui::NextColumn();
            ImGui::TextUnformatted("Player");ImGui::NextColumn();
            ImGui::TextUnformatted("Ping (ms)");ImGui::NextColumn();
            ImGui::Separator();
            for(const auto& row:g_pgrpTabRows)
            {
                ImGui::Text("%d",row.rpId);ImGui::NextColumn();
                ImGui::TextUnformatted(row.name.c_str());ImGui::NextColumn();
                ImGui::Text("%d",row.ping);ImGui::NextColumn();
            }
            ImGui::Columns(1);
            ImGui::EndChild();
        }
        ImGui::End();
        ImGui::PopStyleVar();
        ImGui::PopStyleColor();
    }
    bool IsPgrpGameplayReady() {
'@ 'native read-only live admin scoreboard'
Patch 'native/gui/imgui_manager.cpp' @'
                opensamp::bridge::SendCommand("/players");
'@ @'
                opensamp::bridge::PgrpTabToggle();
'@ 'TAB toggles local overlay (no repeated dialog)'
Patch 'native/gui/imgui_manager.cpp' @'
    g_chat.Draw();
    opensamp::gui::Dialog::Get().Draw();
'@ @'
    g_chat.Draw();
    opensamp::gui::Dialog::Get().Draw();
    opensamp::bridge::PgrpTabDraw();
'@ 'draw player list every game frame while open'
Write-Host "PGRP admin TAB is now client-rendered, server only updates row snapshots."

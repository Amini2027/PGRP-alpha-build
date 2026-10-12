param([string]$Root='upstream')
$ErrorActionPreference = 'Stop'
function PatchOne([string]$relative,[string]$before,[string]$after,[string]$tag) {
  $file=(Resolve-Path -LiteralPath (Join-Path $Root $relative)).Path
  $src=[IO.File]::ReadAllText($file)
  $found=([regex]::Matches($src,[regex]::Escape($before))).Count
  if($found -ne 1) {throw "PGRP spawn/TAB $tag patch refused; matches=$found"}
  [IO.File]::WriteAllText($file,$src.Replace($before,$after),[Text.UTF8Encoding]::new($false))
  Write-Host "PATCH OK $tag : $relative"
}

# Standard open.mp servers preserve their existing spawn FSM.
# PGRP requires authentication before any client Spawn RPC.
PatchOne 'native/sampraknet_bridge.cpp' 'int g_myPlayerID = -1;' @'
int g_myPlayerID = -1;
// PGRP server-side auth is the only authority for releasing a player from spectator mode.
static bool g_pgrpEndpoint = false;
static bool g_pgrpAdminTabAllowed = false;
static bool g_pgrpSpawnInfoReady = false;
static bool g_pgrpReleasedSpectator = false;
'@ 'PGRP state'

PatchOne 'native/sampraknet_bridge.cpp' @'
    bsData.Read((PCHAR)&SpawnInfo, sizeof(PLAYER_SPAWN_INFO));

    fNormalModePos[0] = SpawnInfo.vecPos[0];
'@ @'
    if (!bsData.Read((PCHAR)&SpawnInfo, sizeof(PLAYER_SPAWN_INFO)))
    {
        Log("[PGRP Spawn] SetSpawnInfo payload too short; will not spawn");
        return;
    }
    if (g_pgrpEndpoint)
    {
        g_pgrpSpawnInfoReady = true;
        Log("[PGRP Spawn] Server info pos=(%.3f,%.3f,%.3f) angle=%.1f",
            SpawnInfo.vecPos[0], SpawnInfo.vecPos[1], SpawnInfo.vecPos[2], SpawnInfo.fRotation);
    }

    fNormalModePos[0] = SpawnInfo.vecPos[0];
'@ 'authoritative SetSpawnInfo'

PatchOne 'native/sampraknet_bridge.cpp' @'
    if (bIsSpectating && !bToggle && !iSpawned)
    {
        sampSpawn();
        iSpawned = 1;
    }
'@ @'
    // For PGRP, a released spectator and a SetSpawnInfo from the authenticated
    // server are BOTH required. The main Tick() sends the spawn once; never
    // send it automatically from an early class-selection RPC.
    if (g_pgrpEndpoint)
    {
        g_pgrpReleasedSpectator = (bToggle == 0);
        if (bToggle)
            g_pgrpSpawnInfoReady = false;
        Log("[PGRP Spawn] Spectator=%u AuthReleased=%u InfoReady=%u",
            unsigned(bToggle), unsigned(g_pgrpReleasedSpectator), unsigned(g_pgrpSpawnInfoReady));
    }
    else if (bIsSpectating && !bToggle && !iSpawned)
    {
        sampSpawn();
        iSpawned = 1;
    }
'@ 'respect spectator server permission'

PatchOne 'native/sampraknet_bridge.cpp' @'
    Log("%s", utf8.c_str());
}

void Chat(RPCParameters* rpcParams)
'@ @'
    // Internal one-bit UI role hint. Only the configured PGRP endpoint can set
    // this hint, and the /players command still verifies admin rank on server.
    // Do not expose a fake staff UI on ordinary players or on other servers.
    if (g_pgrpEndpoint && (utf8 == "PGRP_TAB_ROLE:1" || utf8 == "PGRP_TAB_ROLE:0"))
    {
        g_pgrpAdminTabAllowed = (utf8 == "PGRP_TAB_ROLE:1");
        Log("[PGRP TAB] server permitted admin menu=%d", int(g_pgrpAdminTabAllowed));
        return;
    }
    Log("%s", utf8.c_str());
}

void Chat(RPCParameters* rpcParams)
'@ 'consume server role hint'

PatchOne 'native/sampraknet_bridge.cpp' @'
        s_serverPort = port;

        s_serverPassword[0] = 0;
'@ @'
        s_serverPort = port;

        // Other open.mp endpoints retain the original generic spawn behavior.
        g_pgrpEndpoint = (port == 7777 && std::strcmp(host, "46.38.138.33") == 0);
        g_pgrpAdminTabAllowed = false;
        g_pgrpSpawnInfoReady = false;
        g_pgrpReleasedSpectator = false;

        s_serverPassword[0] = 0;
'@ 'isolate PGRP endpoint'

PatchOne 'native/sampraknet_bridge.cpp' @'
        if (iAreWeConnected && iGameInited && !iSpawned && !dialog_blocking)
'@ @'
        if (!g_pgrpEndpoint && iAreWeConnected && iGameInited && !iSpawned && !dialog_blocking)
'@ 'disable pre-auth auto-spawn PGRP'

PatchOne 'native/sampraknet_bridge.cpp' @'
        // Server is authoritative for time — vanilla CClock keeps ticking
'@ @'
        // A single PGRP spawn handshake follows successful server auth:
        // 1. SetSpawnInfo (NPC/skin/position), 2. ToggleSpectating(false).
        // Never teleport or send Spawn before these server messages arrive.
        if (g_pgrpEndpoint && iAreWeConnected && iGameInited && !iSpawned &&
            g_pgrpSpawnInfoReady && g_pgrpReleasedSpectator)
        {
            Log("[PGRP Spawn] Authorized by server; issuing first Spawn RPC");
            sampSpawn();
            iSpawned = 1;
            s_spawnStage = SpawnStage::Done;
        }

        // Server is authoritative for time — vanilla CClock keeps ticking
'@ 'authenticated-only first spawn'

PatchOne 'native/sampraknet_bridge.cpp' @'
    int  MyPlayerId()    { return g_myPlayerID; }

    void SendChat(const char* utf8_message)
'@ @'
    int  MyPlayerId()    { return g_myPlayerID; }
    bool IsPgrpEndpoint() { return g_pgrpEndpoint; }
    bool IsPgrpAdminTabAllowed() { return g_pgrpEndpoint && g_pgrpAdminTabAllowed && iSpawned && !bIsSpectating; }

    void SendChat(const char* utf8_message)
'@ 'expose verified UI role'

PatchOne 'native/sampraknet_bridge.h' @'
    int  MyPlayerId();      // -1 if not assigned yet
'@ @'
    int  MyPlayerId();
    // UI-only hint; the server always rechecks privileges on /players.
    bool IsPgrpEndpoint();
    bool IsPgrpAdminTabAllowed();
'@ 'declare UI role API'

PatchOne 'native/gui/imgui_manager.cpp' @'
        if (msg == WM_KEYDOWN)
        {
            // Toggle chat with T
'@ @'
        // In PGRP the native TAB scoreboard is disabled for ordinary players.
        // Staff TAB opens the server-authorized player list; the server's
        // /players handler is still the final permission boundary.
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
        if (msg == WM_KEYDOWN)
        {
            // Toggle chat with T
'@ 'TAB admin-only via verified server command'

Write-Host 'PGRP alpha v0.4.9: authenticating spawn before local ped movement; role-gated TAB UI.'

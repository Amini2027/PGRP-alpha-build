param([string]$Root = 'upstream')
$ErrorActionPreference = 'Stop'
$src = Join-Path $Root 'native/sampraknet_bridge.cpp'
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing client source: $src" }
$full = (Resolve-Path -LiteralPath $src).Path
$s = [IO.File]::ReadAllText($full)
function Replace-One([string]$Before, [string]$After, [string]$Tag) {
    $matches = ([regex]::Matches($script:s, [regex]::Escape($Before))).Count
    if ($matches -ne 1) { throw "Unexpected upstream layout for $Tag, matches=$matches" }
    $script:s = $script:s.Replace($Before, $After)
    Write-Host "PGRP WORLD SYNC PATCH OK: $Tag"
}

# open.mp/Shared/NetCode/core.hpp:
# SetPlayerTime is RPC 29 (two UINT8 fields: hour and minute).
# SetPlayerWorldTime is RPC 94 (one UINT8 hour).
# SetPlayerWeather is RPC 152 (one UINT8 weather).
# RPC 255 is NOT SetPlayerTime.
Replace-One 'static int RPC_SetTimeEx = 255;' @'
static int RPC_SetPlayerTime = 29; // open.mp NetCode::RPC::SetPlayerTime
static void PgrpApplyInitialWorld(BYTE hour, BYTE weather);
'@ 'register canonical RPC 29'

Replace-One '    g_myPlayerID = MyPlayerID;' @'
    // InitGame carries the starting server world state. Apply it before the
    // first render frame rather than waiting for a later broadcast.
    PgrpApplyInitialWorld(m_byteWorldTime, m_byteWeather);
    g_myPlayerID = MyPlayerID;
'@ 'initialize from InitGame hour/weather'

Replace-One '    bool  serverTimeKnown = false; // flips on first Weather/WorldTime/SetTimeEx' @'
    bool  serverTimeKnown = false;
    bool  serverWeatherKnown = false;
'@ 'track independent server time and weather authority'

Replace-One 'static WorldRpcState g_world;' @'
static WorldRpcState g_world;

static void PgrpApplyInitialWorld(BYTE hour, BYTE weather)
{
    if (hour < 24)
    {
        g_world.worldTimeHour = hour;
        g_world.worldTimeMinute = 0;
        g_world.serverTimeKnown = true;
        gta::sa::SetWorldTime(hour, 0);
    }
    // GTA SA has normal weather types 0..22. Reject malformed packets rather
    // than putting unknown weather indices into the original game's arrays.
    if (weather <= 22)
    {
        g_world.weather = weather;
        g_world.serverWeatherKnown = true;
        gta::sa::ReleaseForcedWeather();
        gta::sa::SetWeather(weather);
    }
    Log("[PGRP World Sync] InitGame hour=%u weather=%u", unsigned(hour), unsigned(weather));
}
'@ 'apply initial server world safely'

Replace-One @'
    BYTE w = 0;
    bs.Read(w);
    g_world.weather = w;
    gta::sa::SetWeather(w);
    Log("[Weather] %u", static_cast<unsigned>(w));
'@ @'
    BYTE w = 0;
    if (!bs.Read(w) || w > 22)
    {
        Log("[PGRP World Sync] Invalid weather RPC ignored");
        return;
    }
    g_world.weather = w;
    g_world.serverWeatherKnown = true;
    gta::sa::ReleaseForcedWeather();
    gta::sa::SetWeather(w);
    Log("[Weather] server weather=%u", static_cast<unsigned>(w));
'@ 'safe authoritative weather RPC'

Replace-One @'
    BYTE h = 0;
    bs.Read(h);
    g_world.worldTimeHour = h;
    g_world.serverTimeKnown = true;
    gta::sa::SetWorldTime(h, g_world.worldTimeMinute);
    Log("[WorldTime] hour=%u", static_cast<unsigned>(h));
'@ @'
    BYTE h = 0;
    if (!bs.Read(h) || h >= 24)
    {
        Log("[PGRP World Sync] Invalid world-time RPC ignored");
        return;
    }
    g_world.worldTimeHour = h;
    g_world.serverTimeKnown = true;
    gta::sa::SetWorldTime(h, g_world.worldTimeMinute);
    Log("[WorldTime] hour=%u", static_cast<unsigned>(h));
'@ 'safe authoritative hour RPC'

Replace-One @'
static void SetTimeEx(RPCParameters* rpcParams)
{
    RakNet::BitStream bs(reinterpret_cast<unsigned char*>(rpcParams->input),
                         (rpcParams->numberOfBitsOfData / 8) + 1, false);
    BYTE h = 0, m = 0;
    bs.Read(h);
    bs.Read(m);
    g_world.worldTimeHour   = h;
    g_world.worldTimeMinute = m;
    g_world.serverTimeKnown = true;
    gta::sa::SetWorldTime(h, m);
    Log("[SetTimeEx] %02u:%02u", static_cast<unsigned>(h), static_cast<unsigned>(m));
}
'@ @'
static void SetPlayerTime(RPCParameters* rpcParams)
{
    // SetPlayerTime RPC 29: UINT8 hour then UINT8 minute.
    RakNet::BitStream bs(reinterpret_cast<unsigned char*>(rpcParams->input),
                         (rpcParams->numberOfBitsOfData / 8) + 1, false);
    BYTE h = 0, m = 0;
    if (!bs.Read(h) || !bs.Read(m) || h >= 24 || m >= 60)
    {
        Log("[PGRP World Sync] Invalid player-time RPC ignored");
        return;
    }
    g_world.worldTimeHour   = h;
    g_world.worldTimeMinute = m;
    g_world.serverTimeKnown = true;
    gta::sa::SetWorldTime(h, m);
    Log("[SetPlayerTime] %02u:%02u", static_cast<unsigned>(h), static_cast<unsigned>(m));
}
'@ 'decode canonical hour/minute RPC'

Replace-One 'pRakClient->RegisterAsRemoteProcedureCall(&RPC_SetTimeEx,                SetTimeEx);' 'pRakClient->RegisterAsRemoteProcedureCall(&RPC_SetPlayerTime,             SetPlayerTime);' 'subscribe to RPC 29'
Replace-One 'pRakClient->UnregisterAsRemoteProcedureCall(&RPC_SetTimeEx);' 'pRakClient->UnregisterAsRemoteProcedureCall(&RPC_SetPlayerTime);' 'unsubscribe RPC 29'

Replace-One @'
        // Server is authoritative for time — vanilla CClock keeps ticking
        // every frame, so once we've heard a server time we re-pin it each
        // tick. Otherwise the HUD clock drifts forward independent of what
        // the server thinks the world time is.
        if (iAreWeConnected && iGameInited && g_world.serverTimeKnown)
        {
            gta::sa::SetWorldTime(g_world.worldTimeHour, g_world.worldTimeMinute);
        }
'@ @'
        // Server-authoritative world state: GTA's own CClock and CWeather
        // advance every frame. Keep both in step with the most recent RPC.
        // Two byte writes for clock and two 16-bit writes for weather are cheap
        // enough for older PCs; no allocations, timers or GPU effects here.
        if (iAreWeConnected && iGameInited)
        {
            if (g_world.serverTimeKnown)
                gta::sa::SetWorldTime(g_world.worldTimeHour, g_world.worldTimeMinute);
            if (g_world.serverWeatherKnown)
                gta::sa::SetWeather(g_world.weather);
        }
'@ 'pin client clock and weather to server state'

if ($s.Contains('RPC_SetTimeEx') -or $s.Contains('[SetTimeEx]')) {
    throw 'RPC 255 SetTimeEx was not fully removed'
}
[IO.File]::WriteAllText($full, $s, [Text.UTF8Encoding]::new($false))
Write-Host 'PGRP World Sync v0.4.8: canonical open.mp time, weather and initial synchronization enabled.'

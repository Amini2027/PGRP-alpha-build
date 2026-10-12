param([string]$PayloadDir = 'upstream\bin')
$ErrorActionPreference = 'Stop'
$root=Join-Path $env:RUNNER_TEMP ('pgrp-update-installer-smoke-' + [guid]::NewGuid().ToString('N'))
$game=Join-Path $root 'GTA_San_Andreas'
New-Item -ItemType Directory -Path $game -Force | Out-Null
try {
    $gta=Join-Path $game 'gta_sa.exe'
    $launch=Join-Path $game 'opensamp.exe'
    $dll=Join-Path $game 'Client.Native.dll'
    [IO.File]::WriteAllBytes($gta,[byte[]](1,2,3,4,5))
    [IO.File]::WriteAllBytes($launch,[byte[]](9,8,7))
    [IO.File]::WriteAllBytes($dll,[byte[]](6,7,8,9))
    $gtaBefore=(Get-FileHash -LiteralPath $gta -Algorithm SHA256).Hash
    $launcherBefore=(Get-FileHash -LiteralPath $launch -Algorithm SHA256).Hash
    $originalDllHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    & .\tools\install-v043-ui-update.ps1 -GameDirectory $game -PayloadDir $PayloadDir -NoSetup
    if ($LASTEXITCODE -ne 0) {throw 'Installer first run failed'}
    $installed=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    $expected=(Get-FileHash -LiteralPath (Join-Path $PayloadDir 'Client.Native.dll') -Algorithm SHA256).Hash
    if($installed -ne $expected) {throw 'DLL hash mismatch after install'}
    if((Get-FileHash $gta -Algorithm SHA256).Hash -ne $gtaBefore) {throw 'Installer modified gta_sa.exe'}
    if((Get-FileHash $launch -Algorithm SHA256).Hash -ne $launcherBefore) {throw 'Installer modified opensamp.exe'}
    $backups=@(Get-ChildItem -LiteralPath $game -Directory -Filter 'PGRP_Backup_v043_*')
    if($backups.Count -ne 1) {throw 'Exactly one backup required after first install'}
    $saved=(Get-FileHash (Join-Path $backups[0].FullName 'Client.Native.dll') -Algorithm SHA256).Hash
    if ($saved -ne $originalDllHash) {throw 'Backup did not preserve original DLL'}
    & .\tools\install-v043-ui-update.ps1 -GameDirectory $game -PayloadDir $PayloadDir -NoSetup
    if($LASTEXITCODE -ne 0) {throw 'Idempotent second install failed'}
    $backups2=@(Get-ChildItem -LiteralPath $game -Directory -Filter 'PGRP_Backup_v043_*')
    if($backups2.Count -ne 1) {throw 'Idempotent install created a duplicate backup'}
    Write-Host "PGRP v0.4.3 updater smoke PASS: clean update, backup/verify, no GTA/launcher mutation, idempotent re-run."
}
finally {
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
}

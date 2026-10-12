param(
    [string]$GameDirectory = "",
    [string]$PayloadDir = "",
    [switch]$NoSetup
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PayloadDir) { $PayloadDir = $PSScriptRoot }
if (-not $GameDirectory) {
    $GameDirectory = Join-Path $env:LOCALAPPDATA 'PaladinGuard\PGRP_Alpha_v0.4.2\GTA_San_Andreas'
}
$logFile = Join-Path $env:TEMP 'PGRP_v043_Install_Log.txt'
function Say([string]$msg) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}
$source = Join-Path $PayloadDir 'Client.Native.dll'
$target = Join-Path $GameDirectory 'Client.Native.dll'
$originalLauncher = Join-Path $GameDirectory 'opensamp.exe'
$originalGame = Join-Path $GameDirectory 'gta_sa.exe'
$setup = Join-Path $PayloadDir 'PGRP_Alpha_v0.4.2_Setup_Windows_x64.exe'
$staged = Join-Path $GameDirectory 'Client.Native.dll.pgrp-stage'
$backup = $null
try {
    Say "PGRP GUI/cursor/resolution patch v0.4.3 — safe installer"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw 'Patch DLL missing; extract the ENTIRE ZIP into a separate folder first.'
    }
    if (-not (Test-Path -LiteralPath $originalGame -PathType Leaf) -or
        -not (Test-Path -LiteralPath $originalLauncher -PathType Leaf)) {
        if ($NoSetup) {
            throw ('Clean test: no existing game/launcher in ' + $GameDirectory)
        }
        if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
            throw 'Original v0.4.2 Setup missing; please extract ENTIRE ZIP first.'
        }
        Say 'Installed game not found. Starting trusted existing v0.4.2 Setup; please finish the installer window.'
        $p = Start-Process -FilePath $setup -PassThru -Wait
        Say ('Base Setup returned exit code ' + $p.ExitCode)
        if (-not (Test-Path -LiteralPath $originalGame -PathType Leaf) -or
            -not (Test-Path -LiteralPath $originalLauncher -PathType Leaf)) {
            throw ('Base installer did not produce expected GTA/opensamp files at ' + $GameDirectory)
        }
    }
    foreach ($processName in @('gta_sa','opensamp')) {
        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            throw ('Close all processes named ' + $processName + ' before updating.')
        }
    }
    $sourceFile = Get-Item -LiteralPath $source
    $targetFile = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    Say ('Source SHA256: ' + $sourceHash)
    if ($targetFile -and $targetFile.FullName -ieq $sourceFile.FullName) {
        Say 'Source and target are the same file: already in the install folder. No replacement attempted.'
        exit 0
    }
    if ($targetFile -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $sourceHash) {
        Say 'Already updated. Existing Client.Native.dll matches this release.'
        exit 0
    }
    $backup = Join-Path $GameDirectory ('PGRP_Backup_v043_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -Path $backup -ItemType Directory -ErrorAction Stop | Out-Null
    if ($targetFile) {
        $backupDll = Join-Path $backup 'Client.Native.dll'
        $hashBefore = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $target -Destination $backupDll -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $backupDll -Algorithm SHA256).Hash -ne $hashBefore) {
            throw 'Backup verification FAILED; existing DLL has not been modified.'
        }
        Say ('Existing DLL safely backed up at ' + $backupDll)
    }
    if (Test-Path -LiteralPath $staged -PathType Leaf) {
        Remove-Item -LiteralPath $staged -Force
    }
    Copy-Item -LiteralPath $source -Destination $staged -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $sourceHash) {
        throw 'Staging verification failed before replacement.'
    }
    if ($targetFile) {
        [System.IO.File]::Replace($staged, $target, $null, $true)
    } else {
        Move-Item -LiteralPath $staged -Destination $target -ErrorAction Stop
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHash) {
        throw 'Installed file verification failed!'
    }
    Say 'SUCCESS: updated Client.Native.dll. Original opensamp.exe and gta_sa.exe were NOT modified.'
    Say ('Game directory: ' + $GameDirectory)
    Say 'Launch the installed original PGRP launcher / opensamp.exe to test.'
    exit 0
}
catch {
    Say ('FAILURE: ' + $_.Exception.Message)
    if ($backup) {
        $backupDll = Join-Path $backup 'Client.Native.dll'
        if (Test-Path -LiteralPath $backupDll -PathType Leaf) {
            try {
                Copy-Item -LiteralPath $backupDll -Destination $target -Force -ErrorAction Stop
                Say 'Old Client.Native.dll restored from verified backup.'
            } catch {
                Say ('RESTORE FAILED; backup remains at: ' + $backupDll + '; ' + $_.Exception.Message)
            }
        }
    }
    exit 1
}
finally {
    if (Test-Path -LiteralPath $staged -PathType Leaf) {
        Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
    }
    Say ('Full installer log: ' + $logFile)
}

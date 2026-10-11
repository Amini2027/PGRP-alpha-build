param([string]$SourceDir = 'upstream\bin')
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:RUNNER_TEMP 'pgrp-mock-gta-smoke'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$stub = @'
using System;
using System.Threading;
internal static class GTAStub
{
    [STAThread]
    private static void Main()
    {
        // Harmless 32-bit test process, NOT Rockstar GTA or a game emulator.
        Thread.Sleep(45000);
    }
}
'@
$csPath = Join-Path $work 'GTAStub.cs'
[IO.File]::WriteAllText($csPath,$stub,[Text.UTF8Encoding]::new($false))
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
if (!(Test-Path $csc)) { throw "The .NET Framework 32-bit csc.exe compiler was not found: $csc" }
& $csc /nologo /platform:x86 /target:winexe "/out:$work\gta_sa.exe" $csPath
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile x86 GTA test stand-in' }
Copy-Item (Join-Path $SourceDir 'opensamp.exe') -Destination $work -Force
Copy-Item (Join-Path $SourceDir 'Client.Native.dll') -Destination $work -Force

function Test-Pgrp([string]$Name,[string]$SkipInjection,[string]$Passive,[string]$Stage) {
    Write-Host "== Testing $Name =="
    $env:PGRP_SKIP_INJECTION = $SkipInjection
    $env:PGRP_DLL_PASSIVE = $Passive
    $env:PGRP_BOOT_STAGE = $Stage
    $env:PGRP_INJECT_DELAY_MS = '0'
    $env:PGRP_SMOKE_TAG = $Name
    foreach ($p in @('PGRP_Launcher_Trace.log','PGRP_Native_Init.log','PGRP_Launcher_Error.txt')) {
        Remove-Item (Join-Path $work $p) -Force -ErrorAction SilentlyContinue
    }
    try {
        $launcher = Start-Process -FilePath (Join-Path $work 'opensamp.exe') -WorkingDirectory $work -PassThru
        if (!$launcher.WaitForExit(20000)) {
            Stop-Process -Id $launcher.Id -Force -ErrorAction SilentlyContinue
            throw "Launcher hung during $Name"
        }
        $code = $launcher.ExitCode
        Write-Host "Launcher exit code: $code"
        $alive = @(Get-Process -Name 'gta_sa' -ErrorAction SilentlyContinue)
        Write-Host "Running stub processes: $($alive.Count)"
        $tracePath = Join-Path $work 'PGRP_Launcher_Trace.log'
        if (Test-Path $tracePath) {
            Get-Content $tracePath | ForEach-Object { Write-Host "TRACE: $_" }
        }
        $nativePath = Join-Path $work 'PGRP_Native_Init.log'
        if (Test-Path $nativePath) {
            Get-Content $nativePath | ForEach-Object { Write-Host "NATIVE: $_" }
        }
        if ($code -ne 0 -or $alive.Count -lt 1) {
            throw "$Name failed: launcher code=$code, GTA mock alive count=$($alive.Count)"
        }
        if ($Name -eq 'no injection') {
            if (!(Select-String -Path $tracePath -Pattern 'CONTROL PASS' -Quiet)) {
                throw 'No-injection control did not reach CONTROL PASS'
            }
        }
        elseif ($Name -eq 'passive DLL') {
            if (!(Select-String -Path $tracePath -Pattern 'DLL LoadLibraryW returned successfully' -Quiet)) {
                throw 'Passive DLL did not finish LoadLibraryW'
            }
        }
        elseif ($Name -eq 'stage zero DLL') {
            if (!(Select-String -Path $nativePath -Pattern 'MODE 0' -Quiet)) {
                throw 'Stage zero was not entered by the injected DLL'
            }
        }
        Write-Host "SMOKE PASS: $Name"
    }
    finally {
        @(Get-Process -Name 'gta_sa' -ErrorAction SilentlyContinue) | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}
Test-Pgrp -Name 'no injection' -SkipInjection '1' -Passive '0' -Stage '0'
Test-Pgrp -Name 'passive DLL' -SkipInjection '0' -Passive '1' -Stage '0'
Test-Pgrp -Name 'stage zero DLL' -SkipInjection '0' -Passive '0' -Stage '0'
Write-Host 'All three Win32 injection-path smoke tests passed against a synthetic x86 GTA stand-in.'

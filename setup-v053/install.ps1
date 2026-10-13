param(
    [Parameter(Mandatory=$true)][string]$AssetsDir,
    [string]$SourceGTA = "",
    [string]$InstallRoot = "",
    [switch]$Silent,
    [switch]$UiSmoke,
    [switch]$UiActionSmoke
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$LogPath=Join-Path $env:TEMP "PGRP_v053_Setup.log"
$DefaultRoot=Join-Path $env:LOCALAPPDATA "PaladinGuard\PGRP_Alpha_v0.5.3"
if(-not $InstallRoot) { $InstallRoot=$DefaultRoot }
$DllAsset=Join-Path $AssetsDir "Client.Native.dll"
$ExeAsset=Join-Path $AssetsDir "opensamp.exe"
$LauncherAsset=Join-Path $AssetsDir "PGRPLauncher.exe"
$VcAsset=Join-Path $AssetsDir "vc_redist.x86.exe"
function Log([string]$m) {
    $line=("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$m)
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    if($Silent) { Write-Host $line }
}
function Get-PgrpSHA256([string]$FilePath) {
    $sha=[System.Security.Cryptography.SHA256]::Create()
    $stream=[System.IO.File]::OpenRead($FilePath)
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}
function Resolve-Gta([string]$InputPath) {
    if([string]::IsNullOrWhiteSpace($InputPath)) { throw "Select an existing GTA San Andreas gta_sa.exe first." }
    $p=$InputPath.Trim().Trim('"')
    if(Test-Path -LiteralPath $p -PathType Container) { $p=Join-Path $p "gta_sa.exe" }
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ("GTA not found: " + $p) }
    if((Split-Path -Leaf $p) -ine "gta_sa.exe") { throw "Please select gta_sa.exe" }
    $full=(Resolve-Path -LiteralPath $p).Path
    $dir=Split-Path -Parent $full
    foreach($subdir in @("models","data")) {
        if(-not (Test-Path -LiteralPath (Join-Path $dir $subdir) -PathType Container)) {
            throw ("GTA installation incomplete: missing " + $subdir)
        }
    }
    return $full
}
function Install-Gta([string]$GtaFile) {
    foreach($file in @($DllAsset,$ExeAsset,$LauncherAsset,$VcAsset)) {
        if(-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ("Setup payload missing: "+$file) }
    }
    $sourceExe=Resolve-Gta $GtaFile
    # Verify genuine Microsoft x86 VC++ runtime before invoking with elevation.
    $vcSig=Get-AuthenticodeSignature -LiteralPath $VcAsset
    if($vcSig.Status -ne 'Valid' -or $vcSig.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw 'Bundled VC++ runtime is unsigned or not signed by Microsoft; refusing to run it.'
    }
    $vcReg='HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
    $needsRuntime=$true
    try {
        $vcInfo=Get-ItemProperty -LiteralPath $vcReg -ErrorAction Stop
        if($vcInfo.Installed -eq 1) {$needsRuntime=$false}
    } catch {}
    if($UiActionSmoke) {
        # CI runs on a non-interactive Windows desktop: never block waiting
        # for a prerequisite UAC elevation prompt during an installer GUI test.
        # The signed VC++ payload was verified above and still ships in Setup.
        Log ('GUI test: signed VC++ payload validated; installation deferred. Present=' + (-not $needsRuntime))
    }
    elseif($needsRuntime) {
        Log 'Installing official Microsoft VC++ 2015-2022 x86 runtime (Windows consent/UAC may be required).'
        $vc=Start-Process -FilePath $VcAsset -ArgumentList @('/install','/passive','/norestart') -Wait -PassThru
        if($vc.ExitCode -ne 0 -and $vc.ExitCode -ne 3010 -and $vc.ExitCode -ne 1638) {
            throw ('Official VC++ runtime install failed; exit code '+$vc.ExitCode)
        }
        if($vc.ExitCode -eq 3010) { Log 'VC++ requires restart to complete.' }
        Log ('VC++ runtime setup returned '+$vc.ExitCode)
    } else { Log 'Microsoft VC++ x86 runtime already installed.' }
    $src=Split-Path -Parent $sourceExe
    $destRoot=[IO.Path]::GetFullPath($InstallRoot)
    $dest=Join-Path $destRoot "GTA_San_Andreas"
    if($src.TrimEnd('\') -ieq $dest.TrimEnd('\')) { throw "Source and target folders cannot be identical." }
    foreach($n in @("gta_sa","opensamp")) {
        if(Get-Process -Name $n -ErrorAction SilentlyContinue) { throw ("Close "+$n+".exe before installation.") }
    }
    Log ("Selected GTA: "+$sourceExe)
    Log ("Clean destination: "+$dest)
    $parent=Split-Path -Parent $destRoot
    if(-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $previous=""
    if(Test-Path -LiteralPath $destRoot) {
        $previous=$destRoot+".backup_"+(Get-Date -Format "yyyyMMdd_HHmmss")
        Move-Item -LiteralPath $destRoot -Destination $previous -ErrorAction Stop
        Log ("Previous v0.5.3 copy backed up to "+$previous)
    }
    try {
        [void](New-Item -ItemType Directory -Path $dest -Force)
        Log "Copying owned GTA into a separate PGRP v0.5.3 installation..."
        $args=('"{0}" "{1}" /E /XJ /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NP /NFL /NDL /NJH /NJS /XF opensamp.exe Client.Native.dll /XD crash' -f $src,$dest)
        $psi=New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName="robocopy.exe"
        $psi.Arguments=$args
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $p=[System.Diagnostics.Process]::Start($psi)
        while(-not $p.HasExited) {
            Start-Sleep -Milliseconds 200
            if(-not $Silent) { [System.Windows.Forms.Application]::DoEvents() }
        }
        Log ("Robocopy result="+$p.ExitCode)
        if($p.ExitCode -ge 8) { throw ("Failed to copy game files, Robocopy exit "+$p.ExitCode) }
        if(-not (Test-Path -LiteralPath (Join-Path $dest "gta_sa.exe") -PathType Leaf)) {
            throw "The copied GTA directory does not contain gta_sa.exe."
        }
        foreach($bin in @(@{name="opensamp.exe";src=$ExeAsset},@{name="Client.Native.dll";src=$DllAsset})) {
            $out=Join-Path $dest $bin.name
            Copy-Item -LiteralPath $bin.src -Destination $out -Force -ErrorAction Stop
            $h1=(Get-PgrpSHA256 $bin.src)
            $h2=(Get-PgrpSHA256 $out)
            if($h1 -ne $h2) { throw ("Installed binary mismatch: "+$bin.name) }
            Log ($bin.name+" SHA256 verified: "+$h2)
        }
        $installedLauncher=Join-Path $destRoot "PGRPLauncher.exe"
        Copy-Item -LiteralPath $LauncherAsset -Destination $installedLauncher -Force
        if((Get-PgrpSHA256 $LauncherAsset) -ne (Get-PgrpSHA256 $installedLauncher)) {
            throw 'Installed launcher SHA256 mismatch'
        }
        $manifest=@(
            "PGRP v0.5.3 - client + launcher all-in-one",
            ("Installed: "+(Get-Date -Format o)),
            ("Source game: "+$sourceExe),
            ("Installed game: "+$dest),
            ("opensamp.exe SHA256: "+(Get-PgrpSHA256 (Join-Path $dest "opensamp.exe"))),
            ("Client.Native.dll SHA256: "+(Get-PgrpSHA256 (Join-Path $dest "Client.Native.dll"))),
            ("PGRPLauncher.exe SHA256: "+(Get-PgrpSHA256 (Join-Path $destRoot "PGRPLauncher.exe"))),
            "Server: 46.38.138.33:7777",
            "This setup never alters server-side account records."
        )
        [IO.File]::WriteAllLines((Join-Path $destRoot "PGRP_Installed_Version.txt"),$manifest,[Text.Encoding]::UTF8)
        $cmd= '@echo off'+[Environment]::NewLine+'cd /d "%~dp0"'+[Environment]::NewLine+'start "" "PGRPLauncher.exe"'+[Environment]::NewLine
        [IO.File]::WriteAllText((Join-Path $destRoot "PGRP_Play.cmd"),$cmd,[Text.Encoding]::ASCII)
        try {
            $shell=New-Object -ComObject WScript.Shell
            $desk=[Environment]::GetFolderPath("DesktopDirectory")
            if($desk) {
                $shortcut=$shell.CreateShortcut((Join-Path $desk "PGRP Alpha v0.5.3.lnk"))
                $shortcut.TargetPath=Join-Path $destRoot "PGRPLauncher.exe"
                $shortcut.WorkingDirectory=$destRoot
                $shortcut.Description="Paladin Guard RolePlay v0.5.3"
                $shortcut.Save()
            }
        } catch { Log ("Shortcut skipped: "+$_.Exception.Message) }
        Log "SUCCESS: PGRP v0.5.3 complete launcher+client installed in separate path."
        return $destRoot
    } catch {
        Log ("ERROR: "+$_.Exception.Message)
        if(Test-Path -LiteralPath $destRoot) {
            try { Remove-Item -LiteralPath $destRoot -Recurse -Force -ErrorAction Stop }
            catch { Log ("Partial destination cleanup failed: "+$_.Exception.Message) }
        }
        if($previous -and (Test-Path -LiteralPath $previous) -and -not (Test-Path -LiteralPath $destRoot)) {
            Move-Item -LiteralPath $previous -Destination $destRoot
            Log "Restored previous v0.5.3 installation."
        }
        throw
    }
}
try {
    if($Silent) {
        Install-Gta $SourceGTA | Out-Null
        exit 0
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form=New-Object System.Windows.Forms.Form
    $form.Text="PALADIN GUARD | All-in-One v0.5.3 Installer"
    $form.ClientSize=[System.Drawing.Size]::new(740,410)
    $form.StartPosition="CenterScreen"
    $form.FormBorderStyle="FixedDialog"
    $form.MaximizeBox=$false
    $form.Font=[System.Drawing.Font]::new("Segoe UI",10)
    $heading=New-Object System.Windows.Forms.Label
    $heading.Text="PGRP v0.5.3 | Game Client + Animated Launcher + Prerequisites"
    $heading.Location=[System.Drawing.Point]::new(22,20)
    $heading.AutoSize=$true
    $form.Controls.Add($heading)
    $caption=New-Object System.Windows.Forms.Label
    $caption.Text="Select an existing GTA San Andreas gta_sa.exe:"
    $caption.Location=[System.Drawing.Point]::new(22,64)
    $caption.AutoSize=$true
    $form.Controls.Add($caption)
    $script:gtaExeTextBox=New-Object System.Windows.Forms.TextBox
    $script:gtaExeTextBox.Location=[System.Drawing.Point]::new(22,94)
    $script:gtaExeTextBox.Size=[System.Drawing.Size]::new(558,30)
    foreach($candidate in @(
        (Join-Path $env:LOCALAPPDATA "PaladinGuard\PGRP_Alpha_v0.4.2\GTA_San_Andreas\gta_sa.exe"),
        "C:\Program Files (x86)\Rockstar Games\GTA San Andreas\gta_sa.exe"
    )) {
        if(Test-Path -LiteralPath $candidate -PathType Leaf) { $script:gtaExeTextBox.Text=$candidate; break }
    }
    $form.Controls.Add($script:gtaExeTextBox)
    $browse=New-Object System.Windows.Forms.Button
    $browse.Text="Browse GTA"
    $browse.Location=[System.Drawing.Point]::new(594,92)
    $browse.Size=[System.Drawing.Size]::new(122,34)
    $browse.Add_Click({
        if ($UiActionSmoke) {
            if (-not $SourceGTA) { throw "GUI Action Smoke requires -SourceGTA" }
            Log ("Browse-click smoke ENTER; source GTA="+$SourceGTA)
            $script:gtaExeTextBox.Text=$SourceGTA
            Log ("Browse-click smoke: GTA textbox updated to "+$script:gtaExeTextBox.Text)
            return
        }
        $picker=New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title="Locate gta_sa.exe"
        $picker.Filter="GTA executable (gta_sa.exe)|gta_sa.exe|EXE (*.exe)|*.exe"
        $picker.CheckFileExists=$true
        if($picker.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:gtaExeTextBox.Text=$picker.FileName
        }
        $picker.Dispose()
    })
    $form.Controls.Add($browse)
    $destInfo=New-Object System.Windows.Forms.Label
    $destInfo.Location=[System.Drawing.Point]::new(22,151)
    $destInfo.Size=[System.Drawing.Size]::new(694,49)
    $destInfo.Text=("New independent install: "+(Join-Path $DefaultRoot "GTA_San_Andreas"))
    $form.Controls.Add($destInfo)
    $note=New-Object System.Windows.Forms.Label
    $note.Location=[System.Drawing.Point]::new(22,205)
    $note.Size=[System.Drawing.Size]::new(694,44)
    $note.Text="Installs GTA copy + native PGRP client + animated launcher + official VC++ x86 runtime if needed. Earlier installations stay untouched."
    $form.Controls.Add($note)
    $progress=New-Object System.Windows.Forms.ProgressBar
    $progress.Location=[System.Drawing.Point]::new(22,257)
    $progress.Size=[System.Drawing.Size]::new(694,16)
    $progress.Style="Marquee"
    $progress.Visible=$false
    $form.Controls.Add($progress)
    $status=New-Object System.Windows.Forms.Label
    $status.Location=[System.Drawing.Point]::new(22,282)
    $status.Size=[System.Drawing.Size]::new(694,25)
    $status.Text="Ready for installation"
    $form.Controls.Add($status)
    $install=New-Object System.Windows.Forms.Button
    $install.Text="Install PGRP | All-in-One"
    $install.Location=[System.Drawing.Point]::new(22,316)
    $install.Size=[System.Drawing.Size]::new(230,35)
    $install.Add_Click({
        $install.Enabled=$false
        $browse.Enabled=$false
        $script:gtaExeTextBox.Enabled=$false
        $progress.Visible=$true
        $status.Text="Copying and verifying files, please wait..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $selectedGtaPath=$script:gtaExeTextBox.Text
            Log ("Install-click: received GTA path " + $selectedGtaPath)
            $installed=Install-Gta $selectedGtaPath
            $status.Text="Installation completed! Starting PGRP Launcher..."
            if ($UiActionSmoke) {
                [IO.File]::WriteAllText((Join-Path $env:TEMP "PGRP_v053_UI_Action_Smoke.ok"), "UI_BROWSE_AND_INSTALL_PASS=" + $selectedGtaPath)
                Log "Install-click smoke succeeded; exiting dialog automatically."
            } else {
                [System.Windows.Forms.MessageBox]::Show($form,("PGRP v0.5.3 installed successfully at:"+[Environment]::NewLine+$installed),"PGRP Setup","OK","Information") | Out-Null
                Start-Process -FilePath (Join-Path $installed "PGRPLauncher.exe") -WorkingDirectory $installed
            }
            $form.Close()
        } catch {
            $status.Text="Installation failed. See PGRP_v053_Setup.log in TEMP."
            Log ("Install UI failure: " + $_.Exception.ToString())
            if ($UiActionSmoke) {
                [IO.File]::WriteAllText((Join-Path $env:TEMP "PGRP_v053_UI_Action_Smoke.error"), $_.Exception.ToString())
                $form.Close()
            } else {
                [System.Windows.Forms.MessageBox]::Show($form,($_.Exception.Message+[Environment]::NewLine+"Log: "+$LogPath),"PGRP Setup error","OK","Error") | Out-Null
            }
        } finally {
            $install.Enabled=$true
            $browse.Enabled=$true
            $script:gtaExeTextBox.Enabled=$true
            $progress.Visible=$false
        }
    })
    $form.Controls.Add($install)
    if ($UiActionSmoke) {
        $successPath=Join-Path $env:TEMP "PGRP_v053_UI_Action_Smoke.ok"
        $errorPath=Join-Path $env:TEMP "PGRP_v053_UI_Action_Smoke.error"
        Remove-Item -LiteralPath $successPath,$errorPath -Force -ErrorAction SilentlyContinue
        $form.Add_Shown({
            $script:actionSmokeTimer=New-Object System.Windows.Forms.Timer
            $script:actionSmokeTimer.Interval=500
            $script:actionSmokeTimer.Add_Tick({
                $script:actionSmokeTimer.Stop()
                try {
                    Log "GUI-action timer: before Browse.PerformClick"
                    $browse.PerformClick()
                    Log "GUI-action timer: after Browse.PerformClick"
                    if ($script:gtaExeTextBox.Text -ne $SourceGTA) {
                        throw 'Browse handler did not update the TextBox'
                    }
                    Log ('GUI action smoke clicking Install for '+$script:gtaExeTextBox.Text)
                    Log "GUI-action timer: before Install.PerformClick"
                    $install.PerformClick()
                    Log "GUI-action timer: after Install.PerformClick"
                } catch {
                    [IO.File]::WriteAllText((Join-Path $env:TEMP "PGRP_v053_UI_Action_Smoke.error"), $_.Exception.ToString())
                    $form.Close()
                }
            })
            $script:actionSmokeTimer.Start()
        })
    }
    if ($UiSmoke) {
        $probePath = Join-Path $env:TEMP "PGRP_v053_UI_Smoke.ok"
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        $form.Add_Shown({
            $visible=$form.Visible
            Log ("WinForms Shown fired; Visible=" + $visible)
            if ($visible) {
                [IO.File]::WriteAllText($probePath, "WINFORMS_VISIBLE=TRUE")
            }
            $script:smokeTimer=New-Object System.Windows.Forms.Timer
            $script:smokeTimer.Interval=1500
            $script:smokeTimer.Add_Tick({
                $script:smokeTimer.Stop()
                $form.Close()
            })
            $script:smokeTimer.Start()
        })
    }
    [void]$form.ShowDialog()
    if ($UiSmoke -and -not (Test-Path -LiteralPath $probePath -PathType Leaf)) {
        throw 'Installer GUI probe did not observe a visible Shown event.'
    }
    if ($UiActionSmoke) {
        if (Test-Path -LiteralPath $errorPath -PathType Leaf) {
            throw ('GUI Browse/Install smoke failed: '+(Get-Content -LiteralPath $errorPath -Raw))
        }
        if (-not (Test-Path -LiteralPath $successPath -PathType Leaf)) {
            throw 'GUI Browse/Install smoke did not report success.'
        }
        Log 'GUI Action Smoke succeeded.'
    }
} catch {
    Log ("SETUP FAILED: "+$_.Exception.Message)
    if($Silent -or $UiActionSmoke -or $UiSmoke) { throw }
    try { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,"PGRP Setup error","OK","Error") | Out-Null } catch {}
    exit 1
}

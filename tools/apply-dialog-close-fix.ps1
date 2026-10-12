param([string]$Root='upstream')
$ErrorActionPreference='Stop'
$path=Join-Path $Root 'native/sampraknet_bridge.cpp'
if (!(Test-Path -LiteralPath $path)) {throw 'OpenSAMP RPC handler source missing'}
$full=(Resolve-Path -LiteralPath $path).Path
$s=[IO.File]::ReadAllText($full)
$before=@'
    bsData.Read(sampDialog.wDialogID);
    bsData.Read(sampDialog.bDialogStyle);

    bsData.Read(sampDialog.bTitleLength);
'@
$after=@'
    // SA-MP/open.mp closes dialogs using the reserved dialog ID 0xFFFF.
    // HidePlayerDialog can send the close marker with no normal title/buttons.
    // Do NOT decode a "blank dialog" from the close packet: the former client
    // rendered an empty modal after successful PGRP login until Enter was hit.
    if (!bsData.Read(sampDialog.wDialogID))
        return;
    if (sampDialog.wDialogID == 0xFFFFu)
    {
        opensamp::gui::Dialog::Get().Hide();
        return;
    }
    if (!bsData.Read(sampDialog.bDialogStyle))
        return;
    if (sampDialog.bDialogStyle == 255)
    {
        opensamp::gui::Dialog::Get().Hide();
        return;
    }

    if (!bsData.Read(sampDialog.bTitleLength))
        return;
'@
$count=([regex]::Matches($s,[regex]::Escape($before))).Count
if($count -ne 1) { throw "RPC close marker patch expects one match; got $count" }
$s=$s.Replace($before,$after)
[IO.File]::WriteAllText($full,$s,[Text.UTF8Encoding]::new($false))
Write-Host 'FIXED: 0xFFFF HidePlayerDialog RPC is consumed instead of shown as an empty form.'

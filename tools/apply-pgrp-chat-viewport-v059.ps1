param([string]$Root='upstream')
$ErrorActionPreference='Stop'
$p=(Resolve-Path -LiteralPath (Join-Path $Root 'native/gui/chat.cpp')).Path
$s=[IO.File]::ReadAllText($p)
function Replace-One([string]$before,[string]$after,[string]$label){
 $script:count=([regex]::Matches($script:s,[regex]::Escape($before))).Count
 if($script:count -ne 1){throw ("v059 chat "+$label+": expected 1 anchor, found "+$script:count)}
 $script:s=$script:s.Replace($before,$after)
 Write-Host ("PGRP v059 CHAT PATCH OK "+$label)
}
Replace-One @'
    constexpr float pad = 20.0f;
    const float width = min(720.0f, io.DisplaySize.x - pad * 2.0f);
'@ @'
    // Keep the top of the in-game chat below the title/HUD safe zone,
    // including 1280x960x32 and higher-DPI fullscreen configurations.
    const float pad = std::max(24.f,std::min(70.f,io.DisplaySize.y*.052f));
    const float width = std::max(290.f,std::min(800.f,io.DisplaySize.x-pad*2.f));
'@ 'adaptive high-resolution chat margins'
Replace-One @'
    const float height = lineH * static_cast<float>(IsModal() ? m_visibleLines : 5) + lineH * 2.2f;
'@ @'
    // Never allow chat to extend beyond the renderable game viewport.
    // The original fixed-height child clipped the earliest visible lines
    // at unusual 1280x960 display scaling modes.
    const float idealHeight = lineH * static_cast<float>(IsModal() ? m_visibleLines : 5) + lineH * 2.2f;
    const float height=std::min(idealHeight,std::max(90.f,io.DisplaySize.y-pad-34.f));
'@ 'clamp chat window to actual viewport'
Replace-One @'
    const int linesToShow = m_visibleLines;
'@ @'
    const int linesToShow = std::max(1,std::min(m_visibleLines,
        static_cast<int>((std::max(40.f,io.DisplaySize.y-pad-60.f))/lineH)));
'@ 'fit line count to 960p+ geometry'
[IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($false))
Write-Host 'PGRP v059 chat high-resolution viewport clipping fixed.'

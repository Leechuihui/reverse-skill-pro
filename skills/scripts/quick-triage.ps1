#Requires -Version 5.1
# reverse-skill-pro: one-shot artifact triage.
# magic bytes -> file class -> suggested routes -> tool availability -> triage report.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File skills/scripts/quick-triage.ps1 -Path "C:\case\app.apk"
#   powershell ... -Path "C:\case\target.so" -Hint "restore sign algorithm" -ProjectRoot "C:\analysis"
# Exit codes: 0 ok / 2 usage or missing input
param(
    [string] $Path = '',
    [string] $Hint = '',
    [string] $OutDir = '',
    [string] $ProjectRoot = ''
)
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$skillsRoot = Split-Path -Parent $scriptDir

if ([string]::IsNullOrWhiteSpace($Path)) {
    Write-Host 'ERROR: -Path <artifact> required' -ForegroundColor Red
    Write-Host 'Usage: quick-triage.ps1 -Path <file> [-Hint "<task text>"] [-ProjectRoot <dir>]'
    exit 2
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host ("ERROR: file not found: {0}" -f $Path) -ForegroundColor Red
    exit 2
}

. (Join-Path (Join-Path $scriptDir 'lib') 'WorkRoot.ps1')
$projectRoot = Resolve-ReverseProjectRoot -RequestedRoot $ProjectRoot

# --- 1) read header bytes ---
$bytes = New-Object byte[] 16
$fs = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Path))
try { [void]$fs.Read($bytes, 0, 16) } finally { $fs.Close() }
$hex = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
$ascii = -join ($bytes | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } })

function Test-Magic([string]$hx, [string]$pattern) { return $hx.StartsWith($pattern) }

# --- 2) classify by magic ---
$fileClass = 'unknown'
$suggestedRoutes = @()
$suggestedSkills = @()
$ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()

if (Test-Magic $hex '504b0304' -or $ext -eq '.apk' -or $ext -eq '.jar' -or $ext -eq '.crx') {
    if ((Test-Magic $hex '504b0304') -and ($ext -in @('.apk', '.jar', '.crx'))) {
        switch ($ext) {
            '.apk' { $fileClass = 'android-apk'; $suggestedRoutes = @('R1'); $suggestedSkills = @('apk-reverse') }
            '.crx' { $fileClass = 'browser-extension'; $suggestedRoutes = @('R30'); $suggestedSkills = @('browser-extension-reverse') }
            default { $fileClass = 'java-archive'; $suggestedRoutes = @('R1'); $suggestedSkills = @('apk-reverse') }
        }
    } else {
        $fileClass = 'zip-archive'
        $suggestedRoutes = @('R48'); $suggestedSkills = @('stego-analysis')   # zip 常见隐写载体；也提示 CTF zip-archive sidecar
    }
}
elseif (Test-Magic $hex '7f454c46') {
    $fileClass = 'elf-binary'
    $suggestedRoutes = @('R6'); $suggestedSkills = @('ida-reverse')
}
elseif (Test-Magic $hex '4d5a') {
    $fileClass = 'pe-binary'
    $suggestedRoutes = @('R6'); $suggestedSkills = @('ida-reverse')
    # .NET 检测：MZ 后 PE 头里找 CLR 需要深读，这里用扩展名/字符串启发
    $headText = [Text.Encoding]::ASCII.GetString($bytes)
    if ($ext -in @('.dll', '.exe')) {
        $suggestedRoutes += 'R5'; $suggestedSkills += 'dotnet-reverse'
    }
}
elseif (Test-Magic $hex '6465780a') {
    $fileClass = 'android-dex'; $suggestedRoutes = @('R1'); $suggestedSkills = @('apk-reverse')
}
elseif (Test-Magic $hex 'cffaedfe' -or $hex.StartsWith('feedface') -or $hex.StartsWith('cafebabe')) {
    if ($hex.StartsWith('cafebabe')) { $fileClass = 'java-class-or-macho'; $suggestedRoutes = @('R31','R1'); $suggestedSkills = @('macos-reverse','apk-reverse') }
    else { $fileClass = 'mach-o'; $suggestedRoutes = @('R31'); $suggestedSkills = @('macos-reverse') }
}
elseif (Test-Magic $hex '89504e47') {
    $fileClass = 'png-image'; $suggestedRoutes = @('R48'); $suggestedSkills = @('stego-analysis')
}
elseif (Test-Magic $hex 'ffd8ff') {
    $fileClass = 'jpeg-image'; $suggestedRoutes = @('R48'); $suggestedSkills = @('stego-analysis')
}
elseif (Test-Magic $hex '47494638') {
    $fileClass = 'gif-image'; $suggestedRoutes = @('R48'); $suggestedSkills = @('stego-analysis')
}
elseif (Test-Magic $hex '25504446') {
    $fileClass = 'pdf-document'; $suggestedRoutes = @('R48'); $suggestedSkills = @('stego-analysis')
}
elseif (Test-Magic $hex '52617221') {
    $fileClass = 'rar-archive'; $suggestedRoutes = @('R41'); $suggestedSkills = @('ctf-sandbox')
}
elseif (Test-Magic $hex '377abcaf271c') {
    $fileClass = '7z-archive'; $suggestedRoutes = @('R41'); $suggestedSkills = @('ctf-sandbox')
}
elseif (Test-Magic $hex '52494646') {
    $fileClass = 'riff-media(wav/avi)'; $suggestedRoutes = @('R48'); $suggestedSkills = @('stego-analysis')
}
elseif (Test-Magic $hex '0061736d') {
    $fileClass = 'wasm-module'; $suggestedRoutes = @('R0'); $suggestedSkills = @('reverse-engineering')
}
elseif (Test-Magic $hex '1f8b08') {
    $fileClass = 'gzip-stream'; $suggestedRoutes = @('R8'); $suggestedSkills = @('firmware-pentest')
}
elseif ($ext -eq '.pcap' -or $ext -eq '.pcapng') {
    $fileClass = 'packet-capture'; $suggestedRoutes = @('R21'); $suggestedSkills = @('protocol-reverse')
}
elseif ($ext -in @('.bin', '.img', '.rom')) {
    $fileClass = 'raw-firmware-image?'; $suggestedRoutes = @('R8'); $suggestedSkills = @('firmware-pentest')
}

$item = Get-Item -LiteralPath $Path
$sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
$md5 = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash
$sizeKB = [Math]::Round($item.Length / 1KB, 1)

# --- 3) keyword route via master-route when hint given ---
$keywordRouteId = ''
$keywordRouteSkill = ''
if (-not [string]::IsNullOrWhiteSpace($Hint)) {
    $mr = Join-Path $scriptDir 'master-route.ps1'
    $tmpRoute = Join-Path ([IO.Path]::GetTempPath()) ("rsqt-" + [guid]::NewGuid().ToString('n'))
    try {
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $mr -Hint $Hint -OutDir $tmpRoute -ProjectRoot $projectRoot 2>&1
        $scopeFile = Join-Path $tmpRoute 'route-scope.md'
        if (Test-Path $scopeFile) {
            $scopeText = Get-Content $scopeFile -Raw -Encoding UTF8
            if ($scopeText -match '(?m)^- primary:\s*(R\d+)') { $keywordRouteId = $Matches[1] }
            if ($scopeText -match '(?m)^- primary_skill:\s*(\S+)') { $keywordRouteSkill = $Matches[1] }
        }
    } finally {
        Remove-Item -Recurse -Force $tmpRoute -ErrorAction SilentlyContinue
    }
}

# --- 4) tool availability for suggested skills ---
$toolsOk = @(); $toolsMissing = @()
$toolIndexPath = Join-Path $skillsRoot 'tool-index.json'
if (Test-Path -LiteralPath $toolIndexPath) {
    $ti = Get-Content $toolIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($t in @($ti.tools)) {
        if ($t.available -and ($t.skill -in $suggestedSkills)) {
            $toolsOk += ("{0} -> {1}" -f $t.name, $t.resolved_path)
        } elseif (-not $t.available -and ($t.skill -in $suggestedSkills)) {
            $toolsMissing += $t.name
        }
    }
}

# --- 5) write report ---
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutDir = Join-Path (Join-Path $projectRoot 'work') ("quick-triage-{0}" -f $stamp)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# reverse-skill-pro Quick Triage')
[void]$sb.AppendLine(("- created: {0}" -f (Get-Date -Format 'o')))
[void]$sb.AppendLine(("- artifact: {0}" -f (Resolve-Path -LiteralPath $Path)))
[void]$sb.AppendLine(("- size_kb: {0}" -f $sizeKB))
[void]$sb.AppendLine(("- sha256: {0}" -f $sha256))
[void]$sb.AppendLine(("- md5: {0}" -f $md5))
[void]$sb.AppendLine(("- head_hex: {0}" -f $hex.Substring(0, 32)))
[void]$sb.AppendLine(("- head_ascii: {0}" -f $ascii))
[void]$sb.AppendLine(("- file_class: {0}" -f $fileClass))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Suggested routes (by file type)')
foreach ($r in $suggestedRoutes) { [void]$sb.AppendLine(("- {0}" -f $r)) }
if ($suggestedRoutes.Count -eq 0) { [void]$sb.AppendLine('- (unknown type; run master-route with a task hint)') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Keyword route (master-route)')
[void]$sb.AppendLine(("- hint: {0}" -f $Hint))
[void]$sb.AppendLine(("- primary: {0} ({1})" -f $keywordRouteId, $keywordRouteSkill))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Tools for suggested skills')
[void]$sb.AppendLine(("- available: {0}" -f ($(if ($toolsOk.Count) { $toolsOk -join '; ' } else { '(none resolved)' }))))
[void]$sb.AppendLine(("- missing: {0}" -f ($(if ($toolsMissing.Count) { $toolsMissing -join ', ' } else { '(none)' }))))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Next actions')
[void]$sb.AppendLine('1. case-init (auth gate) before touching any network target')
[void]$sb.AppendLine('2. open PRIMARY SKILL.md from the routes above')
[void]$sb.AppendLine('3. missing tools -> bootstrap-reverse (manifest only)')
$utf8 = New-Object System.Text.UTF8Encoding $true
$reportPath = Join-Path $OutDir 'triage.md'
[System.IO.File]::WriteAllText($reportPath, $sb.ToString(), $utf8)

# --- console summary ---
Write-Host ("=== quick-triage: {0} ===" -f $item.Name)
Write-Host ("class={0} size={1}KB" -f $fileClass, $sizeKB)
Write-Host ("sha256={0}" -f $sha256)
Write-Host ("type-routes: {0}" -f ($suggestedRoutes -join ','))
if ($Hint) { Write-Host ("hint-route : {0} ({1})" -f $keywordRouteId, $keywordRouteSkill) }
Write-Host ("tools ok={0} missing={1}" -f $toolsOk.Count, $toolsMissing.Count)
Write-Host ("report -> {0}" -f $reportPath) -ForegroundColor Green
exit 0

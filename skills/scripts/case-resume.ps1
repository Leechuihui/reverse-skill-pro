#Requires -Version 5.1
# reverse-skill-pro: resume an existing case — summarize scope/timeline/workitems/evidence state
# and print the deterministic next actions (no re-materialization of unchanged context).
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File skills/scripts/case-resume.ps1 -CaseRoot work\my-case
#   powershell ... -CaseRoot work\my-case -Last 10     # show last 10 timeline entries
# Exit codes: 0 ok / 2 case not found or invalid
param(
    [Parameter(Mandatory = $true)]
    [string] $CaseRoot,
    [int] $Last = 5,
    [string] $ProjectRoot = ''
)
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$skillsRoot = Split-Path -Parent $scriptDir

if (-not (Test-Path -LiteralPath $CaseRoot)) {
    # try resolving under current project's work/
    . (Join-Path (Join-Path $scriptDir 'lib') 'WorkRoot.ps1')
    $proj = Resolve-ReverseProjectRoot -RequestedRoot $ProjectRoot
    $candidate = Join-Path (Join-Path $proj 'work') $CaseRoot
    if (Test-Path -LiteralPath $candidate) { $CaseRoot = $candidate }
    else {
        Write-Host ("ERROR: case root not found: {0}" -f $CaseRoot) -ForegroundColor Red
        Write-Host 'Pass -CaseRoot <path> or run from the project that owns work\<case>.'
        exit 2
    }
}

$scopePath = Join-Path $CaseRoot 'scope.md'
$timelinePath = Join-Path $CaseRoot 'timeline.md'
$workitemsPath = Join-Path $CaseRoot 'workitems.md'
$evidenceDir = Join-Path $CaseRoot 'evidence'

if (-not (Test-Path -LiteralPath $scopePath)) {
    Write-Host ("ERROR: not a valid case (missing scope.md): {0}" -f $CaseRoot) -ForegroundColor Red
    exit 2
}

function Get-ScopeField([string]$text, [string]$field) {
    if ($text -match ("(?m)^-\s*{0}:\s*(.+)$" -f [regex]::Escape($field))) { return $Matches[1].Trim() }
    return ''
}

$scopeText = Get-Content $scopePath -Raw -Encoding UTF8
$caseId = Get-ScopeField $scopeText 'case_id'
$primaryId = Get-ScopeField $scopeText 'primary_id'
$primarySkill = Get-ScopeField $scopeText 'primary_skill'
$preset = Get-ScopeField $scopeText 'preset'
$authStatus = ''
if ($scopeText -match '(?m)^-\s*status:\s*(\S+)' ) { $authStatus = $Matches[1] }
$readyForAct = ''
if ($scopeText -match '(?m)^-\s*ready_for_act:\s*(\S+)') { $readyForAct = $Matches[1] }
$networkMode = ''
if ($scopeText -match '(?m)^-\s*mode:\s*(\S+)') { $networkMode = $Matches[1] }

# timeline entries: split on "## " headers
$timelineEntries = @()
if (Test-Path -LiteralPath $timelinePath) {
    $tl = Get-Content $timelinePath -Raw -Encoding UTF8
    $matches0 = [regex]::Matches($tl, '(?ms)^## (.+?)$(.*?)(?=^## |\z)')
    foreach ($m in $matches0) {
        $head = $m.Groups[1].Value.Trim()
        $body = $m.Groups[2].Value
        $action = ''; $next = ''; $delta = ''
        if ($body -match '(?m)^-\s*action:\s*(.+)$') { $action = $Matches[1].Trim() }
        if ($body -match '(?m)^-\s*next:\s*(.+)$') { $next = $Matches[1].Trim() }
        if ($body -match '(?m)^-\s*decision_delta:\s*\[(.*)\]') { $delta = $Matches[1].Trim() }
        $timelineEntries += [pscustomobject]@{ Head = $head; Action = $action; Next = $next; Delta = $delta }
    }
}

# workitems status
$wiOpen = @(); $wiDone = 0; $wiTotal = 0
if (Test-Path -LiteralPath $workitemsPath) {
    $wi = Get-Content $workitemsPath -Encoding UTF8
    foreach ($line in $wi) {
        if ($line -match '^\|\s*(WI-\d+)\s*\|') {
            $wiTotal++
            $wiId = $Matches[1]
            if ($line -match '\|\s*(open|in_progress|pending)\s*\|') { $wiOpen += $wiId }
            elseif ($line -match '\|\s*(done|closed|complete)\s*\|') { $wiDone++ }
        }
    }
}

# evidence inventory
$evidenceIds = @()
if (Test-Path -LiteralPath $evidenceDir) {
    $evidenceIds = @(Get-ChildItem -LiteralPath $evidenceDir -Filter 'E-*.md' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
}
$findingsCount = 0
$findingsPath = Join-Path $CaseRoot 'findings.md'
if (Test-Path -LiteralPath $findingsPath) {
    $findingsCount = @([regex]::Matches((Get-Content $findingsPath -Raw -Encoding UTF8), '(?m)^##\s+F-')).Count
}

# --- console summary ---
Write-Host ("=== case-resume: {0} ===" -f $(if ($caseId) { $caseId } else { (Split-Path $CaseRoot -Leaf) }))
Write-Host ("auth={0} ready_for_act={1} network={2} preset={3}" -f $authStatus, $readyForAct, $networkMode, $preset)
Write-Host ("primary={0} ({1})" -f $primaryId, $primarySkill)
Write-Host ("workitems: total={0} open={1} done={2}" -f $wiTotal, $wiOpen.Count, $wiDone)
Write-Host ("evidence: {0} items   findings: {1}" -f $evidenceIds.Count, $findingsCount)

if ($timelineEntries.Count -gt 0) {
    Write-Host ("--- last {0} timeline entries ---" -f [Math]::Min($Last, $timelineEntries.Count))
    foreach ($e in ($timelineEntries | Select-Object -Last $Last)) {
        Write-Host ("[{0}] {1}" -f $e.Head, $e.Action)
        if ($e.Delta) { Write-Host ("    delta: {0}" -f $e.Delta) -ForegroundColor DarkGray }
        if ($e.Next) { Write-Host ("    next : {0}" -f $e.Next) -ForegroundColor Cyan }
    }
}

# --- deterministic next actions ---
Write-Host '--- NEXT ACTIONS ---'
if ($authStatus -ne 'granted') {
    Write-Host '1. auth NOT granted -> fill scope.md auth + in_scope first (MUST before ACT)' -ForegroundColor Yellow
    Write-Host '   network target: re-run case-init with -AuthGranted -TargetUrl <url>'
    Write-Host '   offline sample: re-run with -Preset offline-sample -Sample <path>'
} elseif ($readyForAct -ne 'true') {
    Write-Host '1. complete signoff checklist in scope.md -> set ready_for_act=true' -ForegroundColor Yellow
} else {
    Write-Host ("1. continue PRIMARY skill: skills/{0}" -f $primarySkill)
}
if ($wiOpen.Count -gt 0) {
    Write-Host ("2. finish open workitems: {0}" -f ($wiOpen -join ', '))
}
if ($evidenceIds.Count -gt 0) {
    Write-Host ("3. evidence on file: {0}" -f (($evidenceIds | Select-Object -First 8) -join ', ') )
} else {
    Write-Host '3. no evidence yet -> append via skills/scripts/append-evidence.ps1 as you progress'
}
Write-Host '4. on completion: docs-generator report + field-journal write-back'
exit 0

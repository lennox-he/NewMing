param(
    [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameVersion = "1.13.9"
)

$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Test-RequiredPath {
    param([string]$RelativePath)
    $path = Join-Path $ModRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing required path: $RelativePath"
    }
}

function Test-ForbiddenPath {
    param([string]$RelativePath)
    $path = Join-Path $ModRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Failure "Forbidden first-stage path exists: $RelativePath"
    }
}

function Get-FileCount {
    param([string]$RelativePath)
    $path = Join-Path $ModRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        return 0
    }
    return (Get-ChildItem -Recurse -File -LiteralPath $path | Measure-Object).Count
}

$descriptor = Join-Path $ModRoot "descriptor.mod"
Test-RequiredPath "descriptor.mod"
if (Test-Path -LiteralPath $descriptor) {
    $descriptorText = Get-Content -Raw -LiteralPath $descriptor
    if ($descriptorText -notmatch 'name="NewMing"') {
        Add-Failure 'descriptor.mod name must be "NewMing"'
    }
    if ($descriptorText -notmatch ('supported_version="' + [regex]::Escape($GameVersion) + '"')) {
        Add-Failure "descriptor.mod supported_version must be $GameVersion"
    }
    if ($descriptorText -match 'supported_version="1\.12\.\*"') {
        Add-Failure "descriptor.mod still targets Age Of Ming workshop version 1.12.*"
    }
}

$requiredPaths = @(
    "map_data\provinces.png",
    "map_data\state_regions",
    "gfx\map",
    "gfx\models\portraits",
    "gfx\portraits",
    "common\genes",
    "common\dna_data",
    "common\scripted_triggers",
    "common\strategic_regions",
    "common\state_traits",
    "common\history\states",
    "common\history\pops",
    "common\history\buildings",
    "common\history\countries",
    "common\country_definitions",
    "common\cultures",
    "common\religions",
    "common\flag_definitions",
    "common\coat_of_arms",
    "localization\simp_chinese"
)

foreach ($relativePath in $requiredPaths) {
    Test-RequiredPath $relativePath
}

$minimumFileCounts = @{
    "map_data\state_regions" = 6
    "gfx\models\portraits" = 400
    "gfx\portraits" = 10
    "common\history\states" = 1
    "common\history\pops" = 5
    "common\history\buildings" = 1
    "common\scripted_triggers" = 10
}

foreach ($entry in $minimumFileCounts.GetEnumerator()) {
    $count = Get-FileCount $entry.Key
    if ($count -lt $entry.Value) {
        Add-Failure "Too few files under $($entry.Key): expected at least $($entry.Value), got $count"
    }
}

$forbiddenPaths = @(
    "events",
    "common\journal_entries",
    "common\decisions",
    "common\scripted_buttons",
    "common\scripted_progress_bars"
)

foreach ($relativePath in $forbiddenPaths) {
    Test-ForbiddenPath $relativePath
}

$scriptExtensions = @(".txt", ".mod", ".asset")
$textFiles = Get-ChildItem -Recurse -File -LiteralPath $ModRoot |
    Where-Object {
        $_.FullName -notmatch '\\.git\\' -and
        $scriptExtensions -contains $_.Extension
    }

foreach ($file in $textFiles) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    $left = ([regex]::Matches($text, '\{')).Count
    $right = ([regex]::Matches($text, '\}')).Count
    if ($left -ne $right) {
        $relative = $file.FullName.Substring($ModRoot.Length).TrimStart('\')
        Add-Failure "Brace count mismatch in ${relative}: {=$left }=$right"
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures.Count) validation issue(s)."
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host "OK: NewMing first-stage static validation passed for Victoria 3 $GameVersion."

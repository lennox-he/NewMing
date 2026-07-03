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

function Get-RelativePath {
    param([string]$FullName)
    return $FullName.Substring($ModRoot.Length).TrimStart('\')
}

function Test-NoPatternInFiles {
    param(
        [string]$RelativePath,
        [string]$Filter,
        [string]$Pattern,
        [string]$FailurePrefix
    )

    $path = Join-Path $ModRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $matches = Get-ChildItem -Recurse -File -Filter $Filter -LiteralPath $path |
        Select-String -Pattern $Pattern -CaseSensitive

    foreach ($match in $matches) {
        $relative = Get-RelativePath $match.Path
        Add-Failure "${FailurePrefix}: ${relative}:$($match.LineNumber)"
    }
}

function Test-LocalizationColonSeparators {
    $path = Join-Path $ModRoot "localization"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $files = Get-ChildItem -Recurse -File -Filter "*.yml" -LiteralPath $path
    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            if ($line -match '^\s*[^#\s][^:]*$') {
                $relative = Get-RelativePath $file.FullName
                Add-Failure "Localization line missing colon: ${relative}:$lineNumber"
            }
        }
    }
}

function Test-GeneAccessoryStructure {
    $path = Join-Path $ModRoot "common\genes"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $files = Get-ChildItem -Recurse -File -Filter "*.txt" -LiteralPath $path
    foreach ($file in $files) {
        $depth = 0
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            if (($depth -lt 4) -and ($line -match '^\s*(index|male|female|boy|girl)\s*=')) {
                $relative = Get-RelativePath $file.FullName
                Add-Failure "Accessory gene option appears above gene entry level: ${relative}:$lineNumber"
            }
            $depth += ([regex]::Matches($line, '\{')).Count
            $depth -= ([regex]::Matches($line, '\}')).Count
        }
    }
}

function Test-AccessoryVariationTopLevelBlocks {
    $path = Join-Path $ModRoot "gfx\portraits\accessory_variations"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $allowedTopLevelBlocks = @("pattern_textures", "pattern_layout", "variation")
    $files = Get-ChildItem -Recurse -File -Filter "*.txt" -LiteralPath $path
    foreach ($file in $files) {
        $depth = 0
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            if (($depth -eq 0) -and ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*\{')) {
                $blockName = $Matches[1]
                if ($allowedTopLevelBlocks -notcontains $blockName) {
                    $relative = Get-RelativePath $file.FullName
                    Add-Failure "Unexpected top-level block in accessory variation file: ${relative}:$lineNumber ($blockName)"
                }
            }
            $depth += ([regex]::Matches($line, '\{')).Count
            $depth -= ([regex]::Matches($line, '\}')).Count
        }
    }
}

function Test-PortraitPatternMaskPaths {
    $path = Join-Path $ModRoot "gfx\models\portraits\attachments"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $files = Get-ChildItem -Recurse -File -Filter "*.asset" -LiteralPath $path
    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            $match = [regex]::Match($line, 'pattern_mask\s*=\s*"([^"]+)"')
            if (-not $match.Success) {
                continue
            }
            $maskPath = $match.Groups[1].Value
            if ($maskPath -like "gfx/models/portraits/f_clothes/*") {
                $localPath = Join-Path $ModRoot ($maskPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                    $relative = Get-RelativePath $file.FullName
                    Add-Failure "Portrait pattern mask path is missing from mod VFS: ${relative}:$lineNumber -> $maskPath"
                }
            }
        }
    }
}

function Test-NoDirectCommanderUsageTrigger {
    $path = Join-Path $ModRoot "common\character_templates"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $files = Get-ChildItem -Recurse -File -Filter "*.txt" -LiteralPath $path
    foreach ($file in $files) {
        $depth = 0
        $commanderUsageDepth = $null
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            if (($null -ne $commanderUsageDepth) -and ($depth -eq $commanderUsageDepth) -and ($line -match '^\s*OR\s*=\s*\{')) {
                $relative = Get-RelativePath $file.FullName
                Add-Failure "commander_usage country condition must be wrapped in country_trigger: ${relative}:$lineNumber"
            }
            if ($line -match '^\s*commander_usage\s*=\s*\{') {
                $commanderUsageDepth = $depth + 1
            }
            $depth += ([regex]::Matches($line, '\{')).Count
            $depth -= ([regex]::Matches($line, '\}')).Count
            if (($null -ne $commanderUsageDepth) -and ($depth -lt $commanderUsageDepth)) {
                $commanderUsageDepth = $null
            }
        }
    }
}

function Test-NoAddClaimInsideCreateState {
    $path = Join-Path $ModRoot "common\history\states"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $files = Get-ChildItem -Recurse -File -Filter "*.txt" -LiteralPath $path
    foreach ($file in $files) {
        $depth = 0
        $createStateDepth = $null
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName) {
            $lineNumber++
            if (($null -ne $createStateDepth) -and ($depth -ge $createStateDepth) -and ($line -match '^\s*add_claim\s*=')) {
                $relative = Get-RelativePath $file.FullName
                Add-Failure "add_claim must not be inside create_state: ${relative}:$lineNumber"
            }
            if ($line -match '^\s*create_state\s*=\s*\{') {
                $createStateDepth = $depth + 1
            }
            $depth += ([regex]::Matches($line, '\{')).Count
            $depth -= ([regex]::Matches($line, '\}')).Count
            if (($null -ne $createStateDepth) -and ($depth -lt $createStateDepth)) {
                $createStateDepth = $null
            }
        }
    }
}

function Get-GitTrackedFiles {
    $gitOutput = & git -C $ModRoot ls-files 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Unable to list Git tracked files: $gitOutput"
        return @()
    }
    return @($gitOutput | Where-Object { $_ -ne "" })
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

Test-NoPatternInFiles `
    -RelativePath "common\history\countries" `
    -Filter "*.txt" `
    -Pattern '\b(add_journal_entry|trigger_event)\b' `
    -FailurePrefix "Forbidden first-stage startup trigger in history countries"

Test-NoPatternInFiles `
    -RelativePath "common\history\states" `
    -Filter "*.txt" `
    -Pattern '\bC:[A-Za-z0-9_]+\b' `
    -FailurePrefix "Uppercase country scope in history states"

Test-LocalizationColonSeparators
Test-GeneAccessoryStructure
Test-AccessoryVariationTopLevelBlocks
Test-PortraitPatternMaskPaths
Test-NoDirectCommanderUsageTrigger
Test-NoAddClaimInsideCreateState

Test-NoPatternInFiles `
    -RelativePath "common\interest_groups" `
    -Filter "*.txt" `
    -Pattern '^\s*commander_leader_chance\s*=' `
    -FailurePrefix "Obsolete interest group commander leader field"

Test-NoPatternInFiles `
    -RelativePath "common\power_bloc_principles" `
    -Filter "*.txt" `
    -Pattern '^\s*(on_enact|immediate)\s*=' `
    -FailurePrefix "Unsupported power bloc principle effect slot"

$trackedFiles = Get-GitTrackedFiles
$maxTrackedFileBytes = 100MB
foreach ($relativePath in $trackedFiles) {
    $localRelativePath = $relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $path = [System.IO.Path]::Combine($ModRoot, $localRelativePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $file = Get-Item -LiteralPath $path
    if ($file.Length -gt $maxTrackedFileBytes) {
        Add-Failure "Git tracked file exceeds 100MB: $relativePath ($($file.Length) bytes)"
    }
}

$trackedDocs = @($trackedFiles | Where-Object { $_ -eq "docs" -or $_ -like "docs/*" })
if ($trackedDocs.Count -gt 0) {
    foreach ($relativePath in $trackedDocs) {
        Add-Failure "docs/ must not be Git tracked: $relativePath"
    }
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

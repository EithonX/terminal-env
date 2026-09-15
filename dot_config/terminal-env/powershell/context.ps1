function ConvertTo-TerminalEnvTrimmedString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function Test-TerminalEnvMetadataValueSafe {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    $text = ([string]$Value).Trim()
    if (-not $text -or $text.Length -gt 256) { return $false }
    foreach ($ch in $text.ToCharArray()) {
        if ([char]::IsControl($ch)) { return $false }
    }
    return $true
}

function ConvertTo-TerminalEnvDisplayText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $out = [Text.StringBuilder]::new()
    foreach ($ch in ([string]$Value).ToCharArray()) {
        if ([char]::IsControl($ch)) { [void]$out.Append('?') } else { [void]$out.Append($ch) }
    }
    return $out.ToString()
}

function Get-TerminalEnvPhysicalPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    try { return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { return $Path }
}

function Test-TerminalEnvPathInside {
    param([string]$Path, [string]$Root)
    if (-not $Path -or -not $Root) { return $false }
    try {
        $p = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $r = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        if ($p.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        return $p.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            $p.StartsWith($r + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-TerminalEnvSearchDirs {
    param([string]$Cwd, [string]$Root)
    $dirs = [Collections.Generic.List[string]]::new()
    $current = [IO.DirectoryInfo]::new($Cwd)
    while ($null -ne $current) {
        $dirs.Add($current.FullName)
        if ($current.FullName.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $current.Parent
    }
    return @($dirs)
}

function Get-TerminalEnvFirstValueLine {
    param([string]$Path)
    foreach ($line in [IO.File]::ReadLines($Path)) {
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        return $value
    }
    return ''
}

function Get-TerminalEnvTomlValue {
    param([string]$Path, [string]$Section, [string]$Key)
    $inside = $false
    foreach ($rawLine in [IO.File]::ReadLines($Path)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([^\]]+)\]\s*$') {
            $inside = $Matches[1] -eq $Section
            continue
        }
        if (-not $inside) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $name = $line.Substring(0, $eq).Trim().Trim('"', "'")
        if ($name -ne $Key) { continue }
        $value = $line.Substring($eq + 1).Trim()
        if ($value.Length -lt 2) { return '' }
        $quote = $value[0]
        if ($quote -ne '"' -and $quote -ne "'") { return '' }
        $out = [Text.StringBuilder]::new()
        $escaped = $false
        for ($i = 1; $i -lt $value.Length; $i++) {
            $ch = $value[$i]
            if ($quote -eq '"' -and $escaped) {
                [void]$out.Append($ch)
                $escaped = $false
                continue
            }
            if ($quote -eq '"' -and $ch -eq '\') {
                $escaped = $true
                continue
            }
            if ($ch -eq $quote) { return $out.ToString() }
            [void]$out.Append($ch)
        }
        return ''
    }
    return ''
}
function Get-TerminalEnvNearestTomlValue {
    param([string[]]$Dirs, [string]$FileName, [string]$Section, [string]$Key)
    foreach ($dir in $Dirs) {
        $path = Join-Path $dir $FileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $value = Get-TerminalEnvTomlValue -Path $path -Section $Section -Key $Key
        if ($value) { return [pscustomobject]@{ value = $value; source = $path } }
    }
    return $null
}

function Get-TerminalEnvNearestToolVersion {
    param([string[]]$Dirs, [ValidateSet('node','python','go','rust')][string]$Tool)
    foreach ($dir in $Dirs) {
        $path = Join-Path $dir '.tool-versions'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        foreach ($rawLine in [IO.File]::ReadLines($path)) {
            $line = $rawLine.Trim()
            if (-not $line -or $line.StartsWith('#')) { continue }
            $parts = @($line -split '\s+' | Where-Object { $_ })
            if ($parts.Count -lt 2) { continue }
            $matches = switch ($Tool) {
                node { $parts[0] -in @('node','nodejs') }
                python { $parts[0] -eq 'python' }
                go { $parts[0] -in @('go','golang') }
                rust { $parts[0] -eq 'rust' }
            }
            if ($matches) { return [pscustomobject]@{ value = $parts[1]; source = $path; kind = 'tool-versions' } }
        }
    }
    return $null
}

function Get-TerminalEnvMiseSelectors {
    param([string[]]$Dirs, [ValidateSet('node','python','go','rust')][string]$Tool)
    foreach ($dir in $Dirs) {
        $results = [Collections.Generic.List[object]]::new()
        foreach ($fileName in '.mise.toml','mise.toml') {
            $path = Join-Path $dir $fileName
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $keys = switch ($Tool) {
                node { @('node','nodejs') }
                python { @('python') }
                go { @('go','golang') }
                rust { @('rust') }
            }
            foreach ($key in $keys) {
                $value = Get-TerminalEnvTomlValue -Path $path -Section 'tools' -Key $key
                if ($value) {
                    $results.Add([pscustomobject]@{ value = $value; source = $path; kind = "mise:$key" })
                    break
                }
            }
        }
        if ($results.Count -gt 0) { return @($results) }
    }
    return @()
}

function ConvertTo-TerminalEnvSelectorValue {
    param([string]$Tool, [string]$Value)
    $v = $Value.Trim()
    switch ($Tool) {
        node { $v = $v -replace '^v(?=\d)', '' }
        go { $v = $v -replace '^go(?=\d)', '' }
        python { $v = $v -replace '^python-', '' }
    }
    return $v
}

function Test-TerminalEnvNumericSelector {
    param([string]$Tool, [string]$Value)
    $v = ConvertTo-TerminalEnvSelectorValue -Tool $Tool -Value $Value
    return $v -match '^\d+(\.\d+){0,3}([+-][0-9A-Za-z.-]+)?$'
}

function Test-TerminalEnvSelectorCompatible {
    param([string]$Tool, [string]$A, [string]$B)
    $aValue = ConvertTo-TerminalEnvSelectorValue -Tool $Tool -Value $A
    $bValue = ConvertTo-TerminalEnvSelectorValue -Tool $Tool -Value $B
    if ($aValue -eq $bValue) { return $true }
    if ((Test-TerminalEnvNumericSelector -Tool $Tool -Value $aValue) -and (Test-TerminalEnvNumericSelector -Tool $Tool -Value $bValue)) {
        return $aValue.StartsWith($bValue + '.', [StringComparison]::Ordinal) -or
            $bValue.StartsWith($aValue + '.', [StringComparison]::Ordinal)
    }
    return $false
}

function Test-TerminalEnvSelectorsCompatible {
    param([string]$Tool, [string]$A, [string]$KindA, [string]$B, [string]$KindB)
    if (Test-TerminalEnvSelectorCompatible -Tool $Tool -A $A -B $B) { return $true }
    if ($Tool -eq 'go' -and
        (Test-TerminalEnvNumericSelector -Tool go -Value $A) -and
        (Test-TerminalEnvNumericSelector -Tool go -Value $B)) {
        $aValue = ConvertTo-TerminalEnvSelectorValue -Tool go -Value $A
        $bValue = ConvertTo-TerminalEnvSelectorValue -Tool go -Value $B
        if ($KindA -eq 'go-toolchain' -and $KindB -eq 'go-toolchain') { return $true }
        if ($KindA -eq 'go-toolchain') { return (Test-TerminalEnvVersionAtLeast -Active $bValue -Minimum $aValue) }
        if ($KindB -eq 'go-toolchain') { return (Test-TerminalEnvVersionAtLeast -Active $aValue -Minimum $bValue) }
    }
    return $false
}

function Get-TerminalEnvSelectorStatus {
    param([string]$Tool, [string]$Selector, [string]$Kind, [string]$Active)
    if (-not $Active -or -not (Test-TerminalEnvNumericSelector -Tool $Tool -Value $Selector)) { return 'unknown' }
    $matches = if ($Tool -eq 'go' -and $Kind -eq 'go-toolchain') {
        Test-TerminalEnvVersionAtLeast -Active $Active -Minimum (ConvertTo-TerminalEnvSelectorValue -Tool go -Value $Selector)
    } else {
        Test-TerminalEnvSelectorCompatible -Tool $Tool -A $Active -B $Selector
    }
    if ($matches) { return 'satisfied' }
    return 'mismatch'
}

function Get-TerminalEnvVersionParts {
    param([string]$Value)
    $v = $Value -replace '^v(?=\d)', '' -replace '^go(?=\d)', ''
    $v = ($v -split '[-+]')[0]
    $parts = @($v -split '\.')
    while ($parts.Count -lt 4) { $parts += '0' }
    return @(0..3 | ForEach-Object { if ($parts[$_] -match '^\d+$') { [int64]$parts[$_] } else { [int64]0 } })
}

function Test-TerminalEnvVersionAtLeast {
    param([string]$Active, [string]$Minimum)
    $a = Get-TerminalEnvVersionParts $Active
    $b = Get-TerminalEnvVersionParts $Minimum
    for ($i = 0; $i -lt 4; $i++) {
        if ($a[$i] -gt $b[$i]) { return $true }
        if ($a[$i] -lt $b[$i]) { return $false }
    }
    return $true
}

function Get-TerminalEnvSimpleMinimum {
    param([string]$Tool, [string]$Constraint)
    $raw = $Constraint.Trim()
    if ($raw -match '^>=\s*(\d+(?:\.\d+){0,3})\s*$') { return $Matches[1] }
    if ($Tool -in @('go','rust') -and $raw -match '^(\d+(?:\.\d+){0,3})$') { return $Matches[1] }
    return ''
}

function Get-TerminalEnvConstraintStatus {
    param([string]$Tool, [string]$Constraint, [string]$Active)
    if (-not $Active) { return '' }
    $raw = $Constraint.Trim()
    $minimum = Get-TerminalEnvSimpleMinimum -Tool $Tool -Constraint $raw
    if ($minimum) { if (Test-TerminalEnvVersionAtLeast -Active $Active -Minimum $minimum) { return 'satisfied' }; return 'mismatch' }
    if ($Tool -eq 'node' -and $raw -match '^\d+(?:\.\d+){0,3}$') {
        if (Test-TerminalEnvSelectorCompatible -Tool node -A $Active -B $raw) { return 'satisfied' }; return 'mismatch'
    }
    return 'unknown'
}

function Get-TerminalEnvConstraintPrompt {
    param([string]$Tool, [string]$Constraint)
    $raw = $Constraint.Trim()
    $minimum = Get-TerminalEnvSimpleMinimum -Tool $Tool -Constraint $raw
    if ($minimum) { return "≥$minimum" }
    if ($Tool -eq 'node' -and $raw -match '^\d+(?:\.\d+){0,3}$') { return "$raw.x" }
    return $raw.Replace('>=','≥').Replace('<=','≤')
}

function Get-TerminalEnvShortActive {
    param([string]$Tool, [string]$Active, [string]$Selector = '')
    $parts = @((($Active -replace '^v(?=\d)', '' -replace '^go(?=\d)', '') -split '[-+]')[0] -split '\.')
    $count = if ($Selector -and (Test-TerminalEnvNumericSelector -Tool $Tool -Value $Selector)) {
        [Math]::Min(3, ((ConvertTo-TerminalEnvSelectorValue -Tool $Tool -Value $Selector) -split '\.').Count)
    } elseif ($Tool -eq 'node') { 1 } else { 2 }
    return ($parts | Select-Object -First $count) -join '.'
}

function Add-TerminalEnvSelector {
    param([Collections.Generic.List[object]]$List, [string]$Value, [string]$Kind, [string]$Source)
    $valueText = $Value.Trim()
    if (Test-TerminalEnvMetadataValueSafe $valueText) { $List.Add([pscustomobject]@{ value = $valueText; kind = $Kind; source = $Source }) }
}

function Get-TerminalEnvCommandInfo {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) { continue }
        $source = if ($command.Path) { $command.Path } elseif ($command.Source) { $command.Source } else { '' }
        if ($source -match '(?i)\\WindowsApps\\python(?:3)?\.exe$') { continue }
        return [pscustomobject]@{ command = $command; path = $source }
    }
    return $null
}

function Invoke-TerminalEnvRuntimeVersionCommand {
    param([object]$CommandInfo, [string]$Tool)
    if ($null -eq $CommandInfo) { return '' }
    $miseNames = @('MISE_OFFLINE','MISE_AUTO_INSTALL','MISE_NOT_FOUND_AUTO_INSTALL','MISE_EXEC_AUTO_INSTALL','MISE_NO_HOOKS')
    $miseOld = @{}
    foreach ($name in $miseNames) {
        $miseOld[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        $env:MISE_OFFLINE = 'true'
        $env:MISE_AUTO_INSTALL = 'false'
        $env:MISE_NOT_FOUND_AUTO_INSTALL = 'false'
        $env:MISE_EXEC_AUTO_INSTALL = 'false'
        $env:MISE_NO_HOOKS = '1'
        switch ($Tool) {
            node { return ((& $CommandInfo.path --version 2>$null | Select-Object -First 1) -replace '^v', '').Trim() }
            python {
                $line = (& $CommandInfo.path --version 2>&1 | Select-Object -First 1)
                if ($line -match '^Python\s+(.+)$') { return $Matches[1].Trim() }
            }
            go {
                $old = $env:GOTOOLCHAIN
                try {
                    $env:GOTOOLCHAIN = 'local'
                    $line = (& $CommandInfo.path version 2>$null | Select-Object -First 1)
                    if ($line -match '\bgo(\d+(?:\.\d+)+(?:[-+][^\s]+)?)\b') { return $Matches[1] }
                } finally {
                    if ($null -eq $old) { Remove-Item Env:GOTOOLCHAIN -ErrorAction SilentlyContinue } else { $env:GOTOOLCHAIN = $old }
                }
            }
            rust {
                $old = $env:RUSTUP_AUTO_INSTALL
                try {
                    $env:RUSTUP_AUTO_INSTALL = '0'
                    $line = (& $CommandInfo.path --version 2>$null | Select-Object -First 1)
                    if ($line -match '^rustc\s+([^\s]+)') { return $Matches[1] }
                } finally {
                    if ($null -eq $old) { Remove-Item Env:RUSTUP_AUTO_INSTALL -ErrorAction SilentlyContinue } else { $env:RUSTUP_AUTO_INSTALL = $old }
                }
            }
        }
    } catch {
        return ''
    } finally {
        foreach ($name in $miseNames) {
            $oldValue = $miseOld[$name]
            if ($null -eq $oldValue) { Remove-Item ("Env:" + $name) -ErrorAction SilentlyContinue } else { Set-Item ("Env:" + $name) $oldValue }
        }
    }
    return ''
}
function Get-TerminalEnvDisplaySource {
    param([string]$Source, [string]$Root)
    if (Test-TerminalEnvPathInside -Path $Source -Root $Root) {
        if ($Source.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { return '.' }
        try { return (ConvertTo-TerminalEnvDisplayText ([IO.Path]::GetRelativePath($Root, $Source))) } catch {}
    }
    return (ConvertTo-TerminalEnvDisplayText $Source)
}

function Resolve-TerminalEnvTool {
    param(
        [ValidateSet('node','python','go','rust')][string]$Tool,
        [object[]]$Selectors,
        [AllowNull()][object]$Constraint,
        [AllowNull()][object]$ActiveInfo,
        [AllowNull()][string]$ActiveVersion,
        [AllowNull()][string]$Note
    )
    $selectors = @($Selectors)
    if ($selectors.Count -eq 0 -and $null -eq $Constraint) { return $null }

    $conflict = $false
    for ($i = 0; $i -lt $selectors.Count; $i++) {
        for ($j = $i + 1; $j -lt $selectors.Count; $j++) {
            if (-not (Test-TerminalEnvSelectorsCompatible -Tool $Tool -A $selectors[$i].value -KindA $selectors[$i].kind -B $selectors[$j].value -KindB $selectors[$j].kind)) {
                $conflict = $true
            }
        }
    }

    $selected = $null
    if ($selectors.Count) {
        $selected = $selectors[0]
        foreach ($candidate in $selectors) {
            if (-not (Test-TerminalEnvNumericSelector -Tool $Tool -Value $candidate.value)) { continue }
            if ($Tool -eq 'go') {
                if ($selected.kind -eq 'go-toolchain' -and $candidate.kind -ne 'go-toolchain') {
                    $selected = $candidate
                    continue
                }
                $sameSelectionClass = ($selected.kind -eq $candidate.kind) -or ($selected.kind -ne 'go-toolchain' -and $candidate.kind -ne 'go-toolchain')
                if (-not $sameSelectionClass) { continue }
            }
            if (-not (Test-TerminalEnvNumericSelector -Tool $Tool -Value $selected.value) -or $candidate.value.Length -gt $selected.value.Length) {
                $selected = $candidate
            }
        }
    }

    $active = if (Test-TerminalEnvMetadataValueSafe $ActiveVersion) { $ActiveVersion } else { '' }
    $activeInfo = $ActiveInfo
    $noteText = if ($Note) { $Note } else { '' }
    if ($Tool -eq 'go' -and $active) {
        $goMode = if ($env:GOTOOLCHAIN) { $env:GOTOOLCHAIN } else { 'auto' }
        if ($goMode -ne 'local') {
            if ($goMode -ne 'auto') {
                $noteText = "GOTOOLCHAIN=$goMode can select a different Go toolchain; active runtime was not resolved to avoid automatic toolchain changes"
                $active = ''
                $activeInfo = $null
            } else {
                $needed = ''
                foreach ($candidate in $selectors) {
                    if ($candidate.kind -ne 'go-toolchain' -or -not (Test-TerminalEnvNumericSelector -Tool go -Value $candidate.value)) { continue }
                    $candidateNeeded = ConvertTo-TerminalEnvSelectorValue -Tool go -Value $candidate.value
                    if (-not $needed -or (Test-TerminalEnvVersionAtLeast -Active $candidateNeeded -Minimum $needed)) { $needed = $candidateNeeded }
                }
                if ($null -ne $Constraint) {
                    $minimum = Get-TerminalEnvSimpleMinimum -Tool go -Constraint $Constraint.value
                    if ($minimum -and (-not $needed -or (Test-TerminalEnvVersionAtLeast -Active $minimum -Minimum $needed))) { $needed = $minimum }
                }
                if ($needed -and -not (Test-TerminalEnvVersionAtLeast -Active $active -Minimum $needed)) {
                    $noteText = "local Go $active is older than project context; automatic toolchain selection may choose another installed or downloadable toolchain"
                    $active = ''
                    $activeInfo = $null
                }
            }
        }
    }

    $missing = $false
    $selectorMismatch = $false
    $selectorStatus = ''
    $constraintMismatch = $false
    $constraintStatus = ''
    if (-not $conflict -and -not $noteText) {
        if ($selectors.Count) {
            if (-not $active) { $missing = $true }
            else {
                $selectorStatus = Get-TerminalEnvSelectorStatus -Tool $Tool -Selector $selected.value -Kind $selected.kind -Active $active
                if ($selectorStatus -eq 'mismatch') { $selectorMismatch = $true }
            }
        }
        if ($active -and $null -ne $Constraint) {
            $constraintStatus = Get-TerminalEnvConstraintStatus -Tool $Tool -Constraint $Constraint.value -Active $active
            if ($constraintStatus -eq 'mismatch') { $constraintMismatch = $true }
        }
    }
    $mismatch = $selectorMismatch -or $constraintMismatch

    $label = @{ node = 'node'; python = 'py'; go = 'go'; rust = 'rust' }[$Tool]
    $state = 'normal'
    if ($conflict) {
        $prompt = "$label !"
        $state = 'warning'
    } elseif ($selectors.Count) {
        $selectedText = ConvertTo-TerminalEnvSelectorValue -Tool $Tool -Value $selected.value
        if ($missing) { $prompt = "$label $selectedText · missing"; $state = 'warning' }
        elseif ($selectorMismatch) { $prompt = "$label $(Get-TerminalEnvShortActive -Tool $Tool -Active $active -Selector $selected.value) ≠ $selectedText"; $state = 'warning' }
        elseif ($constraintMismatch) { $prompt = "$label $(Get-TerminalEnvShortActive -Tool $Tool -Active $active) < $(Get-TerminalEnvConstraintPrompt -Tool $Tool -Constraint $Constraint.value)"; $state = 'warning' }
        else { $prompt = "$label $selectedText" }
    } else {
        $constraintText = Get-TerminalEnvConstraintPrompt -Tool $Tool -Constraint $Constraint.value
        if ($constraintMismatch) { $prompt = "$label $(Get-TerminalEnvShortActive -Tool $Tool -Active $active) < $constraintText"; $state = 'warning' }
        else { $prompt = "$label $constraintText" }
    }
    if ($noteText) {
        $state = 'warning'
        if ($prompt) { $prompt += ' · active?' }
    }

    $selectorObject = if ($null -ne $selected -and -not $conflict) {
        [ordered]@{ value = $selected.value; kind = $selected.kind; source = $selected.source }
    } else { $null }
    $activeObject = if ($active) { [ordered]@{ version = $active; path = $activeInfo.path; kind = 'path' } } else { $null }
    return [pscustomobject][ordered]@{
        selectors = @($selectors | ForEach-Object { [ordered]@{ value = $_.value; kind = $_.kind; source = $_.source } })
        selector = $selectorObject
        selector_status = if ($selectorStatus) { $selectorStatus } else { $null }
        constraint = if ($null -ne $Constraint) { [ordered]@{ value = $Constraint.value; kind = $Constraint.kind; source = $Constraint.source } } else { $null }
        constraint_status = if ($constraintStatus) { $constraintStatus } else { $null }
        active = $activeObject
        conflict = [bool]$conflict
        missing = [bool]$missing
        mismatch = [bool]$mismatch
        prompt = $prompt
        state = $state
        note = if ($noteText) { $noteText } else { $null }
    }
}

function Resolve-TerminalEnvContext {
    param([string]$Cwd = (Get-Location).Path, [switch]$PromptOnly)
    $cwdPath = Get-TerminalEnvPhysicalPath $Cwd
    if (-not (Test-Path -LiteralPath $cwdPath -PathType Container)) { throw "Not a directory: $Cwd" }
    $git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    $repoRoot = ''
    if ($null -ne $git) {
        try { $repoRoot = (& $git.Path -C $cwdPath rev-parse --show-toplevel 2>$null | Select-Object -First 1).Trim() } catch {}
    }
    if ($repoRoot -and (Test-Path -LiteralPath $repoRoot -PathType Container)) {
        $root = Get-TerminalEnvPhysicalPath $repoRoot
        $repoName = Split-Path -Leaf $root
        $branch = ''; $commit = ''
        if (-not $PromptOnly) {
            try { $branch = (& $git.Path -C $cwdPath symbolic-ref --quiet --short HEAD 2>$null | Select-Object -First 1).Trim() } catch {}
            try { $commit = (& $git.Path -C $cwdPath rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim() } catch {}
        }
        $repo = [ordered]@{ name = $repoName; root = $root; branch = if ($branch) { $branch } else { $null }; detached = [bool](-not $PromptOnly -and -not $branch); commit = if ($commit) { $commit } else { $null } }
    } else {
        $root = $cwdPath
        $repo = [ordered]@{ name = $null; root = $null; branch = $null; detached = $false; commit = $null }
    }
    $dirs = Get-TerminalEnvSearchDirs -Cwd $cwdPath -Root $root

    $nodeSelectors = [Collections.Generic.List[object]]::new()
    foreach ($name in '.nvmrc','.node-version') {
        foreach ($dir in $dirs) {
            $path = Join-Path $dir $name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $value = Get-TerminalEnvFirstValueLine $path
            if ($value) { Add-TerminalEnvSelector -List $nodeSelectors -Value $value -Kind $name.TrimStart('.') -Source $path }
            break
        }
    }
    $toolVersion = Get-TerminalEnvNearestToolVersion -Dirs $dirs -Tool node
    if ($null -ne $toolVersion) { $nodeSelectors.Add($toolVersion) }
    foreach ($item in Get-TerminalEnvMiseSelectors -Dirs $dirs -Tool node) { $nodeSelectors.Add($item) }
    $nodeConstraint = $null
    foreach ($dir in $dirs) {
        $path = Join-Path $dir 'package.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
        if ($raw -notmatch '"(engines|devEngines)"\s*:') { continue }
        try { $pkg = $raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $found = $false
        if ($null -ne $pkg.devEngines -and $null -ne $pkg.devEngines.runtime) {
            foreach ($runtime in @($pkg.devEngines.runtime)) {
                if ($runtime.name -eq 'node' -and $runtime.version -and (Test-TerminalEnvMetadataValueSafe ([string]$runtime.version))) {
                    Add-TerminalEnvSelector -List $nodeSelectors -Value ([string]$runtime.version) -Kind 'package-devEngines' -Source $path
                    $found = $true
                }
            }
        }
        if ($null -ne $pkg.engines -and $pkg.engines.node -and ([string]$pkg.engines.node).Trim() -ne '*') {
            $candidateConstraint = ([string]$pkg.engines.node).Trim()
            if (Test-TerminalEnvMetadataValueSafe $candidateConstraint) {
                $nodeConstraint = [pscustomobject]@{ value = $candidateConstraint; kind = 'package-engines'; source = $path }
                $found = $true
            }
        }
        if ($found) { break }
    }

    $pythonSelectors = [Collections.Generic.List[object]]::new()
    foreach ($dir in $dirs) {
        $path = Join-Path $dir '.python-version'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $value = Get-TerminalEnvFirstValueLine $path
        if ($value) { Add-TerminalEnvSelector -List $pythonSelectors -Value (($value -split '\s+')[0]) -Kind 'python-version' -Source $path }
        break
    }
    $toolVersion = Get-TerminalEnvNearestToolVersion -Dirs $dirs -Tool python
    if ($null -ne $toolVersion) { $pythonSelectors.Add($toolVersion) }
    foreach ($item in Get-TerminalEnvMiseSelectors -Dirs $dirs -Tool python) { $pythonSelectors.Add($item) }
    $pythonConstraint = $null
    $foundToml = Get-TerminalEnvNearestTomlValue -Dirs $dirs -FileName 'pyproject.toml' -Section 'project' -Key 'requires-python'
    if ($null -ne $foundToml -and (Test-TerminalEnvMetadataValueSafe $foundToml.value)) { $pythonConstraint = [pscustomobject]@{ value = $foundToml.value; kind = 'pyproject-requires-python'; source = $foundToml.source } }
    $pythonInfo = $null; $pythonVersion = ''
    $venvInside = $false; $venvPath = ''
    if ($env:VIRTUAL_ENV) {
        $venvPath = Get-TerminalEnvPhysicalPath $env:VIRTUAL_ENV
        $venvInside = Test-TerminalEnvPathInside -Path $venvPath -Root $root
    }
    if ($pythonSelectors.Count -gt 0 -or $null -ne $pythonConstraint -or $venvInside) {
        $pythonInfo = Get-TerminalEnvCommandInfo -Names @('python','python3')
        $pythonVersion = Invoke-TerminalEnvRuntimeVersionCommand -CommandInfo $pythonInfo -Tool python
        if ($venvInside -and $null -ne $pythonInfo -and $pythonVersion -and (Test-TerminalEnvPathInside -Path $pythonInfo.path -Root $venvPath)) {
            Add-TerminalEnvSelector -List $pythonSelectors -Value $pythonVersion -Kind 'virtualenv' -Source $venvPath
        }
    }

    $goSelectors = [Collections.Generic.List[object]]::new()
    $toolVersion = Get-TerminalEnvNearestToolVersion -Dirs $dirs -Tool go
    if ($null -ne $toolVersion) { $goSelectors.Add($toolVersion) }
    foreach ($item in Get-TerminalEnvMiseSelectors -Dirs $dirs -Tool go) { $goSelectors.Add($item) }
    $goConstraint = $null; $goProject = $null
    foreach ($fileName in 'go.work','go.mod') {
        foreach ($dir in $dirs) {
            $path = Join-Path $dir $fileName
            if (Test-Path -LiteralPath $path -PathType Leaf) { $goProject = $path; break }
        }
        if ($goProject) { break }
    }
    if ($goProject) {
        foreach ($line in [IO.File]::ReadLines($goProject)) {
            if ($line -match '^\s*toolchain\s+(\S+)') {
                if ($Matches[1] -ne 'default') { Add-TerminalEnvSelector -List $goSelectors -Value $Matches[1] -Kind 'go-toolchain' -Source $goProject }
            } elseif ($line -match '^\s*go\s+(\S+)') {
                if (Test-TerminalEnvMetadataValueSafe $Matches[1]) { $goConstraint = [pscustomobject]@{ value = $Matches[1]; kind = 'go-directive'; source = $goProject } }
            }
        }
    }

    $rustSelectors = [Collections.Generic.List[object]]::new()
    $toolVersion = Get-TerminalEnvNearestToolVersion -Dirs $dirs -Tool rust
    if ($null -ne $toolVersion) { $rustSelectors.Add($toolVersion) }
    foreach ($item in Get-TerminalEnvMiseSelectors -Dirs $dirs -Tool rust) { $rustSelectors.Add($item) }
    $rustToolchain = $null
    foreach ($dir in $dirs) {
        $legacy = Join-Path $dir 'rust-toolchain'
        $toml = Join-Path $dir 'rust-toolchain.toml'
        if (Test-Path -LiteralPath $legacy -PathType Leaf) { $rustToolchain = $legacy; break }
        if (Test-Path -LiteralPath $toml -PathType Leaf) { $rustToolchain = $toml; break }
    }
    if ($rustToolchain) {
        $isToml = (Split-Path -Leaf $rustToolchain) -eq 'rust-toolchain.toml' -or (Get-Content -LiteralPath $rustToolchain -Raw) -match '(?m)^\s*\[toolchain\]'
        $value = if ($isToml) { Get-TerminalEnvTomlValue -Path $rustToolchain -Section 'toolchain' -Key 'channel' } else { Get-TerminalEnvFirstValueLine $rustToolchain }
        if ($value) { Add-TerminalEnvSelector -List $rustSelectors -Value $value -Kind 'rust-toolchain' -Source $rustToolchain }
    }
    $rustConstraint = $null
    $foundToml = Get-TerminalEnvNearestTomlValue -Dirs $dirs -FileName 'Cargo.toml' -Section 'package' -Key 'rust-version'
    if ($null -ne $foundToml -and (Test-TerminalEnvMetadataValueSafe $foundToml.value)) { $rustConstraint = [pscustomobject]@{ value = $foundToml.value; kind = 'cargo-rust-version'; source = $foundToml.source } }

    $nodeInfo = if ($nodeSelectors.Count -gt 0 -or $null -ne $nodeConstraint) { Get-TerminalEnvCommandInfo -Names @('node') } else { $null }
    $nodeVersion = if ($null -ne $nodeInfo) { Invoke-TerminalEnvRuntimeVersionCommand -CommandInfo $nodeInfo -Tool node } else { '' }
    $goInfo = if ($goSelectors.Count -gt 0 -or $null -ne $goConstraint) { Get-TerminalEnvCommandInfo -Names @('go') } else { $null }
    $goVersion = if ($null -ne $goInfo) { Invoke-TerminalEnvRuntimeVersionCommand -CommandInfo $goInfo -Tool go } else { '' }
    $rustInfo = if ($rustSelectors.Count -gt 0 -or $null -ne $rustConstraint) { Get-TerminalEnvCommandInfo -Names @('rustc') } else { $null }
    $rustVersion = if ($null -ne $rustInfo) { Invoke-TerminalEnvRuntimeVersionCommand -CommandInfo $rustInfo -Tool rust } else { '' }

    $tools = [ordered]@{}
    $node = Resolve-TerminalEnvTool -Tool node -Selectors @($nodeSelectors) -Constraint $nodeConstraint -ActiveInfo $nodeInfo -ActiveVersion $nodeVersion -Note ''
    $python = Resolve-TerminalEnvTool -Tool python -Selectors @($pythonSelectors) -Constraint $pythonConstraint -ActiveInfo $pythonInfo -ActiveVersion $pythonVersion -Note ''
    $go = Resolve-TerminalEnvTool -Tool go -Selectors @($goSelectors) -Constraint $goConstraint -ActiveInfo $goInfo -ActiveVersion $goVersion -Note ''
    $rust = Resolve-TerminalEnvTool -Tool rust -Selectors @($rustSelectors) -Constraint $rustConstraint -ActiveInfo $rustInfo -ActiveVersion $rustVersion -Note ''
    if ($null -ne $node) { $tools['node'] = $node }
    if ($null -ne $python) { $tools['python'] = $python }
    if ($null -ne $go) { $tools['go'] = $go }
    if ($null -ne $rust) { $tools['rust'] = $rust }
    $promptParts = @($tools.Values | ForEach-Object { if ($_.prompt) { $_.prompt } })
    $promptState = if (@($tools.Values | Where-Object state -eq 'warning').Count) { 'warning' } else { 'normal' }
    return [pscustomobject][ordered]@{
        schema_version = 1
        cwd = $cwdPath
        root = $root
        repository = $repo
        toolchains = $tools
        prompt = [ordered]@{ text = ($promptParts -join '  '); state = $promptState }
    }
}

function Write-TerminalEnvContextHuman {
    param([object]$Context)
    Write-Output 'Project context'
    Write-Output ''
    Write-Output ('{0,-11} {1}' -f 'Root', (ConvertTo-TerminalEnvDisplayText $Context.root))
    if ($Context.repository.name) {
        Write-Output ('{0,-11} {1}' -f 'Repository', (ConvertTo-TerminalEnvDisplayText $Context.repository.name))
        if ($Context.repository.branch) { Write-Output ('{0,-11} {1}' -f 'Branch', (ConvertTo-TerminalEnvDisplayText $Context.repository.branch)) }
        elseif ($Context.repository.commit) { Write-Output ('{0,-11} detached@{1}' -f 'Revision', $Context.repository.commit) }
    } else { Write-Output ('{0,-11} {1}' -f 'Repository', '(none)') }
    $titles = @{ node = 'Node'; python = 'Python'; go = 'Go'; rust = 'Rust' }
    foreach ($name in 'node','python','go','rust') {
        if (-not $Context.toolchains.Contains($name)) { continue }
        $tool = $Context.toolchains[$name]
        Write-Output ''
        Write-Output $titles[$name]
        $referenceValue = if ($null -ne $tool.selector) { $tool.selector.value } elseif ($tool.selectors.Count) { $tool.selectors[0].value } else { '' }
        $referenceKind = if ($null -ne $tool.selector) { $tool.selector.kind } elseif ($tool.selectors.Count) { $tool.selectors[0].kind } else { '' }
        for ($i = 0; $i -lt $tool.selectors.Count; $i++) {
            $evidence = $tool.selectors[$i]
            if ($i -eq 0) { $relation = 'requested' }
            elseif ($tool.conflict) { $relation = 'conflict' }
            elseif (Test-TerminalEnvSelectorsCompatible -Tool $name -A $evidence.value -KindA $evidence.kind -B $referenceValue -KindB $referenceKind) { $relation = 'also' }
            else { $relation = 'conflict' }
            Write-Output ('  {0,-10} {1,-14} {2}' -f $relation, $evidence.value, (Get-TerminalEnvDisplaySource -Source $evidence.source -Root $Context.root))
        }
        if ($null -ne $tool.constraint) { Write-Output ('  {0,-10} {1,-14} {2}' -f 'requires', $tool.constraint.value, (Get-TerminalEnvDisplaySource -Source $tool.constraint.source -Root $Context.root)) }
        if ($null -ne $tool.active) { Write-Output ('  {0,-10} {1,-14} {2}' -f 'active', $tool.active.version, (ConvertTo-TerminalEnvDisplayText $tool.active.path)) }
        if ($tool.conflict) { Write-Output ('  {0,-10} {1}' -f 'attention', 'conflicting project selectors; no precedence was invented') }
        elseif ($tool.missing) { Write-Output ('  {0,-10} {1}' -f 'attention', 'selected runtime is not available on PATH') }
        elseif ($tool.mismatch) { Write-Output ('  {0,-10} {1}' -f 'attention', 'active runtime does not satisfy the project context') }
        elseif ($tool.note) { Write-Output ('  {0,-10} {1}' -f 'attention', (ConvertTo-TerminalEnvDisplayText $tool.note)) }
        elseif ($tool.selector_status -eq 'unknown') { Write-Output ('  {0,-10} {1}' -f 'note', 'selector compatibility was not evaluated for this syntax') }
        elseif ($tool.constraint_status -eq 'unknown') { Write-Output ('  {0,-10} {1}' -f 'note', 'constraint compatibility was not evaluated for this syntax') }
    }
    if ($Context.toolchains.Count -eq 0) { Write-Output ''; Write-Output 'No authoritative project runtime declarations found.' }
}

function Write-TerminalEnvContextPlain {
    param([object]$Context)
    function Field([AllowNull()][object]$Value) { return (ConvertTo-TerminalEnvDisplayText $Value) }
    Write-Output ("context`tcwd`t{0}" -f (Field $Context.cwd))
    Write-Output ("context`troot`t{0}" -f (Field $Context.root))
    Write-Output ("repository`tname`t{0}" -f (Field $Context.repository.name))
    Write-Output ("repository`tbranch`t{0}" -f (Field $Context.repository.branch))
    Write-Output ("repository`tdetached`t{0}" -f ([string]$Context.repository.detached).ToLowerInvariant())
    Write-Output ("repository`tcommit`t{0}" -f (Field $Context.repository.commit))
    foreach ($name in 'node','python','go','rust') {
        if (-not $Context.toolchains.Contains($name)) { continue }
        $tool = $Context.toolchains[$name]
        foreach ($evidence in $tool.selectors) {
            Write-Output ("toolchain`t{0}`tselector`t{1}`t{2}`t{3}" -f $name,(Field $evidence.value),(Field $evidence.kind),(Field $evidence.source))
        }
        if ($null -ne $tool.constraint) {
            Write-Output ("toolchain`t{0}`tconstraint`t{1}`t{2}`t{3}" -f $name,(Field $tool.constraint.value),(Field $tool.constraint.kind),(Field $tool.constraint.source))
        }
        if ($null -ne $tool.active) {
            Write-Output ("toolchain`t{0}`tactive`t{1}`tpath`t{2}" -f $name,(Field $tool.active.version),(Field $tool.active.path))
        }
        if ($tool.selector_status) { Write-Output ("toolchain`t{0}`tselector_status`t{1}`t`t" -f $name,(Field $tool.selector_status)) }
        if ($tool.constraint_status) { Write-Output ("toolchain`t{0}`tconstraint_status`t{1}`t`t" -f $name,(Field $tool.constraint_status)) }
        Write-Output ("toolchain`t{0}`tconflict`t{1}`t`t" -f $name,([string][bool]$tool.conflict).ToLowerInvariant())
        Write-Output ("toolchain`t{0}`tmissing`t{1}`t`t" -f $name,([string][bool]$tool.missing).ToLowerInvariant())
        Write-Output ("toolchain`t{0}`tmismatch`t{1}`t`t" -f $name,([string][bool]$tool.mismatch).ToLowerInvariant())
        Write-Output ("toolchain`t{0}`tstate`t{1}`t`t" -f $name,(Field $tool.state))
        if ($tool.note) { Write-Output ("toolchain`t{0}`tnote`t{1}`t`t" -f $name,(Field $tool.note)) }
    }
    Write-Output ("prompt`tstate`t{0}" -f (Field $Context.prompt.state))
    Write-Output ("prompt`ttext`t{0}" -f (Field $Context.prompt.text))
}

function Update-TerminalEnvProjectContext {
    $key = @(
        (Get-Location).Path,
        $env:PATH,
        $env:VIRTUAL_ENV,
        $env:PYENV_VERSION,
        $env:RUSTUP_TOOLCHAIN,
        $env:GOTOOLCHAIN
    ) -join "`n"
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($script:TerminalEnvContextCacheKey -ne $key -or ($now - $script:TerminalEnvContextCacheAt) -ge 5) {
        try {
            $context = Resolve-TerminalEnvContext -Cwd (Get-Location).Path -PromptOnly
            $script:TerminalEnvContextCacheText = $context.prompt.text
            $script:TerminalEnvContextCacheState = $context.prompt.state
        } catch {
            $script:TerminalEnvContextCacheText = ''
            $script:TerminalEnvContextCacheState = 'normal'
        }
        $script:TerminalEnvContextCacheKey = $key
        $script:TerminalEnvContextCacheAt = $now
    }
    $env:TERMINAL_ENV_PROJECT_CONTEXT = $script:TerminalEnvContextCacheText
    $env:TERMINAL_ENV_PROJECT_CONTEXT_STATE = $script:TerminalEnvContextCacheState
}

function Show-TerminalEnvContextUsage {
    Write-Output @'
Usage: terminal context [options]
       terminal-context [options]

Options:
  --cwd PATH               Resolve context for PATH instead of the current directory.
  --format human|plain|json
  -h, --help               Show this help.
'@
}

function Invoke-TerminalEnvContextCommand {
    param([string[]]$CommandArgs)
    $format = 'human'
    $cwd = (Get-Location).Path
    for ($i = 0; $i -lt $CommandArgs.Count; $i++) {
        switch ($CommandArgs[$i]) {
            '--format' {
                if ($i + 1 -ge $CommandArgs.Count) { throw 'Missing value for --format' }
                $format = $CommandArgs[++$i]
            }
            '--cwd' {
                if ($i + 1 -ge $CommandArgs.Count) { throw 'Missing value for --cwd' }
                $cwd = $CommandArgs[++$i]
            }
            '--prompt-record' { $format = 'prompt-record' }
            '-h' { Show-TerminalEnvContextUsage; return }
            '--help' { Show-TerminalEnvContextUsage; return }
            default { throw "Unknown option: $($CommandArgs[$i])" }
        }
    }
    if ($format -notin @('human','plain','json','prompt-record')) { throw "Unknown format: $format" }
    $context = Resolve-TerminalEnvContext -Cwd $cwd
    switch ($format) {
        json { $context | ConvertTo-Json -Depth 8 -Compress }
        plain { Write-TerminalEnvContextPlain $context }
        'prompt-record' { Write-Output ("{0}`t{1}" -f $context.prompt.state, $context.prompt.text) }
        default { Write-TerminalEnvContextHuman $context }
    }
    return
}

$script:TerminalEnvContextCacheKey = ''
$script:TerminalEnvContextCacheAt = [int64]0
$script:TerminalEnvContextCacheText = ''
$script:TerminalEnvContextCacheState = 'normal'

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-TerminalEnvContextCommand -CommandArgs @($args)
        exit 0
    } catch {
        Write-Error $_.Exception.Message
        exit 2
    }
}

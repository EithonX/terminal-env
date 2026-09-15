$script:TerminalEnvUiUseAnsi = $false
$script:TerminalEnvUiWidth = 80
$script:TerminalEnvUiTheme = @{
    text = '#E6EBF0'
    soft = '#A2ACB7'
    muted = '#707C88'
    accent = '#7CC4E4'
    warning = '#D6A85F'
    danger = '#E07880'
    success = '#8BB594'
}

$themePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'theme.json'
if (Test-Path -LiteralPath $themePath) {
    try {
        $theme = Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json
        foreach ($name in @($script:TerminalEnvUiTheme.Keys)) {
            if ($theme.PSObject.Properties.Name -contains $name) {
                $script:TerminalEnvUiTheme[$name] = [string]$theme.$name
            }
        }
    } catch {}
}

function Get-TerminalEnvSafeText {
    param([AllowNull()][object]$Text)
    if ($null -eq $Text) { return '' }
    $value = [string]$Text
    $value = [regex]::Replace($value, "`e\[[0-?]*[ -/]*[@-~]", '')
    $value = [regex]::Replace($value, '[\x00-\x1F\x7F]', ' ')
    return $value
}

function Initialize-TerminalEnvUI {
    param(
        [ValidateSet('human','plain','json')][string]$Format = 'human',
        [ValidateSet('auto','always','never')][string]$ColorMode = 'auto'
    )
    $script:TerminalEnvUiUseAnsi = $false
    if ($Format -eq 'human') {
        if ($ColorMode -eq 'always') {
            $script:TerminalEnvUiUseAnsi = $true
        } elseif ($ColorMode -eq 'auto') {
            $redirected = $true
            try { $redirected = [Console]::IsOutputRedirected } catch {}
            if (-not $redirected -and -not $env:NO_COLOR -and $env:TERM -ne 'dumb') {
                $script:TerminalEnvUiUseAnsi = $true
            }
        }
    }

    $width = 0
    if ($env:COLUMNS -match '^\d+$') { $width = [int]$env:COLUMNS }
    if ($width -le 0) {
        try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch { $width = 80 }
    }
    if ($width -le 0) { $width = 80 }
    $script:TerminalEnvUiWidth = $width
}

function Format-TerminalEnvStyle {
    param([string]$Role, [AllowNull()][object]$Text)
    $value = Get-TerminalEnvSafeText $Text
    if (-not $script:TerminalEnvUiUseAnsi) { return $value }
    if ($Role -eq 'title') { return "`e[1m$value`e[0m" }
    if (-not $script:TerminalEnvUiTheme.ContainsKey($Role)) { return $value }
    $hex = $script:TerminalEnvUiTheme[$Role].TrimStart('#')
    if ($hex.Length -ne 6) { return $value }
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)
    return "`e[38;2;${r};${g};${b}m$value`e[0m"
}

function Write-TerminalEnvTitle {
    param([string]$Command)
    Write-Output (Format-TerminalEnvStyle title "Terminal Environment · $Command")
}

function Write-TerminalEnvMeta {
    param([string]$Text)
    Write-Output (Format-TerminalEnvStyle muted $Text)
}

function Write-TerminalEnvSection {
    param([string]$Name)
    Write-Output ''
    Write-Output (Format-TerminalEnvStyle title $Name)
}

function Write-TerminalEnvRow {
    param([string]$Label, [string]$Value, [string]$Tone = 'text')
    if ($script:TerminalEnvUiWidth -lt 72) {
        Write-Output ('  ' + (Format-TerminalEnvStyle soft $Label))
        Write-Output ('    ' + (Format-TerminalEnvStyle $Tone $Value))
        return
    }
    $width = if ($script:TerminalEnvUiWidth -ge 100) { 20 } else { 16 }
    $left = $Label.PadRight($width)
    Write-Output ('  ' + (Format-TerminalEnvStyle soft $left) + '  ' + (Format-TerminalEnvStyle $Tone $Value))
}

function Write-TerminalEnvAttention {
    param([string]$Status, [string]$Label, [string]$Message)
    if ($Status -eq 'fail' -or $Status -eq 'failure') { $word='failure'; $tone='danger' }
    else { $word='warning'; $tone='warning' }
    if ($script:TerminalEnvUiWidth -lt 72) {
        Write-Output ('  ' + (Format-TerminalEnvStyle soft $Label))
        Write-Output ('    ' + (Format-TerminalEnvStyle $tone $word) + ' · ' + (Get-TerminalEnvSafeText $Message))
        return
    }
    $width = if ($script:TerminalEnvUiWidth -ge 100) { 20 } else { 16 }
    Write-Output ('  ' + (Format-TerminalEnvStyle soft $Label.PadRight($width)) + '  ' + (Format-TerminalEnvStyle $tone $word) + ' · ' + (Get-TerminalEnvSafeText $Message))
}

function Write-TerminalEnvOutcome {
    param([string]$Tone, [string]$Text)
    Write-Output ''
    Write-Output (Format-TerminalEnvStyle $Tone $Text)
}

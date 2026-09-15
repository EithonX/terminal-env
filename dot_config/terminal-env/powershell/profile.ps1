# Managed Terminal Environment PowerShell profile. Optional integrations fail open.
$env:TERMINAL_ENV_VERSION = '8'
$localBin = Join-Path $HOME '.local\bin'
if (-not ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -eq $localBin })) { $env:PATH = "$localBin$([IO.Path]::PathSeparator)$env:PATH" }
try { $utf8=[Text.UTF8Encoding]::new($false); [Console]::InputEncoding=$utf8; [Console]::OutputEncoding=$utf8; $global:OutputEncoding=$utf8 } catch {}
$terminalEnvPlain = [bool]($env:NO_COLOR -or $env:TERM -eq 'dumb')

try {
    if ($terminalEnvPlain) {
        $PSStyle.FileInfo.Directory = ''
        $PSStyle.FileInfo.SymbolicLink = ''
        $PSStyle.FileInfo.Executable = ''
        foreach ($ext in '.zip','.7z','.tar','.gz','.tgz','.rar','.ps1','.psm1','.psd1','.json','.toml','.yaml','.yml','.md') { $PSStyle.FileInfo.Extension[$ext] = '' }
    } else {
        $PSStyle.FileInfo.Directory = $PSStyle.Foreground.FromRgb(124, 196, 228) + $PSStyle.Bold
        $PSStyle.FileInfo.SymbolicLink = $PSStyle.Foreground.FromRgb(162, 172, 183)
        $PSStyle.FileInfo.Executable = $PSStyle.Foreground.FromRgb(230, 235, 240) + $PSStyle.Bold
        foreach ($ext in '.zip','.7z','.tar','.gz','.tgz','.rar') { $PSStyle.FileInfo.Extension[$ext] = $PSStyle.Foreground.FromRgb(162, 172, 183) }
        foreach ($ext in '.ps1','.psm1','.psd1','.json','.toml','.yaml','.yml','.md') { $PSStyle.FileInfo.Extension[$ext] = $PSStyle.Foreground.FromRgb(162, 172, 183) }
    }
} catch {}

if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -EditMode Windows -HistorySearchCursorMovesToEnd -BellStyle None
    try {
        if ($terminalEnvPlain) {
            Set-PSReadLineOption -Colors @{
                Default = $PSStyle.Reset; Comment = $PSStyle.Reset; Keyword = $PSStyle.Reset; String = $PSStyle.Reset; Operator = $PSStyle.Reset; Variable = $PSStyle.Reset
                Command = $PSStyle.Reset; Parameter = $PSStyle.Reset; Type = $PSStyle.Reset; Number = $PSStyle.Reset; Member = $PSStyle.Reset; Emphasis = $PSStyle.Reset; Error = $PSStyle.Reset
                ContinuationPrompt = $PSStyle.Reset; InlinePrediction = $PSStyle.Reset; ListPrediction = $PSStyle.Reset; ListPredictionSelected = $PSStyle.Reset
            }
        } else {
            Set-PSReadLineOption -Colors @{
                Default = $PSStyle.Foreground.FromRgb(230, 235, 240)
                Comment = $PSStyle.Foreground.FromRgb(112, 124, 136)
                Keyword = $PSStyle.Foreground.FromRgb(162, 172, 183)
                String = $PSStyle.Foreground.FromRgb(230, 235, 240)
                Operator = $PSStyle.Foreground.FromRgb(112, 124, 136)
                Variable = $PSStyle.Foreground.FromRgb(162, 172, 183)
                Command = $PSStyle.Foreground.FromRgb(124, 196, 228)
                Parameter = $PSStyle.Foreground.FromRgb(162, 172, 183)
                Type = $PSStyle.Foreground.FromRgb(162, 172, 183)
                Number = $PSStyle.Foreground.FromRgb(230, 235, 240)
                Member = $PSStyle.Foreground.FromRgb(162, 172, 183)
                Emphasis = $PSStyle.Foreground.FromRgb(124, 196, 228)
                Error = $PSStyle.Foreground.FromRgb(224, 120, 128)
                ContinuationPrompt = $PSStyle.Foreground.FromRgb(112, 124, 136)
                InlinePrediction = $PSStyle.Foreground.FromRgb(112, 124, 136)
                ListPrediction = $PSStyle.Foreground.FromRgb(162, 172, 183)
                ListPredictionSelected = $PSStyle.Background.FromRgb(27, 35, 45) + $PSStyle.Foreground.FromRgb(230, 235, 240)
            }
        }
    } catch {}
    try { Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle InlineView } catch { try { Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView } catch {} }
    try { Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar } catch {}
    try { Set-PSReadLineKeyHandler -Chord Ctrl+RightArrow -Function ForwardWord } catch {}
    try { Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward } catch {}
    try { Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward } catch {}
}
if (Get-Command atuin -ErrorAction SilentlyContinue) { try { (& atuin init powershell --disable-up-arrow --disable-ai | Out-String) | Invoke-Expression } catch {} }
if (Get-Command zoxide -ErrorAction SilentlyContinue) { try { (& zoxide init powershell | Out-String) | Invoke-Expression } catch {} }

$fzfTerminalEnvBase = ' --style=minimal --height=~60% --min-height=10+ --layout=reverse --info=inline-right --no-separator --pointer=› --marker=+'
$fzfTerminalEnvColor = if ($terminalEnvPlain) { ' --no-color' } else { ' --color=bg+:#151b22,bg:#0a0e13,spinner:#707c88,hl:#7cc4e4,fg:#e6ebf0,header:#707c88,info:#707c88,pointer:#7cc4e4,marker:#7cc4e4,prompt:#7cc4e4,hl+:#7cc4e4,border:#28323d,label:#a2acb7' }
$env:FZF_DEFAULT_OPTS = (($env:FZF_DEFAULT_OPTS + $fzfTerminalEnvBase + $fzfTerminalEnvColor).Trim())
Remove-Variable fzfTerminalEnvBase, fzfTerminalEnvColor -ErrorAction SilentlyContinue
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Command fd -ErrorAction SilentlyContinue) -and (Get-Module PSReadLine)) {
    try { Set-PSReadLineKeyHandler -Chord Ctrl+t -ScriptBlock {
        $picked = (& fd --type f --hidden --exclude .git 2>$null | & fzf)
        if ($picked) { $insert = if ($picked -match '\s') { "'" + $picked.Replace("'", "''") + "'" } else { $picked }; [Microsoft.PowerShell.PSConsoleReadLine]::Insert($insert) }
    } } catch {}
}
$env:BAT_THEME = 'ansi'
$env:BAT_STYLE = 'numbers,changes,header'
$env:EZA_ICONS_AUTO = '1'
$env:EZA_COLORS = 'di=1;38;2;124;196;228:ln=38;2;162;172;183:ex=1;38;2;230;235;240:da=38;2;112;124;136:sn=38;2;112;124;136:fi=38;2;230;235;240'
$terminalEnvEzaColor = if ($terminalEnvPlain) { 'never' } else { 'auto' }
function l { if (Get-Command eza -ErrorAction SilentlyContinue) { eza --icons=auto --group-directories-first "--color=$terminalEnvEzaColor" @args } else { Get-ChildItem @args } }
function ll { if (Get-Command eza -ErrorAction SilentlyContinue) { eza -lah --icons=auto --group-directories-first --git "--color=$terminalEnvEzaColor" @args } else { Get-ChildItem -Force @args } }
function lt { if (Get-Command eza -ErrorAction SilentlyContinue) { eza --tree --icons=auto --group-directories-first "--color=$terminalEnvEzaColor" @args } else { Get-ChildItem -Recurse @args } }
function mkcd([Parameter(Mandatory=$true)][string]$Path) { New-Item -ItemType Directory -Force -Path $Path | Out-Null; Set-Location $Path }
function terminal-doctor { & (Join-Path $HOME '.config\terminal-env\powershell\doctor.ps1') @args }
function terminal-update { & (Join-Path $HOME '.config\terminal-env\powershell\update.ps1') @args }
function terminal-rollback { & (Join-Path $HOME '.config\terminal-env\powershell\rollback.ps1') @args }
function terminal-backup { & (Join-Path $HOME '.config\terminal-env\powershell\backup.ps1') @args }
function terminal-deps { & (Join-Path $HOME '.config\terminal-env\powershell\deps.ps1') @args }
$terminalCommandScript = Join-Path $HOME '.config\terminal-env\powershell\terminal.ps1'
if (Test-Path -LiteralPath $terminalCommandScript) {
    try { . $terminalCommandScript } catch {}
}
function terminal {
    if (Get-Command Invoke-TerminalEnvCommand -ErrorAction SilentlyContinue) { Invoke-TerminalEnvCommand -CommandArgs @($args) }
    else { throw 'Unified Terminal Environment command is unavailable; run terminal doctor.' }
}
$terminalContextScript = Join-Path $HOME '.config\terminal-env\powershell\context.ps1'
if (Test-Path -LiteralPath $terminalContextScript) {
    try { . $terminalContextScript } catch {}
}
function terminal-context { & $terminalContextScript @args }
function global:Set-TerminalEnvPoshContext([bool]$originalStatus) {
    $terminalEnvSavedExitCode = $global:LASTEXITCODE
    try { if (Get-Command Update-TerminalEnvProjectContext -ErrorAction SilentlyContinue) { Update-TerminalEnvProjectContext } } catch {}
    finally { $global:LASTEXITCODE = $terminalEnvSavedExitCode }
}
New-Alias -Name 'Set-PoshContext' -Value 'Set-TerminalEnvPoshContext' -Scope Global -Force
$localProfile = Join-Path $HOME '.config\terminal-env\local.ps1'; if (Test-Path $localProfile) { . $localProfile }
$ompTheme = Join-Path $HOME '.config\oh-my-posh\terminal.omp.json'
$script:TerminalEnvFallbackMarker = if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { '#' } else { '❯' }
function global:prompt {
    $terminalEnvSavedExitCode = $global:LASTEXITCODE
    try { if (Get-Command Update-TerminalEnvProjectContext -ErrorAction SilentlyContinue) { Update-TerminalEnvProjectContext } } catch {}
    finally { $global:LASTEXITCODE = $terminalEnvSavedExitCode }
    $terminalEnvProjectPart = if ($env:TERMINAL_ENV_PROJECT_CONTEXT) { "  $($env:TERMINAL_ENV_PROJECT_CONTEXT)" } else { "" }
    "$($executionContext.SessionState.Path.CurrentLocation)$terminalEnvProjectPart │ $script:TerminalEnvFallbackMarker "
}
if ($env:TERM -ne 'dumb' -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $ompTheme)) {
    try { (& oh-my-posh init pwsh --strict --config $ompTheme | Out-String) | Invoke-Expression } catch {}
}

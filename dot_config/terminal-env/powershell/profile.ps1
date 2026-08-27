# Managed Terminal Environment PowerShell profile. Optional integrations fail open.
$env:TERMINAL_ENV_VERSION = '6'
$localBin = Join-Path $HOME '.local\bin'
if (-not ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -eq $localBin })) { $env:PATH = "$localBin$([IO.Path]::PathSeparator)$env:PATH" }
try { $utf8=[Text.UTF8Encoding]::new($false); [Console]::InputEncoding=$utf8; [Console]::OutputEncoding=$utf8; $global:OutputEncoding=$utf8 } catch {}

try {
    $PSStyle.FileInfo.Directory = $PSStyle.Foreground.FromRgb(125, 215, 255) + $PSStyle.Bold
    $PSStyle.FileInfo.SymbolicLink = $PSStyle.Foreground.FromRgb(197, 166, 245)
    $PSStyle.FileInfo.Executable = $PSStyle.Foreground.FromRgb(166, 209, 137) + $PSStyle.Bold
    foreach ($ext in '.zip','.7z','.tar','.gz','.tgz','.rar') { $PSStyle.FileInfo.Extension[$ext] = $PSStyle.Foreground.FromRgb(229, 192, 123) }
    foreach ($ext in '.ps1','.psm1','.psd1','.json','.toml','.yaml','.yml','.md') { $PSStyle.FileInfo.Extension[$ext] = $PSStyle.Foreground.FromRgb(167, 179, 191) }
} catch {}

if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -EditMode Windows -HistorySearchCursorMovesToEnd -BellStyle None
    try {
        Set-PSReadLineOption -Colors @{
            Default = $PSStyle.Foreground.FromRgb(231, 237, 243)
            Comment = $PSStyle.Foreground.FromRgb(77, 88, 99)
            Keyword = $PSStyle.Foreground.FromRgb(197, 166, 245)
            String = $PSStyle.Foreground.FromRgb(166, 209, 137)
            Operator = $PSStyle.Foreground.FromRgb(167, 179, 191)
            Variable = $PSStyle.Foreground.FromRgb(125, 215, 255)
            Command = $PSStyle.Foreground.FromRgb(138, 180, 255)
            Parameter = $PSStyle.Foreground.FromRgb(197, 166, 245)
            Type = $PSStyle.Foreground.FromRgb(125, 215, 255)
            Number = $PSStyle.Foreground.FromRgb(229, 192, 123)
            Member = $PSStyle.Foreground.FromRgb(167, 179, 191)
            Emphasis = $PSStyle.Foreground.FromRgb(125, 215, 255)
            Error = $PSStyle.Foreground.FromRgb(243, 139, 168)
            ContinuationPrompt = $PSStyle.Foreground.FromRgb(108, 121, 134)
            InlinePrediction = $PSStyle.Foreground.FromRgb(108, 121, 134)
            ListPrediction = $PSStyle.Foreground.FromRgb(167, 179, 191)
            ListPredictionSelected = $PSStyle.Background.FromRgb(23, 30, 39) + $PSStyle.Foreground.FromRgb(231, 237, 243)
        }
    } catch {}
    try { Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle InlineView } catch { try { Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView } catch {} }
    try { Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptSuggestion } catch {}
    try { Set-PSReadLineKeyHandler -Chord Ctrl+RightArrow -Function AcceptNextSuggestionWord } catch {}
    try { Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward } catch {}
    try { Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward } catch {}
}
if (Get-Command atuin -ErrorAction SilentlyContinue) { try { (& atuin init powershell --disable-up-arrow --disable-ai | Out-String) | Invoke-Expression } catch {} }
if (Get-Command zoxide -ErrorAction SilentlyContinue) { try { (& zoxide init powershell | Out-String) | Invoke-Expression } catch {} }

$env:FZF_DEFAULT_OPTS = (($env:FZF_DEFAULT_OPTS + ' --height=62% --layout=reverse --border=rounded --info=inline-right --no-separator --pointer=› --marker=+ --color=bg+:#11161d,bg:#090d12,spinner:#7dd7ff,hl:#7dd7ff,fg:#e7edf3,header:#6c7986,info:#6c7986,pointer:#7dd7ff,marker:#a6d189,prompt:#8ab4ff,hl+:#c5a6f5,border:#25303b,label:#a7b3bf').Trim())
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Command fd -ErrorAction SilentlyContinue) -and (Get-Module PSReadLine)) {
    try { Set-PSReadLineKeyHandler -Chord Ctrl+t -ScriptBlock {
        $picked = (& fd --type f --hidden --exclude .git 2>$null | & fzf)
        if ($picked) { $insert = if ($picked -match '\s') { "'" + $picked.Replace("'", "''") + "'" } else { $picked }; [Microsoft.PowerShell.PSConsoleReadLine]::Insert($insert) }
    } } catch {}
}
$env:BAT_THEME = 'ansi'
$env:BAT_STYLE = 'numbers,changes,header'
$env:EZA_ICONS_AUTO = '1'
$env:EZA_COLORS = 'di=1;38;2;125;215;255:ln=38;2;197;166;245:ex=1;38;2;166;209;137:da=38;2;108;121;134:sn=38;2;108;121;134:fi=38;2;231;237;243'
function l { if (Get-Command eza -ErrorAction SilentlyContinue) { eza --icons=auto --group-directories-first @args } else { Get-ChildItem @args } }
function ll { if (Get-Command eza -ErrorAction SilentlyContinue) { eza -lah --icons=auto --group-directories-first --git @args } else { Get-ChildItem -Force @args } }
function lt { if (Get-Command eza -ErrorAction SilentlyContinue) { eza --tree --icons=auto --group-directories-first @args } else { Get-ChildItem -Recurse @args } }
function mkcd([Parameter(Mandatory=$true)][string]$Path) { New-Item -ItemType Directory -Force -Path $Path | Out-Null; Set-Location $Path }
function terminal-doctor { & (Join-Path $HOME '.config\terminal-env\powershell\doctor.ps1') @args }
function terminal-update { & (Join-Path $HOME '.config\terminal-env\powershell\update.ps1') @args }
function terminal-rollback { & (Join-Path $HOME '.config\terminal-env\powershell\rollback.ps1') @args }
function terminal-backup { & (Join-Path $HOME '.config\terminal-env\powershell\backup.ps1') @args }
$localProfile = Join-Path $HOME '.config\terminal-env\local.ps1'; if (Test-Path $localProfile) { . $localProfile }
$ompTheme = Join-Path $HOME '.config\oh-my-posh\terminal.omp.json'
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $ompTheme)) { try { (& oh-my-posh init pwsh --strict --config $ompTheme | Out-String) | Invoke-Expression } catch { function global:prompt { "PS $($executionContext.SessionState.Path.CurrentLocation)> " } } }

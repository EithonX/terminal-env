$Restore=$true
$Yes=$false
$DryRun=$false
$NoInput=$false
$Format='human'
$Color='auto'
$Quiet=$false

function Show-Usage {
    Write-Output @'
Usage: ./uninstall.ps1 [options]

Options:
  --no-restore             Remove managed files without restoring the pre-install snapshot.
  --yes                    Skip interactive confirmation.
  --dry-run                Show the uninstall plan without changing anything.
  --no-input               Never prompt; requires --yes when applying changes.
  --format human|plain|json
  --color auto|always|never
  --quiet                  Print no result output; requires --yes when applying changes.
  -h, --help               Show this help.
'@
}

for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('--no-restore','-NoRestore')){$Restore=$false;continue}
    if($arg -in @('--yes','-Yes')){$Yes=$true;continue}
    if($arg -in @('--dry-run','-DryRun')){$DryRun=$true;continue}
    if($arg -in @('--no-input','-NoInput')){$NoInput=$true;continue}
    if($arg -in @('--quiet','-Quiet')){$Quiet=$true;continue}
    if($arg -in @('--format','-Format')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Format=[string]$args[$i];continue}
    if($arg -like '--format=*'){$Format=$arg.Substring(9);continue}
    if($arg -in @('--color','-Color')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Color=[string]$args[$i];continue}
    if($arg -like '--color=*'){$Color=$arg.Substring(8);continue}
    if($arg -in @('-h','--help','-?')){Show-Usage;return}
    throw "Unknown option: $arg`nUsage: ./uninstall.ps1 [options]"
}
$Format=$Format.ToLowerInvariant();$Color=$Color.ToLowerInvariant()
if($Format -notin @('human','plain','json')){throw "Invalid format: $Format"}
if($Color -notin @('auto','always','never')){throw "Invalid color mode: $Color"}

$scriptRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$uiPath=$null
foreach($candidate in @(
    (Join-Path $scriptRoot 'dot_config\terminal-env\powershell\output.ps1'),
    (Join-Path $HOME '.config\terminal-env\powershell\output.ps1')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$uiPath=$candidate;break}
}
$uiAvailable=$false
if($uiPath){
    try{. $uiPath;Initialize-TerminalEnvUI -Format $Format -ColorMode $Color;$uiAvailable=$true}catch{}
}
function Safe-Text([AllowNull()][object]$Value){
    if($uiAvailable){return (Get-TerminalEnvSafeText $Value)}
    if($null -eq $Value){return ''}
    return [regex]::Replace([string]$Value,'[\x00-\x1F\x7F]',' ')
}

$ErrorActionPreference='Stop'
$State=if($env:TERMINAL_ENV_STATE){$env:TERMINAL_ENV_STATE}else{Join-Path $HOME '.local\state\terminal-env'}
$backupState=Join-Path $State 'original-backup'
$Backup=if(Test-Path -LiteralPath $backupState -PathType Leaf){(Get-Content -LiteralPath $backupState -Raw).Trim()}else{''}
$profilePath=if(Test-Path -LiteralPath (Join-Path $State 'powershell-profile-path') -PathType Leaf){(Get-Content -LiteralPath (Join-Path $State 'powershell-profile-path') -Raw).Trim()}else{''}
$terminalSettings=if(Test-Path -LiteralPath (Join-Path $State 'windows-terminal-settings-path') -PathType Leaf){(Get-Content -LiteralPath (Join-Path $State 'windows-terminal-settings-path') -Raw).Trim()}else{''}
$restoreAvailable=$false
if($Restore){
    if(-not $Backup){throw 'No pre-install restore point is recorded. Re-run with --no-restore only if removing managed files without restoration is intentional.'}
    if(-not(Test-Path -LiteralPath $Backup -PathType Container)){throw 'The recorded pre-install restore point is missing. Re-run with --no-restore only if removing managed files without restoration is intentional.'}
    try{Get-ChildItem -LiteralPath $Backup -Force -Recurse -ErrorAction Stop|Out-Null}catch{throw 'The pre-install restore point could not be read safely; no files were changed.'}
    $restoreAvailable=$true
}

function Write-UninstallPlan {
    if($Quiet -or $Format -ne 'human'){return}
    if($uiAvailable){
        Write-TerminalEnvTitle uninstall
        Write-TerminalEnvSection Plan
        Write-TerminalEnvRow 'Managed files' remove
        if($restoreAvailable){Write-TerminalEnvRow 'Original files' "restore · $(Safe-Text $Backup)"}
        else{Write-TerminalEnvRow 'Original files' 'leave removed' warning}
        if($profilePath){Write-TerminalEnvRow 'PowerShell profile' $(if($restoreAvailable){'restore previous state'}else{'remove managed block'})}
        if($terminalSettings){Write-TerminalEnvRow 'Windows Terminal' $(if($restoreAvailable){'restore previous state'}else{'leave user settings unchanged'})}
        Write-TerminalEnvRow 'Packages/history' preserve
        Write-TerminalEnvMeta 'WinGet/system packages and history databases are not removed.'
        return
    }
    Write-Output 'Terminal Environment · uninstall'
    Write-Output ''
    Write-Output 'Plan'
    Write-Output '  Managed files      remove'
    if($restoreAvailable){Write-Output "  Original files     restore · $(Safe-Text $Backup)"}else{Write-Output '  Original files     leave removed'}
    if($profilePath){Write-Output "  PowerShell profile  $(if($restoreAvailable){'restore previous state'}else{'remove managed block'})"}
    if($terminalSettings){Write-Output "  Windows Terminal    $(if($restoreAvailable){'restore previous state'}else{'leave user settings unchanged'})"}
    Write-Output '  Packages/history   preserve'
    Write-Output ''
    Write-Output 'WinGet/system packages and history databases are not removed.'
}
function Write-UninstallResult {
    param([ValidateSet('planned','cancelled','uninstalled')][string]$Status,[bool]$Restored=$false)
    if($Quiet){return}
    if($Format -eq 'json'){
        [pscustomobject]@{
            command='uninstall';status=$Status;restore_requested=[bool]$Restore;restore_available=[bool]$restoreAvailable
            restored=$Restored;backup=Safe-Text $Backup;packages_preserved=$true;history_preserved=$true
        }|ConvertTo-Json -Compress
        return
    }
    if($Format -eq 'plain'){
        Write-Output "uninstall`t$Status`t$([int]$Restore)`t$([int]$Restored)`t$(Safe-Text $Backup)"
        return
    }
    if($uiAvailable){
        switch($Status){
            'planned'{Write-TerminalEnvOutcome accent 'Dry run complete · no changes applied'}
            'cancelled'{Write-TerminalEnvOutcome text 'Cancelled · no changes applied'}
            'uninstalled'{
                if($Restored){Write-TerminalEnvOutcome success 'Uninstalled · original files restored'}
                else{Write-TerminalEnvOutcome success 'Uninstalled · managed files removed'}
                Write-TerminalEnvMeta 'WinGet/system packages and history databases were preserved.'
            }
        }
        return
    }
    switch($Status){
        'planned'{Write-Output '';Write-Output 'Dry run complete · no changes applied'}
        'cancelled'{Write-Output '';Write-Output 'Cancelled · no changes applied'}
        'uninstalled'{
            Write-Output ''
            if($Restored){Write-Output 'Uninstalled · original files restored'}else{Write-Output 'Uninstalled · managed files removed'}
            Write-Output 'WinGet/system packages and history databases were preserved.'
        }
    }
}

Write-UninstallPlan
if($DryRun){Write-UninstallResult planned;return}
if(-not $Yes){
    if($Quiet){throw 'Uninstall requires --yes when --quiet is used.'}
    if($NoInput){throw 'Uninstall requires --yes when --no-input is used.'}
    if($Format -ne 'human'){throw 'Uninstall requires --yes for plain or JSON output.'}
    $redirected=$true
    try{$redirected=[Console]::IsInputRedirected}catch{}
    if($redirected){throw 'Uninstall requires --yes when stdin is not interactive.'}
    $answer=Read-Host 'Continue? [y/N]'
    if($answer -notmatch '(?i)^(y|yes)$'){Write-UninstallResult cancelled;return}
}

$managed=@(
    '.config\oh-my-posh','.config\atuin','.config\terminal-env','.local\share\terminal-env',
    '.local\bin\oh-my-posh.exe','.local\bin\atuin.exe','.local\bin\fzf.exe','.local\bin\zoxide.exe','.local\bin\chezmoi.exe'
)
$fragment=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
$rollbackRoot=Join-Path ([IO.Path]::GetTempPath()) ("terminal-env-uninstall-"+[guid]::NewGuid())
New-Item -ItemType Directory -Path $rollbackRoot|Out-Null
function Save-UninstallPath([string]$Path,[string]$Snapshot){
    if(-not(Test-Path -LiteralPath $Path)){return}
    $parent=Split-Path -Parent $Snapshot
    if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    Copy-Item -LiteralPath $Path -Destination $Snapshot -Recurse -Force
}
function Restore-UninstallPath([string]$Path,[string]$Snapshot){
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if(-not(Test-Path -LiteralPath $Snapshot)){return}
    $parent=Split-Path -Parent $Path
    if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    Copy-Item -LiteralPath $Snapshot -Destination $Path -Recurse -Force
}
foreach($rel in $managed){Save-UninstallPath (Join-Path $HOME $rel) (Join-Path $rollbackRoot ("home\"+$rel))}
Save-UninstallPath $fragment (Join-Path $rollbackRoot 'external\WindowsTerminal-fragment')
if($profilePath){Save-UninstallPath $profilePath (Join-Path $rollbackRoot 'external\PowerShell-profile.ps1')}
if($terminalSettings){Save-UninstallPath $terminalSettings (Join-Path $rollbackRoot 'external\WindowsTerminal-settings.json')}
$fontKey='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$currentFontRegistry=@{}
foreach($style in 'Regular','Bold','Italic','BoldItalic'){
    $name="Terminal Environment Monaspice Neon $style (TrueType)"
    $item=Get-ItemProperty -LiteralPath $fontKey -Name $name -ErrorAction SilentlyContinue
    if($item){$property=$item.PSObject.Properties[$name];if($property){$currentFontRegistry[$name]=$property.Value}}
}

try{
    foreach($rel in $managed){Remove-Item -LiteralPath (Join-Path $HOME $rel) -Recurse -Force -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $fragment -Recurse -Force -ErrorAction SilentlyContinue
    foreach($style in 'Regular','Bold','Italic','BoldItalic'){
        Remove-ItemProperty -LiteralPath $fontKey -Name "Terminal Environment Monaspice Neon $style (TrueType)" -Force -ErrorAction SilentlyContinue
    }

    if($restoreAvailable){
        $homeBackup=Join-Path $Backup 'home'
        if(Test-Path -LiteralPath $homeBackup -PathType Container){Get-ChildItem -LiteralPath $homeBackup -Force|Copy-Item -Destination $HOME -Recurse -Force}

        $oldProfile=Join-Path $Backup 'external\PowerShell-profile.ps1'
        $profileExisted=Join-Path $Backup 'external\PowerShell-profile-existed'
        if($profilePath){
            if(Test-Path -LiteralPath $oldProfile -PathType Leaf){Copy-Item -LiteralPath $oldProfile -Destination $profilePath -Force}
            elseif((Test-Path -LiteralPath $profileExisted -PathType Leaf)-and((Get-Content -LiteralPath $profileExisted -Raw).Trim()-eq '0')){Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue}
            elseif(Test-Path -LiteralPath $profilePath -PathType Leaf){
                $text=Get-Content -LiteralPath $profilePath -Raw
                $text=[regex]::Replace($text,'(?s)\r?\n?# BEGIN TERMINAL-ENV.*?# END TERMINAL-ENV\r?\n?','')
                Set-Content -LiteralPath $profilePath -Value $text -Encoding utf8NoBOM -NoNewline
            }
        }

        $oldFragment=Join-Path $Backup 'external\WindowsTerminal-fragment'
        if(Test-Path -LiteralPath $oldFragment -PathType Container){Copy-Item -LiteralPath $oldFragment -Destination $fragment -Recurse -Force}
        $oldSettings=Join-Path $Backup 'external\WindowsTerminal-settings.json'
        if($terminalSettings -and (Test-Path -LiteralPath $oldSettings -PathType Leaf)){Copy-Item -LiteralPath $oldSettings -Destination $terminalSettings -Force}
        $fontRegistry=Join-Path $Backup 'external\font-registry.json'
        if(Test-Path -LiteralPath $fontRegistry -PathType Leaf){
            $saved=Get-Content -LiteralPath $fontRegistry -Raw|ConvertFrom-Json
            foreach($style in 'Regular','Bold','Italic','BoldItalic'){
                $name="Terminal Environment Monaspice Neon $style (TrueType)"
                $property=$saved.PSObject.Properties[$name]
                if($property -and $null -ne $property.Value){New-ItemProperty -LiteralPath $fontKey -Name $name -Value $property.Value -PropertyType String -Force|Out-Null}
            }
        }
    }elseif($profilePath -and (Test-Path -LiteralPath $profilePath -PathType Leaf)){
        $text=Get-Content -LiteralPath $profilePath -Raw
        $text=[regex]::Replace($text,'(?s)\r?\n?# BEGIN TERMINAL-ENV.*?# END TERMINAL-ENV\r?\n?','')
        Set-Content -LiteralPath $profilePath -Value $text -Encoding utf8NoBOM -NoNewline
    }
}catch{
    $uninstallError=$_
    [Console]::Error.WriteLine('Could not complete uninstall; restoring the managed state that was active before the command.')
    try{
        foreach($rel in $managed){Restore-UninstallPath (Join-Path $HOME $rel) (Join-Path $rollbackRoot ("home\"+$rel))}
        Restore-UninstallPath $fragment (Join-Path $rollbackRoot 'external\WindowsTerminal-fragment')
        if($profilePath){Restore-UninstallPath $profilePath (Join-Path $rollbackRoot 'external\PowerShell-profile.ps1')}
        if($terminalSettings){Restore-UninstallPath $terminalSettings (Join-Path $rollbackRoot 'external\WindowsTerminal-settings.json')}
        foreach($style in 'Regular','Bold','Italic','BoldItalic'){
            $name="Terminal Environment Monaspice Neon $style (TrueType)"
            Remove-ItemProperty -LiteralPath $fontKey -Name $name -Force -ErrorAction SilentlyContinue
            if($currentFontRegistry.ContainsKey($name)){New-ItemProperty -LiteralPath $fontKey -Name $name -Value $currentFontRegistry[$name] -PropertyType String -Force|Out-Null}
        }
        [Console]::Error.WriteLine('Managed files were restored. The pre-install restore point was left unchanged.')
    }catch{
        [Console]::Error.WriteLine('Automatic uninstall recovery was incomplete; the pre-install restore point was left unchanged for manual recovery.')
    }
    Remove-Item -LiteralPath $rollbackRoot -Recurse -Force -ErrorAction SilentlyContinue
    throw $uninstallError
}
Remove-Item -LiteralPath $rollbackRoot -Recurse -Force -ErrorAction SilentlyContinue

$fontManifest=Join-Path $State 'fonts\current.json'
if(Test-Path -LiteralPath $fontManifest -PathType Leaf){
    try{
        foreach($font in @(Get-Content -LiteralPath $fontManifest -Raw|ConvertFrom-Json)){
            if($font.owned -and $font.path){
                try{Remove-Item -LiteralPath $font.path -Force -ErrorAction Stop}
                catch{[Console]::Error.WriteLine("Managed font is still locked and will remain until a later cleanup: $(Safe-Text $font.path)")}
            }
        }
    }catch{[Console]::Error.WriteLine('Could not parse managed font manifest during uninstall.')}
}

if($restoreAvailable){
    Remove-Item -LiteralPath (Join-Path $State 'backups\transactions') -Recurse -Force -ErrorAction SilentlyContinue
    foreach($directory in @(Get-ChildItem -LiteralPath (Join-Path $State 'backups') -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -notin @('manual','transactions') -and ($_.Name -like 'install-*' -or $_.Name -match '^20\d{6}T\d{6}Z')})){
        Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $backupState -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $State 'last-install-backup') -Force -ErrorAction SilentlyContinue
}

Write-UninstallResult uninstalled $restoreAvailable

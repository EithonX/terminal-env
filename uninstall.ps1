[CmdletBinding()] param([switch]$NoRestore)
$ErrorActionPreference='Stop'
$State=Join-Path $HOME '.local\state\terminal-env'
$Backup=if(Test-Path (Join-Path $State 'original-backup')){(Get-Content (Join-Path $State 'original-backup') -Raw).Trim()}else{''}
$profilePath=if(Test-Path (Join-Path $State 'powershell-profile-path')){(Get-Content (Join-Path $State 'powershell-profile-path') -Raw).Trim()}else{''}
$terminalSettings=if(Test-Path (Join-Path $State 'windows-terminal-settings-path')){(Get-Content (Join-Path $State 'windows-terminal-settings-path') -Raw).Trim()}else{''}
$managed=@('.config\oh-my-posh','.config\atuin','.config\terminal-env','.local\share\terminal-env','.local\bin\oh-my-posh.exe','.local\bin\atuin.exe','.local\bin\fzf.exe','.local\bin\zoxide.exe','.local\bin\chezmoi.exe')
foreach($rel in $managed){ Remove-Item -Recurse -Force (Join-Path $HOME $rel) -ErrorAction SilentlyContinue }
Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env') -ErrorAction SilentlyContinue
$oldFrag=if($Backup){Join-Path $Backup 'external\WindowsTerminal-fragment'}else{''}; if($oldFrag -and (Test-Path $oldFrag)){ Copy-Item -Recurse -Force $oldFrag (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env') }
if(-not $NoRestore -and $Backup -and (Test-Path $Backup)){
    $homeBackup=Join-Path $Backup 'home'; if(Test-Path $homeBackup){ Get-ChildItem -Force $homeBackup | Copy-Item -Destination $HOME -Recurse -Force }
    $oldpp=Join-Path $Backup 'external\PowerShell-profile.ps1'; $ppExisted=Join-Path $Backup 'external\PowerShell-profile-existed'
    if($profilePath){
      if(Test-Path $oldpp){ Copy-Item -Force $oldpp $profilePath }
      elseif((Test-Path $ppExisted) -and ((Get-Content $ppExisted -Raw).Trim() -eq '0')){ Remove-Item -Force $profilePath -ErrorAction SilentlyContinue }
      elseif(Test-Path $profilePath){ $text=Get-Content $profilePath -Raw; $text=[regex]::Replace($text,'(?s)\r?\n?# BEGIN TERMINAL-ENV.*?# END TERMINAL-ENV\r?\n?',''); Set-Content -LiteralPath $profilePath -Value $text -Encoding utf8NoBOM -NoNewline }
    }
    $oldwt=Join-Path $Backup 'external\WindowsTerminal-settings.json'; if($terminalSettings -and (Test-Path $oldwt)){ Copy-Item -Force $oldwt $terminalSettings }
    Write-Host "Restored original pre-install files from $Backup" -ForegroundColor Green
}else{ Write-Host 'Managed configuration removed; persistent history and backups were left in place.' }
Write-Host 'WinGet/system packages and history databases were intentionally left installed/preserved.'

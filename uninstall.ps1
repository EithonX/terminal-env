[CmdletBinding()] param([switch]$NoRestore)
$ErrorActionPreference='Stop'
$State=Join-Path $HOME '.local\state\terminal-env'
$Backup=if(Test-Path (Join-Path $State 'original-backup')){(Get-Content (Join-Path $State 'original-backup') -Raw).Trim()}else{''}
$profilePath=if(Test-Path (Join-Path $State 'powershell-profile-path')){(Get-Content (Join-Path $State 'powershell-profile-path') -Raw).Trim()}else{''}
$terminalSettings=if(Test-Path (Join-Path $State 'windows-terminal-settings-path')){(Get-Content (Join-Path $State 'windows-terminal-settings-path') -Raw).Trim()}else{''}
$fontManifest=Join-Path $State 'fonts\current.json'
if(Test-Path -LiteralPath $fontManifest){
    try{
        foreach($font in @(Get-Content -LiteralPath $fontManifest -Raw|ConvertFrom-Json)){
            if($font.owned -and $font.path){ try{Remove-Item -LiteralPath $font.path -Force -ErrorAction Stop}catch{Write-Warning "Managed font is still locked and will remain until a later cleanup: $($font.path)"} }
        }
    }catch{Write-Warning 'Could not parse managed font manifest during uninstall.'}
}
$fontKey='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
foreach($style in 'Regular','Bold','Italic','BoldItalic'){
    Remove-ItemProperty -LiteralPath $fontKey -Name "Terminal Environment Monaspice Neon $style (TrueType)" -Force -ErrorAction SilentlyContinue
}
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
    Remove-Item -LiteralPath (Join-Path $State 'backups\transactions') -Recurse -Force -ErrorAction SilentlyContinue
    foreach($d in @(Get-ChildItem -LiteralPath (Join-Path $State 'backups') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('manual','transactions') -and ($_.Name -like 'install-*' -or $_.Name -match '^20\d{6}T\d{6}Z') })) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $State 'original-backup') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $State 'last-install-backup') -Force -ErrorAction SilentlyContinue
}else{ Write-Host 'Managed configuration removed; persistent history and backups were left in place.' }
Write-Host 'WinGet/system packages and history databases were intentionally left installed/preserved.'

$pass=0;$warn=0;$fail=0
function P($s){Write-Host "PASS  $s" -ForegroundColor Green;$script:pass++}; function W($s){Write-Host "WARN  $s" -ForegroundColor Yellow;$script:warn++}; function F($s){Write-Host "FAIL  $s" -ForegroundColor Red;$script:fail++}
function Size-Bytes([string]$Path){ if(-not(Test-Path -LiteralPath $Path)){return [int64]0}; [int64]$n=0; Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue|ForEach-Object{$n+=$_.Length}; return $n }
function Human([int64]$n){ if($n-ge 1GB){'{0:N1} GiB'-f($n/1GB)}elseif($n-ge 1MB){'{0:N1} MiB'-f($n/1MB)}elseif($n-ge 1KB){'{0:N1} KiB'-f($n/1KB)}else{"$n B"} }
$state=Join-Path $HOME '.local\state\terminal-env'; $source=Join-Path $HOME '.local\share\terminal-env\source'
Write-Host 'Terminal Environment doctor'
if(Test-Path (Join-Path $state 'original-backup')){P 'original pre-install restore point recorded'}else{W 'original restore point is not recorded'}
$tx=Join-Path $state 'backups\transactions'; $manual=Join-Path $state 'backups\manual'
$txCount=@(Get-ChildItem -LiteralPath $tx -Directory -Filter 'install-*' -ErrorAction SilentlyContinue).Count
$manualCount=@(Get-ChildItem -LiteralPath $manual -File -Filter 'manual-*' -ErrorAction SilentlyContinue).Count
P "storage: $txCount retained transaction backup(s), $(Human (Size-Bytes $tx))"
P "manual backups: $manualCount, $(Human (Size-Bytes $manual)) (never auto-pruned)"
$pwsh=Get-Command pwsh -ErrorAction SilentlyContinue
if($pwsh){
    try{$pwshVersion=(& $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | Out-String).Trim()}catch{$pwshVersion='unknown'}
    P "PowerShell: $pwshVersion ($($pwsh.Source))"
}else{F 'PowerShell 7 (pwsh) is missing'}
$msixPowerShell=@(Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue)
$msiPowerShell=@(Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue | Where-Object DisplayName -Match '^PowerShell 7')
if($msixPowerShell.Count -and $msiPowerShell.Count){
    W "both MSI and MSIX PowerShell 7 installations are present; pwsh currently resolves to $($pwsh.Source)"
}
foreach($c in 'git','oh-my-posh','atuin','fzf','zoxide','chezmoi'){ $x=Get-Command $c -ErrorAction SilentlyContinue;if($x){P "${c}: $($x.Source)"}else{W "$c is missing; related features degrade gracefully"} }
$theme=Join-Path $HOME '.config\oh-my-posh\terminal.omp.json'; try{Get-Content $theme -Raw|ConvertFrom-Json|Out-Null;P 'Oh My Posh theme parses'}catch{F 'Oh My Posh theme is missing or invalid'}
$managed=Join-Path $HOME '.config\terminal-env\powershell\profile.ps1'; if(Test-Path $managed){P 'managed PowerShell profile is installed'}else{F 'managed PowerShell profile is missing'}
$frag=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env\terminal-env.json';if(Test-Path $frag){try{Get-Content $frag -Raw|ConvertFrom-Json|Out-Null;P 'Windows Terminal fragment parses'}catch{F 'Windows Terminal fragment is invalid'}}else{W 'Windows Terminal fragment absent'}
$fontManifest=Join-Path $state 'fonts\current.json'
if(Test-Path -LiteralPath $fontManifest){
    try{
        $fonts=@(Get-Content -LiteralPath $fontManifest -Raw|ConvertFrom-Json); [int64]$bytes=0; $present=0
        foreach($font in $fonts){ if(Test-Path -LiteralPath $font.path){$present++;$bytes+=(Get-Item -LiteralPath $font.path).Length} }
        if($present -eq 4){P "managed font set: 4 RIBBI faces, $(Human $bytes)"}else{W "managed font set is incomplete: $present/4 faces present"}
    }catch{W 'managed font manifest is invalid'}
}else{
    $font=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue).PSObject.Properties.Name|Where-Object{$_ -match 'MonaspiceNe'};if($font){W 'Monaspice Neon is registered but predates managed font tracking; the installer will adopt matching faces without overwriting them'}else{W 'Monaspice Neon font was not detected'}
}
$stale=Join-Path $state 'fonts\stale.txt'; if(Test-Path -LiteralPath $stale){$n=@(Get-Content -LiteralPath $stale|Where-Object{$_}).Count;W "$n stale managed font file(s) are still locked; terminal-deps sync will retry cleanup"}
try{atuin search --limit 1 --cmd-only '' *> $null;if($LASTEXITCODE -eq 0){P 'Atuin history database is readable'}else{W 'Atuin history database check failed'}}catch{W 'Atuin history database check failed'}
if(Test-Path (Join-Path $source '.git')){P 'installed source is Git-backed and updateable'}else{W 'installed source is not Git-backed'}
if(Test-Path (Join-Path $state 'deps-pending')){W 'source update changed dependency pins; run terminal-deps sync'}else{P 'dependency manifest is synchronized with the last source apply'}
if(Test-Path (Join-Path $source 'tests\smoke.ps1')){try{& (Join-Path $source 'tests\smoke.ps1') *> $null;P 'installed source smoke tests pass'}catch{F 'installed source smoke tests failed'}}
Write-Host "`nSummary: $pass pass, $warn warning, $fail failure"; if($fail){exit 1}

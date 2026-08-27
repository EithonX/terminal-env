$pass=0;$warn=0;$fail=0
function P($s){Write-Host "PASS  $s" -ForegroundColor Green;$script:pass++}; function W($s){Write-Host "WARN  $s" -ForegroundColor Yellow;$script:warn++}; function F($s){Write-Host "FAIL  $s" -ForegroundColor Red;$script:fail++}
$state=Join-Path $HOME '.local\state\terminal-env'; $source=Join-Path $HOME '.local\share\terminal-env\source'
Write-Host 'Terminal Environment doctor'
if(Test-Path (Join-Path $state 'original-backup')){P 'original pre-install restore point recorded'}else{W 'original restore point is not recorded'}
foreach($c in 'pwsh','git','oh-my-posh','atuin','fzf','zoxide','chezmoi'){ $x=Get-Command $c -ErrorAction SilentlyContinue;if($x){P "${c}: $($x.Source)"}else{W "$c is missing; related features degrade gracefully"} }
$theme=Join-Path $HOME '.config\oh-my-posh\terminal.omp.json'; try{Get-Content $theme -Raw|ConvertFrom-Json|Out-Null;P 'Oh My Posh theme parses'}catch{F 'Oh My Posh theme is missing or invalid'}
$managed=Join-Path $HOME '.config\terminal-env\powershell\profile.ps1'; if(Test-Path $managed){P 'managed PowerShell profile is installed'}else{F 'managed PowerShell profile is missing'}
$frag=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env\terminal-env.json';if(Test-Path $frag){try{Get-Content $frag -Raw|ConvertFrom-Json|Out-Null;P 'Windows Terminal fragment parses'}catch{F 'Windows Terminal fragment is invalid'}}else{W 'Windows Terminal fragment absent'}
$font=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue).PSObject.Properties.Name|Where-Object{$_ -match 'MonaspiceNe'};if($font){P 'Monaspice Neon font registered'}else{W 'Monaspice Neon font was not detected'}
try{atuin search --limit 1 --cmd-only '' *> $null;if($LASTEXITCODE -eq 0){P 'Atuin history database is readable'}else{W 'Atuin history database check failed'}}catch{W 'Atuin history database check failed'}
if(Test-Path (Join-Path $source '.git')){P 'installed source is Git-backed and updateable'}else{W 'installed source is not Git-backed'}
if(Test-Path (Join-Path $state 'deps-pending')){W 'source update changed dependency pins; run terminal-deps sync'}else{P 'dependency manifest is synchronized with the last source apply'}
if(Test-Path (Join-Path $source 'tests\smoke.ps1')){try{& (Join-Path $source 'tests\smoke.ps1') *> $null;P 'installed source smoke tests pass'}catch{F 'installed source smoke tests failed'}}
Write-Host "`nSummary: $pass pass, $warn warning, $fail failure"; if($fail){exit 1}

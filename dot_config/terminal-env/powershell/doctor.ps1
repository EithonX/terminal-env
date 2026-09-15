$Quick=$false
$Format='human'
$Color='auto'
$Detailed=$false
$Quiet=$false

function Show-Usage {
    Write-Output @'
Usage: terminal doctor [options]
       terminal-doctor [options]

Options:
  --quick                 Skip slower checks.
  --format human|plain|json
  --color auto|always|never
  --verbose               Show every successful check in human output.
  --quiet                 Print nothing; use the exit status only.
  -h, --help              Show this help.
'@
}

for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('--quick','-Quick')){$Quick=$true;continue}
    if($arg -in @('--verbose','-Verbose')){$Detailed=$true;continue}
    if($arg -in @('--quiet','-Quiet')){$Quiet=$true;continue}
    if($arg -in @('--format','-Format')){
        if($i+1 -ge $args.Count){throw "Missing value for $arg."}
        $i++;$Format=[string]$args[$i];continue
    }
    if($arg -like '--format=*'){$Format=$arg.Substring(9);continue}
    if($arg -in @('--color','-Color')){
        if($i+1 -ge $args.Count){throw "Missing value for $arg."}
        $i++;$Color=[string]$args[$i];continue
    }
    if($arg -like '--color=*'){$Color=$arg.Substring(8);continue}
    if($arg -in @('-h','--help','-?')){Show-Usage;return}
    throw "Unknown option: $arg`nUsage: terminal doctor [options]
       terminal-doctor [options]"
}
$Format=$Format.ToLowerInvariant()
$Color=$Color.ToLowerInvariant()
if($Format -notin @('human','plain','json')){throw "Invalid format: $Format"}
if($Color -notin @('auto','always','never')){throw "Invalid color mode: $Color"}

. (Join-Path $PSScriptRoot 'output.ps1')
Initialize-TerminalEnvUI -Format $Format -ColorMode $Color
$ErrorActionPreference='Stop'

$checks=[System.Collections.Generic.List[object]]::new()
$pass=0;$warn=0;$fail=0
function Add-Check {
    param(
        [string]$Id,
        [ValidateSet('pass','warn','fail')][string]$Status,
        [string]$Section,
        [string]$Label,
        [AllowEmptyString()][string]$Value='',
        [AllowEmptyString()][string]$Detail='',
        [bool]$Inventory=$false
    )
    $checks.Add([pscustomobject]@{
        id=Get-TerminalEnvSafeText $Id
        status=$Status
        section=Get-TerminalEnvSafeText $Section
        label=Get-TerminalEnvSafeText $Label
        value=Get-TerminalEnvSafeText $Value
        detail=Get-TerminalEnvSafeText $Detail
        inventory=$Inventory
    }) | Out-Null
    switch($Status){'pass'{$script:pass++};'warn'{$script:warn++};'fail'{$script:fail++}}
}
function Size-Bytes([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return [int64]0};[int64]$n=0;Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue|ForEach-Object{$n+=$_.Length};return $n}
function Human([int64]$n){if($n-ge 1GB){'{0:N1} GiB'-f($n/1GB)}elseif($n-ge 1MB){'{0:N1} MiB'-f($n/1MB)}elseif($n-ge 1KB){'{0:N1} KiB'-f($n/1KB)}else{"$n B"}}
function Tool-Version($Command){
    try{$line=[string](& $Command.Source --version 2>$null|Select-Object -First 1)}catch{$line=''}
    $match=[regex]::Match($line,'[vV]?\d+(?:\.\d+)+(?:[.-][0-9A-Za-z]+)*')
    if($match.Success){return $match.Value}
    return (Get-TerminalEnvSafeText $line)
}

$state=Join-Path $HOME '.local\state\terminal-env'
$source=Join-Path $HOME '.local\share\terminal-env\source'
$managedProfile=if(Test-Path -LiteralPath (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'unknown'}

if(Test-Path -LiteralPath (Join-Path $state 'original-backup')){Add-Check restore_point pass Safety 'Restore point' recorded}
else{Add-Check restore_point warn Safety 'Restore point' missing 'original pre-install restore point is not recorded'}
$tx=Join-Path $state 'backups\transactions';$manual=Join-Path $state 'backups\manual'
$txCount=@(Get-ChildItem -LiteralPath $tx -Directory -Filter 'install-*' -ErrorAction SilentlyContinue).Count
$manualCount=@(Get-ChildItem -LiteralPath $manual -File -Filter 'manual-*' -ErrorAction SilentlyContinue).Count
Add-Check transaction_backups pass Safety 'Transaction backups' "$txCount · $(Human (Size-Bytes $tx))"
Add-Check manual_backups pass Safety 'Manual backups' "$manualCount · $(Human (Size-Bytes $manual))" 'never auto-pruned'

$pwsh=Get-Command pwsh -ErrorAction SilentlyContinue
if($pwsh){
    try{$pwshVersion=(& $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'|Out-String).Trim()}catch{$pwshVersion='unknown'}
    Add-Check pwsh pass Shell PowerShell $pwshVersion $pwsh.Source $true
}else{Add-Check pwsh fail Shell PowerShell missing 'PowerShell 7 (pwsh) is missing' $true}
$git=Get-Command git -ErrorAction SilentlyContinue
if($git){Add-Check git pass Shell Git (Tool-Version $git) '' $true}else{Add-Check git warn Shell Git missing 'git is missing; updates and repository diagnostics are unavailable' $true}

$msixPowerShell=@(Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue)
$msiPowerShell=@(Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue|Where-Object DisplayName -Match '^PowerShell 7')
if($msixPowerShell.Count -and $msiPowerShell.Count){
    $resolved=if($pwsh){$pwsh.Source}else{'no pwsh on PATH'}
    Add-Check powershell_provenance warn Shell PowerShell mixed "MSI and MSIX installations are both present; pwsh resolves to $resolved"
}

foreach($spec in @(
    @('oh_my_posh','oh-my-posh','Oh My Posh'),
    @('atuin','atuin','Atuin'),
    @('fzf','fzf','fzf'),
    @('zoxide','zoxide','zoxide'),
    @('chezmoi','chezmoi','chezmoi')
)){
    $cmd=Get-Command $spec[1] -ErrorAction SilentlyContinue
    if($cmd){Add-Check $spec[0] pass Tools $spec[2] (Tool-Version $cmd) $cmd.Source $true}
    else{Add-Check $spec[0] warn Tools $spec[2] missing "$($spec[1]) is missing; related features degrade gracefully" $true}
}

$theme=Join-Path $HOME '.config\oh-my-posh\terminal.omp.json'
if(Test-Path -LiteralPath $theme){
    try{Get-Content -LiteralPath $theme -Raw|ConvertFrom-Json|Out-Null;Add-Check omp_theme pass Configuration 'Oh My Posh theme' parses}
    catch{Add-Check omp_theme fail Configuration 'Oh My Posh theme' invalid 'theme is invalid JSON'}
}else{Add-Check omp_theme warn Configuration 'Oh My Posh theme' missing 'theme is absent'}
$managed=Join-Path $HOME '.config\terminal-env\powershell\profile.ps1'
if(Test-Path -LiteralPath $managed){Add-Check managed_profile pass Configuration 'PowerShell profile' installed}
else{Add-Check managed_profile fail Configuration 'PowerShell profile' missing 'managed PowerShell profile is missing'}
$frag=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env\terminal-env.json'
if(Test-Path -LiteralPath $frag){
    try{Get-Content -LiteralPath $frag -Raw|ConvertFrom-Json|Out-Null;Add-Check terminal_fragment pass Configuration 'Windows Terminal' parses}
    catch{Add-Check terminal_fragment fail Configuration 'Windows Terminal' invalid 'managed fragment is invalid'}
}else{Add-Check terminal_fragment warn Configuration 'Windows Terminal' missing 'managed fragment is absent'}

$fontManifest=Join-Path $state 'fonts\current.json'
if(Test-Path -LiteralPath $fontManifest){
    try{
        $fonts=@(Get-Content -LiteralPath $fontManifest -Raw|ConvertFrom-Json);[int64]$bytes=0;$present=0
        foreach($font in $fonts){if(Test-Path -LiteralPath $font.path){$present++;$bytes+=(Get-Item -LiteralPath $font.path).Length}}
        if($present -eq 4){Add-Check managed_fonts pass Tools 'Managed fonts' "4 faces · $(Human $bytes)"}
        else{Add-Check managed_fonts warn Tools 'Managed fonts' "$present/4 faces" 'managed font set is incomplete'}
    }catch{Add-Check managed_fonts warn Tools 'Managed fonts' invalid 'managed font manifest is invalid'}
}else{
    $font=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue).PSObject.Properties.Name|Where-Object{$_ -match 'MonaspiceNe'}
    if($font){Add-Check managed_fonts warn Tools 'Managed fonts' untracked 'Monaspice Neon is registered but predates managed font tracking'}
    else{Add-Check managed_fonts warn Tools 'Managed fonts' missing 'Monaspice Neon font was not detected'}
}
$stale=Join-Path $state 'fonts\stale.txt'
if(Test-Path -LiteralPath $stale){$n=@(Get-Content -LiteralPath $stale|Where-Object{$_}).Count;Add-Check stale_fonts warn Tools 'Managed fonts' "$n stale" 'locked managed font files remain; terminal deps sync will retry cleanup'}

$atuin=Get-Command atuin -ErrorAction SilentlyContinue
if($atuin){
    try{& $atuin.Source search --limit 1 --cmd-only '' *> $null;if($LASTEXITCODE -eq 0){Add-Check atuin_database pass Configuration 'Atuin database' readable}else{Add-Check atuin_database warn Configuration 'Atuin database' unreadable 'Atuin history database check failed'}}
    catch{Add-Check atuin_database warn Configuration 'Atuin database' unreadable 'Atuin history database check failed'}
}
if(Test-Path -LiteralPath (Join-Path $source '.git')){Add-Check git_source pass Safety 'Installed source' Git-backed}
else{Add-Check git_source warn Safety 'Installed source' static 'installed source is not Git-backed; automatic source update is unavailable'}
if(Test-Path -LiteralPath (Join-Path $state 'deps-pending')){Add-Check deps_manifest warn Safety Dependencies pending 'source update changed dependency pins; run terminal deps sync'}
else{Add-Check deps_manifest pass Safety Dependencies synchronized}
if(-not $Quick -and (Test-Path -LiteralPath (Join-Path $source 'tests\smoke.ps1'))){
    try{& (Join-Path $source 'tests\smoke.ps1') *> $null;Add-Check source_smoke pass Safety 'Installed source smoke' passes}
    catch{Add-Check source_smoke fail Safety 'Installed source smoke' failed 'installed source smoke tests failed'}
}

if(-not $Quiet){
    if($Format -eq 'json'){
        [pscustomobject]@{
            command='doctor';profile=Get-TerminalEnvSafeText $managedProfile;quick=[bool]$Quick
            summary=[pscustomobject]@{checks=$checks.Count;pass=$pass;warning=$warn;failure=$fail}
            checks=@($checks|ForEach-Object{[pscustomobject]@{id=$_.id;status=$_.status;section=$_.section;label=$_.label;value=$_.value;detail=$_.detail}})
        }|ConvertTo-Json -Depth 6
    }elseif($Format -eq 'plain'){
        Write-Output "meta`tprofile`t$(Get-TerminalEnvSafeText $managedProfile)"
        Write-Output "meta`tquick`t$([int]$Quick)"
        foreach($check in $checks){Write-Output "check`t$($check.status)`t$($check.id)`t$($check.section)`t$($check.label)`t$($check.value)`t$($check.detail)"}
        Write-Output "summary`t$($checks.Count)`t$pass`t$warn`t$fail"
    }else{
        Write-TerminalEnvTitle doctor
        if($warn -eq 0 -and $fail -eq 0 -and -not $Detailed){
            Write-TerminalEnvOutcome success "Healthy · $($checks.Count) checks"
        }else{
            if($Detailed){
                $edition=if($PSVersionTable.PSEdition){$PSVersionTable.PSEdition}else{'PowerShell'}
                Write-TerminalEnvMeta "$managedProfile · $edition · Windows"
                foreach($section in 'Shell','Tools','Safety','Configuration'){
                    $rows=@($checks|Where-Object{$_.status -eq 'pass' -and $_.section -eq $section})
                    if($rows.Count){Write-TerminalEnvSection $section;foreach($row in $rows){Write-TerminalEnvRow $row.label $row.value}}
                }
            }else{
                foreach($section in 'Shell','Tools'){
                    $rows=@($checks|Where-Object{$_.status -eq 'pass' -and $_.section -eq $section -and $_.inventory})
                    if($rows.Count){Write-TerminalEnvSection $section;foreach($row in $rows){Write-TerminalEnvRow $row.label $row.value}}
                }
            }
            $attention=@($checks|Where-Object{$_.status -ne 'pass'})
            if($attention.Count){
                Write-TerminalEnvSection Attention
                foreach($row in $attention){$message=if($row.detail){$row.detail}else{$row.value};Write-TerminalEnvAttention $row.status $row.label $message}
            }
            if($fail){Write-TerminalEnvOutcome danger "$($checks.Count) checks · $warn warnings · $fail failures"}
            elseif($warn){Write-TerminalEnvOutcome warning "$($checks.Count) checks · $warn need attention"}
            else{Write-TerminalEnvOutcome success "$($checks.Count) checks · healthy"}
        }
    }
}
if($fail){exit 1}

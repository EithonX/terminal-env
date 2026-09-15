$Action='status'
$ActionSet=$false
$DryRun=$false
$Format='human'
$Color='auto'
$Detailed=$false
$Quiet=$false

function Show-Usage {
    Write-Output @'
Usage: terminal deps [status|sync] [options]
       terminal-deps [status|sync] [options]

Actions:
  status                   Compare managed dependencies with versions.env.
  sync                     Reconcile dependencies without updating repo source.

Options:
  --dry-run                Show sync work without changing dependencies.
  --format human|plain|json
  --color auto|always|never
  --verbose                Show matching dependencies in human status output.
  --quiet                  Print no result output.
  -h, --help               Show this help.
'@
}

for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('-h','--help','-?')){Show-Usage;return}
    if($arg -in @('status','sync')){if($ActionSet){throw "Unexpected action: $arg"};$Action=$arg;$ActionSet=$true;continue}
    if($arg -eq '-Action'){if($i+1 -ge $args.Count){throw 'Missing value for -Action.'};$i++;$value=[string]$args[$i];if($value -notin @('status','sync')){throw "Invalid action: $value"};if($ActionSet){throw "Unexpected action: $value"};$Action=$value.ToLowerInvariant();$ActionSet=$true;continue}
    if($arg -in @('--dry-run','-DryRun')){$DryRun=$true;continue}
    if($arg -in @('--verbose','-Verbose')){$Detailed=$true;continue}
    if($arg -in @('--quiet','-Quiet')){$Quiet=$true;continue}
    if($arg -in @('--format','-Format')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Format=[string]$args[$i];continue}
    if($arg -like '--format=*'){$Format=$arg.Substring(9);continue}
    if($arg -in @('--color','-Color')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Color=[string]$args[$i];continue}
    if($arg -like '--color=*'){$Color=$arg.Substring(8);continue}
    throw "Unknown option: $arg`nUsage: terminal deps [status|sync] [options]
       terminal-deps [status|sync] [options]"
}
$Format=$Format.ToLowerInvariant();$Color=$Color.ToLowerInvariant()
if($Format -notin @('human','plain','json')){throw "Invalid format: $Format"}
if($Color -notin @('auto','always','never')){throw "Invalid color mode: $Color"}
if($DryRun -and $Action -ne 'sync'){throw '--dry-run is only valid with sync.'}

. (Join-Path $PSScriptRoot 'output.ps1')
Initialize-TerminalEnvUI -Format $Format -ColorMode $Color
$ErrorActionPreference='Stop'
$source=Join-Path $HOME '.local\share\terminal-env\source'
$state=Join-Path $HOME '.local\state\terminal-env'
$manifest=Join-Path $source 'versions.env'
if(-not(Test-Path -LiteralPath $manifest)){throw 'Installed dependency manifest is missing.'}
$versions=@{}
Get-Content -LiteralPath $manifest|Where-Object{$_ -match '^[A-Z0-9_]+='}|ForEach-Object{$k,$v=$_ -split '=',2;$versions[$k]=$v}
$managedProfile=if(Test-Path -LiteralPath (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'workstation'}

function Tool-Version($Command){
    try{$line=[string](& $Command.Source --version 2>$null|Select-Object -First 1)}catch{$line=''}
    $match=[regex]::Match($line,'[vV]?\d+(?:\.\d+)+(?:[.-][0-9A-Za-z]+)*')
    if($match.Success){return $match.Value}
    return (Get-TerminalEnvSafeText $line)
}
function Version-Equal([string]$Actual,[string]$Pinned){return ($Actual -replace '^[vV]','') -eq ($Pinned -replace '^[vV]','')}

if($Action -eq 'status'){
    $dependencies=[System.Collections.Generic.List[object]]::new()
    $mismatch=0
    function Add-Dependency([string]$Id,[string]$Status,[string]$Category,[string]$Label,[string]$Installed,[string]$Pinned,[string]$Detail=''){
        $dependencies.Add([pscustomobject]@{
            id=Get-TerminalEnvSafeText $Id;status=$Status;category=$Category;label=Get-TerminalEnvSafeText $Label
            installed=Get-TerminalEnvSafeText $Installed;pinned=Get-TerminalEnvSafeText $Pinned;detail=Get-TerminalEnvSafeText $Detail
        })|Out-Null
        if($Status -ne 'match'){$script:mismatch++}
    }

    if($managedProfile -ne 'minimal'){
        foreach($spec in @(
            @('oh_my_posh','oh-my-posh','Oh My Posh','OH_MY_POSH_VERSION'),
            @('atuin','atuin','Atuin','ATUIN_VERSION'),
            @('fzf','fzf','fzf','FZF_VERSION'),
            @('zoxide','zoxide','zoxide','ZOXIDE_VERSION'),
            @('chezmoi','chezmoi','chezmoi','CHEZMOI_VERSION')
        )){
            $cmd=Get-Command $spec[1] -ErrorAction SilentlyContinue
            $want=[string]$versions[$spec[3]]
            $actual=if($cmd){Tool-Version $cmd}else{'missing'}
            if($cmd -and (Version-Equal $actual $want)){Add-Dependency $spec[0] match Tools $spec[2] $actual $want}
            else{Add-Dependency $spec[0] mismatch Tools $spec[2] $actual $want "installed $actual · pinned $want"}
        }

        if($managedProfile -eq 'workstation'){
            $fontVersion=if(Test-Path -LiteralPath (Join-Path $state 'fonts\version')){(Get-Content -LiteralPath (Join-Path $state 'fonts\version') -Raw).Trim()}else{'missing'}
            $fontManifest=Join-Path $state 'fonts\current.json'
            $fontCount=0
            if(Test-Path -LiteralPath $fontManifest){
                try{$fontCount=@(Get-Content -LiteralPath $fontManifest -Raw|ConvertFrom-Json|Where-Object{Test-Path -LiteralPath $_.path}).Count}catch{$fontCount=0}
            }
            $want=[string]$versions.NERD_FONTS_VERSION
            if($fontVersion -eq $want -and $fontCount -eq 4){Add-Dependency nerd_fonts match Font 'Monaspice Neon NF' "$fontVersion · 4 faces" "$want · 4 faces"}
            else{Add-Dependency nerd_fonts mismatch Font 'Monaspice Neon NF' "$fontVersion · $fontCount faces" "$want · 4 faces" "installed $fontVersion · $fontCount/4 faces · pinned $want"}
        }
    }
    $pending=Test-Path -LiteralPath (Join-Path $state 'deps-pending')

    if(-not $Quiet){
        if($Format -eq 'json'){
            [pscustomobject]@{
                command='dependencies';action='status';profile=Get-TerminalEnvSafeText $managedProfile
                summary=[pscustomobject]@{dependencies=$dependencies.Count;mismatch=$mismatch;pending=[bool]$pending}
                dependencies=@($dependencies)
            }|ConvertTo-Json -Depth 6
        }elseif($Format -eq 'plain'){
            Write-Output "meta`tprofile`t$(Get-TerminalEnvSafeText $managedProfile)"
            foreach($dep in $dependencies){Write-Output "dependency`t$($dep.status)`t$($dep.id)`t$($dep.category)`t$($dep.label)`t$($dep.installed)`t$($dep.pinned)`t$($dep.detail)"}
            if($pending){Write-Output "state`tpending`tdependency manifest changed"}
            Write-Output "summary`t$($dependencies.Count)`t$mismatch`t$([int]$pending)"
        }else{
            Write-TerminalEnvTitle dependencies
            if($managedProfile -eq 'minimal'){
                Write-TerminalEnvOutcome text 'Minimal profile · optional managed dependencies are intentionally omitted'
            }elseif($mismatch -eq 0 -and -not $pending -and -not $Detailed){
                Write-TerminalEnvOutcome success "Up to date · $($dependencies.Count) dependencies"
            }else{
                if($Detailed){
                    foreach($category in 'Tools','Font'){
                        $rows=@($dependencies|Where-Object{$_.status -eq 'match' -and $_.category -eq $category})
                        if($rows.Count){Write-TerminalEnvSection $category;foreach($row in $rows){Write-TerminalEnvRow $row.label $row.installed}}
                    }
                }
                $attention=$mismatch+[int]$pending
                if($attention){
                    Write-TerminalEnvSection Attention
                    foreach($row in @($dependencies|Where-Object status -eq 'mismatch')){Write-TerminalEnvAttention warn $row.label $row.detail}
                    if($pending){Write-TerminalEnvAttention warn Dependencies 'source changed dependency pins; run terminal deps sync'}
                }
                Write-TerminalEnvOutcome warning "$($dependencies.Count) dependencies · $attention need attention"
            }
        }
    }
    if($mismatch -or $pending){exit 1}
    return
}

$targetProfile=$managedProfile
$installArgs=@{Profile=$targetProfile;Force=$true}
if($DryRun){$installArgs.DryRun=$true}
if($Quiet -or $Format -ne 'human'){
    & (Join-Path $source 'install.ps1') @installArgs 1>$null 6>$null
}else{
    & (Join-Path $source 'install.ps1') @installArgs
}
if(-not $DryRun){Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue}
if($DryRun){$syncStatus='dry-run'}else{$syncStatus='ok'}
if(-not $Quiet){
    if($Format -eq 'json'){
        [pscustomobject]@{command='dependencies';action='sync';profile=Get-TerminalEnvSafeText $managedProfile;dry_run=[bool]$DryRun;status=$syncStatus}|ConvertTo-Json -Compress
    }elseif($Format -eq 'plain'){
        Write-Output "sync`t$syncStatus`t$(Get-TerminalEnvSafeText $managedProfile)`t$([int]$DryRun)"
    }else{
        Write-TerminalEnvTitle dependencies
        if($DryRun){Write-TerminalEnvOutcome accent 'Dry run complete · no dependency changes applied'}
        else{Write-TerminalEnvOutcome success 'Dependencies synchronized to the installed source'}
    }
}

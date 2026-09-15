$Yes=$false
$DryRun=$false
$Format='human'
$Color='auto'
$Quiet=$false

function Show-Usage {
    Write-Output @'
Usage: terminal rollback [options]
       terminal-rollback [options]

Options:
  --yes                    Skip interactive confirmation.
  --dry-run                Show the rollback target without changing anything.
  --format human|plain|json
  --color auto|always|never
  --quiet                  Print no result output; requires --yes to apply.
  -h, --help               Show this help.
'@
}

for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('--yes','-Yes')){$Yes=$true;continue}
    if($arg -in @('--dry-run','-DryRun')){$DryRun=$true;continue}
    if($arg -in @('--format','-Format')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Format=[string]$args[$i];continue}
    if($arg -like '--format=*'){$Format=$arg.Substring(9);continue}
    if($arg -in @('--color','-Color')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Color=[string]$args[$i];continue}
    if($arg -like '--color=*'){$Color=$arg.Substring(8);continue}
    if($arg -in @('--quiet','-Quiet')){$Quiet=$true;continue}
    if($arg -in @('-h','--help','-?')){Show-Usage;return}
    throw "Unknown option: $arg`nUsage: terminal rollback [options]
       terminal-rollback [options]"
}
$Format=$Format.ToLowerInvariant();$Color=$Color.ToLowerInvariant()
if($Format -notin @('human','plain','json')){throw "Invalid format: $Format"}
if($Color -notin @('auto','always','never')){throw "Invalid color mode: $Color"}

. (Join-Path $PSScriptRoot 'output.ps1')
Initialize-TerminalEnvUI -Format $Format -ColorMode $Color
$ErrorActionPreference='Stop'
$source=Join-Path $HOME '.local\share\terminal-env\source'
$state=Join-Path $HOME '.local\state\terminal-env'
$config=Join-Path $HOME '.config\terminal-env\chezmoi.toml'
$bin=Join-Path $HOME '.local\bin'
$previousPath=Join-Path $state 'previous-commit'
if(-not(Test-Path -LiteralPath $previousPath)){throw 'No previous Git revision recorded.'}
$prev=(Get-Content -LiteralPath $previousPath -Raw).Trim()
if($prev -notmatch '^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$'){throw 'Recorded rollback revision is invalid.'}
if(-not(Test-Path -LiteralPath (Join-Path $source '.git'))){throw 'No previous Git revision recorded.'}
& git -C $source cat-file -e "${prev}^{commit}" *> $null;if($LASTEXITCODE){throw 'Recorded rollback revision is not available in the installed source.'}
if(git -C $source status --porcelain){throw 'Installed source has local changes; refusing rollback.'}
$cur=(git -C $source rev-parse HEAD | Out-String).Trim()
if($cur -eq $prev){throw 'The recorded rollback revision is already active.'}
$managedProfile=if(Test-Path -LiteralPath (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'workstation'}
$curVersions=(git -C $source rev-parse "${cur}:versions.env" 2>$null | Out-String).Trim()
$targetVersions=(git -C $source rev-parse "${prev}:versions.env" 2>$null | Out-String).Trim()
$depsChanged=$curVersions -ne $targetVersions

function Invoke-NativeProgress {
    param([string]$FilePath,[string[]]$Arguments)
    if($Quiet){& $FilePath @Arguments 1>$null}
    else{& $FilePath @Arguments | ForEach-Object {[Console]::Error.WriteLine((Get-TerminalEnvSafeText $_))}}
    if($LASTEXITCODE){throw "$FilePath failed with exit code $LASTEXITCODE"}
}
function Invoke-ScriptProgress {
    param([string]$Path,[string[]]$Arguments=@())
    if($Quiet){& $Path @Arguments 1>$null 6>$null}
    else{& $Path @Arguments | ForEach-Object {[Console]::Error.WriteLine((Get-TerminalEnvSafeText $_))}}
}
function Short-Revision([string]$Revision){if($Revision.Length -le 12){return $Revision};return $Revision.Substring(0,12)}
function Write-RollbackPlan {
    if($Quiet -or $Format -ne 'human'){return}
    Write-TerminalEnvTitle rollback
    Write-TerminalEnvSection Plan
    Write-TerminalEnvRow Current (Short-Revision $cur)
    Write-TerminalEnvRow Target (Short-Revision $prev)
    Write-TerminalEnvMeta 'Managed configuration will be replaced. Local secrets and history are not touched.'
}
function Write-RollbackResult {
    param([ValidateSet('planned','cancelled','rolled-back')][string]$Status)
    if($Quiet){return}
    if($Format -eq 'json'){
        [pscustomobject]@{command='rollback';status=$Status;current=$cur;target=$prev;dependencies_changed=[bool]$depsChanged}|ConvertTo-Json -Compress
        return
    }
    if($Format -eq 'plain'){
        Write-Output "rollback`t$Status`t$cur`t$prev`t$([int]$depsChanged)"
        return
    }
    switch($Status){
        'planned'{Write-TerminalEnvOutcome accent 'Dry run complete · no changes applied'}
        'cancelled'{Write-TerminalEnvOutcome text 'Cancelled · no changes applied'}
        'rolled-back'{
            if($depsChanged){Write-TerminalEnvSection Attention;Write-TerminalEnvAttention warn Dependencies 'dependency manifest differs; run terminal deps sync'}
            Write-TerminalEnvOutcome success "Rolled back · $(Short-Revision $prev)"
        }
    }
}

Write-RollbackPlan
if($DryRun){Write-RollbackResult 'planned';return}
if(-not $Yes){
    if($Quiet){throw 'Rollback requires --yes when --quiet is used.'}
    if($Format -ne 'human'){throw 'Rollback requires --yes for plain or JSON output.'}
    $redirected=$true
    try{$redirected=[Console]::IsInputRedirected}catch{}
    if($redirected){throw 'Rollback requires --yes when stdin is not interactive.'}
    $answer=Read-Host 'Continue? [y/N]'
    if($answer -notmatch '(?i)^(y|yes)$'){Write-RollbackResult 'cancelled';return}
}

try {
    Invoke-NativeProgress git @('-C',$source,'reset','--hard',$prev)
    Invoke-ScriptProgress (Join-Path $source 'tests\smoke.ps1')
    Invoke-NativeProgress (Join-Path $bin 'chezmoi.exe') @('--source',$source,'--config',$config,'apply','--force')
    $fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
    New-Item -ItemType Directory -Force $fragDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'dot_config\windows-terminal\terminal-env.json') -Destination (Join-Path $fragDir 'terminal-env.json') -Force
    $doctorPath=Join-Path $HOME '.config\terminal-env\powershell\doctor.ps1'
    if(Test-Path -LiteralPath $doctorPath){
        & $doctorPath '--quick' '--quiet'
        if($LASTEXITCODE){throw 'terminal-doctor verification failed'}
    }
    Set-Content -LiteralPath $previousPath -Value $cur -NoNewline -Encoding utf8NoBOM
    if($depsChanged){Set-Content -LiteralPath (Join-Path $state 'deps-pending') -Value $prev -NoNewline -Encoding utf8NoBOM}
    else{Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue}
} catch {
    [Console]::Error.WriteLine('Could not complete rollback.')
    [Console]::Error.WriteLine('The previously active source revision and managed configuration are being restored.')
    & git -C $source reset --hard $cur *> $null
    & (Join-Path $bin 'chezmoi.exe') --source $source --config $config apply --force *> $null
    $fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
    New-Item -ItemType Directory -Force $fragDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'dot_config\windows-terminal\terminal-env.json') -Destination (Join-Path $fragDir 'terminal-env.json') -Force
    throw
}
Write-RollbackResult 'rolled-back'

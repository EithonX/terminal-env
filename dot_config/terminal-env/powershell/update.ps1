$Check=$false
$Remote=$null
$Branch=$null
$Format='human'
$Color='auto'
$Quiet=$false

function Show-Usage {
    Write-Output @'
Usage: terminal update [options]
       terminal-update [options]

Options:
  --check                 Check for a source update without applying it.
  --remote NAME           Use a specific configured Git remote.
  --branch NAME           Use a specific branch.
  --format human|plain|json
  --color auto|always|never
  --quiet                 Print no result output.
  -h, --help              Show this help.

Updates Terminal Environment source/config from the installed Git repository.
External dependency versions are reconciled separately with terminal deps sync.
'@
}

for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('--check','-Check')){$Check=$true;continue}
    if($arg -in @('--remote','-Remote')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Remote=[string]$args[$i];continue}
    if($arg -like '--remote=*'){$Remote=$arg.Substring(9);continue}
    if($arg -in @('--branch','-Branch')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Branch=[string]$args[$i];continue}
    if($arg -like '--branch=*'){$Branch=$arg.Substring(9);continue}
    if($arg -in @('--format','-Format')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Format=[string]$args[$i];continue}
    if($arg -like '--format=*'){$Format=$arg.Substring(9);continue}
    if($arg -in @('--color','-Color')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Color=[string]$args[$i];continue}
    if($arg -like '--color=*'){$Color=$arg.Substring(8);continue}
    if($arg -in @('--quiet','-Quiet')){$Quiet=$true;continue}
    if($arg -in @('-h','--help','-?')){Show-Usage;return}
    throw "Unknown option: $arg`nUsage: terminal update [options]
       terminal-update [options]"
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
$managedProfile=if(Test-Path -LiteralPath (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'workstation'}

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

if(-not(Test-Path (Join-Path $source '.git'))){throw 'No Git-backed source is installed. Reinstall once from your GitHub clone; future terminal update runs will use that remote.'}
if(git -C $source status --porcelain){throw 'Installed source has local changes; refusing to overwrite them.'}

$currentBranch=(git -C $source symbolic-ref --quiet --short HEAD 2>$null | Out-String).Trim()
$upstream=(git -C $source rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-String).Trim()
if(-not $Remote){$Remote=if($upstream){($upstream -split '/',2)[0]}else{'origin'}}
if(-not $Branch){$Branch=if($upstream){($upstream -split '/',2)[1]}elseif($currentBranch){$currentBranch}else{throw 'Cannot determine update branch; pass --branch.'}}
if(-not $Remote -or $Remote.StartsWith('-')){throw 'Git remote name is invalid.'}
& git -C $source check-ref-format --branch $Branch *> $null;if($LASTEXITCODE){throw "Git branch '$Branch' is invalid."}
& git -C $source remote get-url -- $Remote *> $null;if($LASTEXITCODE){throw "Git remote '$Remote' is not configured."}

if(-not $Quiet -and $Format -eq 'human'){
    Write-TerminalEnvTitle update
    Write-TerminalEnvMeta "Checking $Remote/$Branch"
}
Invoke-NativeProgress git @('-C',$source,'fetch','--prune',$Remote,$Branch)
$old=(git -C $source rev-parse HEAD | Out-String).Trim()
$latest=(git -C $source rev-parse "$Remote/$Branch" | Out-String).Trim()
$count=0
if($old -ne $latest){
    & git -C $source merge-base --is-ancestor $old $latest *> $null
    if($LASTEXITCODE){throw 'Remote branch cannot be fast-forwarded from the current source; refusing update.'}
    $countText=(git -C $source rev-list --count "$old..$latest" 2>$null | Out-String).Trim()
    if($countText -match '^\d+$'){$count=[int]$countText}
}
$oldVersions=(git -C $source rev-parse "${old}:versions.env" 2>$null | Out-String).Trim()
$latestVersions=(git -C $source rev-parse "${latest}:versions.env" 2>$null | Out-String).Trim()
$depsChanged=$oldVersions -ne $latestVersions

function Write-UpdateResult {
    param([ValidateSet('up-to-date','available','updated')][string]$Status,[ValidateSet('check','update')][string]$Action)
    if($Quiet){return}
    $oldShort=Short-Revision $old;$latestShort=Short-Revision $latest
    if($Format -eq 'json'){
        [pscustomobject]@{
            command='update';action=$Action;status=$Status;remote=Get-TerminalEnvSafeText $Remote;branch=Get-TerminalEnvSafeText $Branch
            current=$old;latest=$latest;commit_count=$count;dependencies_changed=[bool]$depsChanged
        }|ConvertTo-Json -Compress
        return
    }
    if($Format -eq 'plain'){
        Write-Output "update`t$Status`t$old`t$latest`t$count`t$(Get-TerminalEnvSafeText $Remote)`t$(Get-TerminalEnvSafeText $Branch)`t$([int]$depsChanged)"
        return
    }
    switch($Status){
        'up-to-date'{Write-TerminalEnvOutcome success "Up to date · $oldShort · $Remote/$Branch"}
        'available'{
            Write-TerminalEnvOutcome accent "Update available · $count commit(s) · $oldShort → $latestShort"
            Write-TerminalEnvMeta "$Remote/$Branch"
            if($depsChanged){Write-TerminalEnvSection Attention;Write-TerminalEnvAttention warn Dependencies 'the available source changes dependency pins; sync after updating'}
        }
        'updated'{
            Write-TerminalEnvSection Updated
            Write-TerminalEnvRow Source "$oldShort → $latestShort"
            Write-TerminalEnvRow Branch "$Remote/$Branch"
            if($depsChanged){Write-TerminalEnvSection Attention;Write-TerminalEnvAttention warn Dependencies 'dependency manifest changed; run terminal deps sync'}
            Write-TerminalEnvOutcome success "Updated · $latestShort"
        }
    }
}

if($old -eq $latest){Write-UpdateResult 'up-to-date' $(if($Check){'check'}else{'update'});return}
if($Check){Write-UpdateResult 'available' 'check';return}

try {
    Invoke-NativeProgress git @('-C',$source,'merge','--ff-only',$latest)
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
    Set-Content -LiteralPath (Join-Path $state 'previous-commit') -Value $old -NoNewline -Encoding utf8NoBOM
    if($depsChanged){
        Set-Content -LiteralPath (Join-Path $state 'deps-pending') -Value $latest -NoNewline -Encoding utf8NoBOM
    }else{
        Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue
    }
} catch {
    [Console]::Error.WriteLine('Could not update Terminal Environment.')
    [Console]::Error.WriteLine('The previous source revision and managed configuration are being restored.')
    & git -C $source reset --hard $old *> $null
    & (Join-Path $bin 'chezmoi.exe') --source $source --config $config apply --force *> $null
    $fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
    New-Item -ItemType Directory -Force $fragDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'dot_config\windows-terminal\terminal-env.json') -Destination (Join-Path $fragDir 'terminal-env.json') -Force
    throw
}
Write-UpdateResult 'updated' 'update'

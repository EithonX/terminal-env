function Show-TerminalEnvRootHelp {
    Write-Output @'
Terminal Environment

Usage
  terminal <command> [options]

Commands
  doctor      Check the environment
  update      Update managed configuration
  deps        Inspect or synchronize dependencies
  context     Explain project context and toolchains
  backup      Create a manual backup
  rollback    Restore a previous managed revision
  version     Show installed source identity

Run `terminal <command> --help` for details.
'@
}

function Resolve-TerminalEnvCommandScript {
    param([Parameter(Mandatory=$true)][string]$Name)
    $path = Join-Path $PSScriptRoot "$Name.ps1"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Managed command is missing: terminal-$Name" }
    return $path
}

function Invoke-TerminalEnvVersionCommand {
    param([string[]]$CommandArgs)
    $format='human';$color='auto';$quiet=$false
    for($i=0;$i -lt $CommandArgs.Count;$i++){
        $arg=[string]$CommandArgs[$i]
        if($arg -in @('-h','--help','-?')){
            Write-Output @'
Usage: terminal version [options]

Options:
  --format human|plain|json
  --color auto|always|never
  --quiet                 Print no result output.
  -h, --help              Show this help.
'@
            return
        }
        if($arg -in @('--quiet','-Quiet')){$quiet=$true;continue}
        if($arg -in @('--format','-Format')){if($i+1 -ge $CommandArgs.Count){throw "Missing value for $arg."};$i++;$format=[string]$CommandArgs[$i];continue}
        if($arg -like '--format=*'){$format=$arg.Substring(9);continue}
        if($arg -in @('--color','-Color')){if($i+1 -ge $CommandArgs.Count){throw "Missing value for $arg."};$i++;$color=[string]$CommandArgs[$i];continue}
        if($arg -like '--color=*'){$color=$arg.Substring(8);continue}
        throw "Unknown option: $arg"
    }
    $format=$format.ToLowerInvariant();$color=$color.ToLowerInvariant()
    if($format -notin @('human','plain','json')){throw "Invalid format: $format"}
    if($color -notin @('auto','always','never')){throw "Invalid color mode: $color"}
    if($quiet){return}

    . (Join-Path $PSScriptRoot 'output.ps1')
    Initialize-TerminalEnvUI -Format $format -ColorMode $color
    $source=Join-Path $HOME '.local\share\terminal-env\source'
    $state=Join-Path $HOME '.local\state\terminal-env'
    $profile=if(Test-Path -LiteralPath (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'unknown'}
    $revision='';$branch='';$sourceKind='static'
    $git=Get-Command git -ErrorAction SilentlyContinue
    if($git -and (Test-Path -LiteralPath (Join-Path $source '.git'))){
        $revision=(& $git.Source -C $source rev-parse HEAD 2>$null | Out-String).Trim()
        if($LASTEXITCODE -eq 0 -and $revision){
            $sourceKind='git'
            $branch=(& $git.Source -C $source symbolic-ref --quiet --short HEAD 2>$null | Out-String).Trim()
            if($LASTEXITCODE -ne 0){$branch=''}
        }else{$revision=''}
    }
    $profile=Get-TerminalEnvSafeText $profile;$revision=Get-TerminalEnvSafeText $revision;$branch=Get-TerminalEnvSafeText $branch
    if($format -eq 'json'){
        [pscustomobject]@{command='version';source_kind=$sourceKind;revision=$revision;branch=$branch;profile=$profile}|ConvertTo-Json -Compress
    }elseif($format -eq 'plain'){
        Write-Output "version`t$sourceKind`t$revision`t$branch`t$profile"
    }else{
        Write-TerminalEnvTitle version
        Write-TerminalEnvRow Source $(if($revision){$revision.Substring(0,[Math]::Min(12,$revision.Length))}else{'static checkout'})
        if($branch){Write-TerminalEnvRow Branch $branch}
        Write-TerminalEnvRow Profile $profile
    }
}

function Write-TerminalEnvCompactVersion {
    $source=Join-Path $HOME '.local\share\terminal-env\source'
    $revision='static'
    $git=Get-Command git -ErrorAction SilentlyContinue
    if($git -and (Test-Path -LiteralPath (Join-Path $source '.git'))){
        $candidate=(& $git.Source -C $source rev-parse --short=12 HEAD 2>$null | Out-String).Trim()
        if($LASTEXITCODE -eq 0 -and $candidate){$revision=$candidate}
    }
    Write-Output "Terminal Environment source $revision"
}

function Invoke-TerminalEnvCommand {
    param([string[]]$CommandArgs)
    if($CommandArgs.Count -eq 0){Show-TerminalEnvRootHelp;return}
    $command=[string]$CommandArgs[0]
    $rest=@()
    if($CommandArgs.Count -gt 1){$rest=@($CommandArgs[1..($CommandArgs.Count-1)])}
    switch($command){
        '-h' {Show-TerminalEnvRootHelp;return}
        '--help' {Show-TerminalEnvRootHelp;return}
        'help' {Show-TerminalEnvRootHelp;return}
        '-V' {Write-TerminalEnvCompactVersion;return}
        '--version' {Write-TerminalEnvCompactVersion;return}
        'version' {Invoke-TerminalEnvVersionCommand -CommandArgs $rest;return}
        'deps' {
            if($rest.Count -eq 0){$rest=@('status')}
            elseif($rest[0] -eq 'check'){
                $tail=@()
                if($rest.Count -gt 1){$tail=@($rest[1..($rest.Count-1)])}
                $rest=@('status')+$tail
            }
            & (Resolve-TerminalEnvCommandScript deps) @rest
            return
        }
        {$_ -in @('doctor','update','context','backup','rollback')} {
            & (Resolve-TerminalEnvCommandScript $command) @rest
            return
        }
        default {throw "Unknown command: $command`nRun 'terminal --help' for usage."}
    }
}

if($MyInvocation.InvocationName -ne '.'){
    try{Invoke-TerminalEnvCommand -CommandArgs @($args)}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 2}
}

$WithHistory=$false
$Format='path'
$Color='auto'
$Quiet=$false

function Show-Usage {
    Write-Output @'
Usage: terminal backup [options]
       terminal-backup [options]

Options:
  --with-history          Include managed shell/history data.
  --format human|plain|json
  --color auto|always|never
  --quiet                 Print no result output.
  -h, --help              Show this help.

Without --format, stdout remains the created archive path for compatibility.
'@
}

for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('--with-history','-WithHistory')){$WithHistory=$true;continue}
    if($arg -in @('--format','-Format')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Format=[string]$args[$i];continue}
    if($arg -like '--format=*'){$Format=$arg.Substring(9);continue}
    if($arg -in @('--color','-Color')){if($i+1 -ge $args.Count){throw "Missing value for $arg."};$i++;$Color=[string]$args[$i];continue}
    if($arg -like '--color=*'){$Color=$arg.Substring(8);continue}
    if($arg -in @('--quiet','-Quiet')){$Quiet=$true;continue}
    if($arg -in @('-h','--help','-?')){Show-Usage;return}
    throw "Unknown option: $arg`nUsage: terminal backup [options]
       terminal-backup [options]"
}
$Format=$Format.ToLowerInvariant();$Color=$Color.ToLowerInvariant()
if($Format -notin @('path','human','plain','json')){throw "Invalid format: $Format"}
if($Color -notin @('auto','always','never')){throw "Invalid color mode: $Color"}

. (Join-Path $PSScriptRoot 'output.ps1')
$uiFormat=if($Format -eq 'path'){'plain'}else{$Format}
Initialize-TerminalEnvUI -Format $uiFormat -ColorMode $Color
$ErrorActionPreference='Stop'
$root=Join-Path $HOME '.local\state\terminal-env\backups\manual'
New-Item -ItemType Directory -Force $root|Out-Null
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$out=Join-Path $root ("manual-$stamp.zip")
if(Test-Path -LiteralPath $out){$out=Join-Path $root ("manual-$stamp-$PID.zip")}
$items=@()
foreach($r in '.config\oh-my-posh','.config\atuin','.config\terminal-env'){
    $p=Join-Path $HOME $r
    if(Test-Path -LiteralPath $p){$items+=$p}
}
if($WithHistory){
    foreach($r in '.local\share\atuin'){
        $p=Join-Path $HOME $r
        if(Test-Path -LiteralPath $p){$items+=$p}
    }
}
if(-not $items){throw 'Nothing to back up.'}
Compress-Archive -Path $items -DestinationPath $out -CompressionLevel Optimal
$bytes=(Get-Item -LiteralPath $out).Length
if($Quiet){return}
if($Format -eq 'path'){Write-Output $out;return}
if($Format -eq 'json'){
    [pscustomobject]@{command='backup';status='created';archive=Get-TerminalEnvSafeText $out;bytes=[long]$bytes;with_history=[bool]$WithHistory}|ConvertTo-Json -Compress
    return
}
if($Format -eq 'plain'){
    Write-Output "backup`tcreated`t$(Get-TerminalEnvSafeText $out)`t$bytes`t$([int]$WithHistory)"
    return
}
Write-TerminalEnvTitle backup
Write-TerminalEnvSection Created
Write-TerminalEnvRow Archive $out
$scopeText=if($WithHistory){'configuration + history'}else{'configuration'}
Write-TerminalEnvRow Scope $scopeText
Write-TerminalEnvRow Size "$bytes bytes"
Write-TerminalEnvOutcome success 'Backup created'

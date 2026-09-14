$WithHistory=$false
foreach($arg in $args){
    if([string]$arg -in @('--with-history','-WithHistory')){$WithHistory=$true;continue}
    if([string]$arg -in @('-h','--help','-?')){Write-Output 'Usage: terminal-backup [--with-history]';return}
    throw "Unknown option: $arg`nUsage: terminal-backup [--with-history]"
}
$ErrorActionPreference='Stop'
$root=Join-Path $HOME '.local\state\terminal-env\backups\manual'
New-Item -ItemType Directory -Force $root|Out-Null
$out=Join-Path $root ('manual-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'.zip')
$items=@()
foreach($r in '.config\oh-my-posh','.config\atuin','.config\terminal-env'){ $p=Join-Path $HOME $r;if(Test-Path $p){$items+=$p} }
if($WithHistory){ foreach($r in '.local\share\atuin'){ $p=Join-Path $HOME $r;if(Test-Path $p){$items+=$p} } }
if(-not $items){throw 'Nothing to back up.'}
Compress-Archive -Path $items -DestinationPath $out -CompressionLevel Optimal
Write-Output $out

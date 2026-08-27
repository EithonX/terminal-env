[CmdletBinding()] param([switch]$WithHistory)
$ErrorActionPreference='Stop'; $root=Join-Path $HOME '.local\state\terminal-env\backups'; New-Item -ItemType Directory -Force $root|Out-Null
$out=Join-Path $root ('manual-'+(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'.zip'); $items=@()
foreach($r in '.config\oh-my-posh','.config\atuin','.config\terminal-env'){ $p=Join-Path $HOME $r;if(Test-Path $p){$items+=$p} }
if($WithHistory){ foreach($r in '.local\share\atuin'){ $p=Join-Path $HOME $r;if(Test-Path $p){$items+=$p} } }
if(-not $items){throw 'Nothing to back up.'}; Compress-Archive -Path $items -DestinationPath $out -CompressionLevel Optimal; Write-Output $out

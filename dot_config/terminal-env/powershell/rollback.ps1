$ErrorActionPreference='Stop'; $source=Join-Path $HOME '.local\share\terminal-env\source'; $state=Join-Path $HOME '.local\state\terminal-env'
$prev=(Get-Content (Join-Path $state 'previous-commit') -Raw -ErrorAction Stop).Trim(); if(-not $prev){throw 'No previous revision recorded.'}
if(git -C $source status --porcelain){throw 'Installed source has local changes; refusing rollback.'}
$cur=(git -C $source rev-parse HEAD).Trim(); $profile=(Get-Content (Join-Path $state 'profile') -Raw).Trim()
git -C $source reset --hard $prev | Out-Null; & (Join-Path $source 'install.ps1') -Profile $profile -Force
Set-Content -LiteralPath (Join-Path $state 'previous-commit') -Value $cur -NoNewline -Encoding utf8NoBOM; Write-Host "Rolled back to $prev" -ForegroundColor Green

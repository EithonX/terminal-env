$ErrorActionPreference='Stop'
$source=Join-Path $HOME '.local\share\terminal-env\source'
$state=Join-Path $HOME '.local\state\terminal-env'
$config=Join-Path $HOME '.config\terminal-env\chezmoi.toml'
$bin=Join-Path $HOME '.local\bin'
$prev=(Get-Content -LiteralPath (Join-Path $state 'previous-commit') -Raw -ErrorAction Stop).Trim()
if(-not $prev){throw 'No previous revision recorded.'}
if(git -C $source status --porcelain){throw 'Installed source has local changes; refusing rollback.'}
$cur=(git -C $source rev-parse HEAD | Out-String).Trim()
$curVersions=(git -C $source rev-parse "${cur}:versions.env" 2>$null | Out-String).Trim()
& git -C $source reset --hard $prev | Out-Null
& (Join-Path $source 'tests\smoke.ps1')
& (Join-Path $bin 'chezmoi.exe') --source $source --config $config apply --force
if($LASTEXITCODE){ throw 'chezmoi apply failed during rollback' }
$fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
New-Item -ItemType Directory -Force $fragDir | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'dot_config\windows-terminal\terminal-env.json') -Destination (Join-Path $fragDir 'terminal-env.json') -Force
Set-Content -LiteralPath (Join-Path $state 'previous-commit') -Value $cur -NoNewline -Encoding utf8NoBOM
$newVersions=(git -C $source rev-parse "${prev}:versions.env" 2>$null | Out-String).Trim()
if($curVersions -ne $newVersions){
    Set-Content -LiteralPath (Join-Path $state 'deps-pending') -Value $prev -NoNewline -Encoding utf8NoBOM
    Write-Host "Rolled source/config back to $prev. Dependency manifest differs; run: terminal-deps sync" -ForegroundColor Yellow
} else {
    Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue
    Write-Host "Rolled back to $prev" -ForegroundColor Green
}

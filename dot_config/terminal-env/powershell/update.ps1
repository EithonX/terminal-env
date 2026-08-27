[CmdletBinding()]
param(
    [switch]$Check,
    [string]$Remote,
    [string]$Branch
)
$ErrorActionPreference='Stop'
$source=Join-Path $HOME '.local\share\terminal-env\source'
$state=Join-Path $HOME '.local\state\terminal-env'
$config=Join-Path $HOME '.config\terminal-env\chezmoi.toml'
$bin=Join-Path $HOME '.local\bin'
if(-not(Test-Path (Join-Path $source '.git'))){ throw 'No Git-backed source is installed. Reinstall once from your GitHub clone; future terminal-update runs will use that remote.' }
if(git -C $source status --porcelain){ throw 'Installed source has local changes; refusing to overwrite them.' }

$currentBranch=(git -C $source symbolic-ref --quiet --short HEAD 2>$null | Out-String).Trim()
$upstream=(git -C $source rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-String).Trim()
if(-not $Remote){ $Remote=if($upstream){($upstream -split '/',2)[0]}else{'origin'} }
if(-not $Branch){ $Branch=if($upstream){($upstream -split '/',2)[1]}elseif($currentBranch){$currentBranch}else{throw 'Cannot determine update branch; pass -Branch.'} }
& git -C $source remote get-url $Remote *> $null; if($LASTEXITCODE){ throw "Git remote '$Remote' is not configured." }
& git -C $source fetch --prune $Remote $Branch; if($LASTEXITCODE){ throw 'git fetch failed' }
$old=(git -C $source rev-parse HEAD | Out-String).Trim()
$latest=(git -C $source rev-parse "$Remote/$Branch" | Out-String).Trim()
if($old -eq $latest){ Write-Host "Already up to date: $($old.Substring(0,12)) ($Remote/$Branch)" -ForegroundColor Green; return }
if($Check){
    $count=(git -C $source rev-list --count "$old..$latest" | Out-String).Trim()
    Write-Host "Update available: $($old.Substring(0,12)) -> $($latest.Substring(0,12)) ($count commit(s), $Remote/$Branch)" -ForegroundColor Cyan
    return
}
$oldVersions=(git -C $source rev-parse "${old}:versions.env" 2>$null | Out-String).Trim()
try {
    & git -C $source merge --ff-only $latest; if($LASTEXITCODE){throw 'git fast-forward failed'}
    & (Join-Path $source 'tests\smoke.ps1')
    & (Join-Path $bin 'chezmoi.exe') --source $source --config $config apply --force
    if($LASTEXITCODE){throw 'chezmoi apply failed'}
    $fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
    New-Item -ItemType Directory -Force $fragDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'dot_config\windows-terminal\terminal-env.json') -Destination (Join-Path $fragDir 'terminal-env.json') -Force
    Set-Content -LiteralPath (Join-Path $state 'previous-commit') -Value $old -NoNewline -Encoding utf8NoBOM
    $newHead=(git -C $source rev-parse HEAD | Out-String).Trim()
    $newVersions=(git -C $source rev-parse "${newHead}:versions.env" 2>$null | Out-String).Trim()
    if($oldVersions -ne $newVersions){
        Set-Content -LiteralPath (Join-Path $state 'deps-pending') -Value $newHead -NoNewline -Encoding utf8NoBOM
        Write-Host 'Source/config updated. Dependency manifest also changed; run: terminal-deps sync' -ForegroundColor Yellow
    } else {
        Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue
        Write-Host "Source/config updated successfully. Previous revision: $old" -ForegroundColor Green
    }
} catch {
    Write-Warning 'Source update failed; restoring previous known-good revision/configuration.'
    & git -C $source reset --hard $old | Out-Null
    & (Join-Path $bin 'chezmoi.exe') --source $source --config $config apply --force | Out-Null
    $fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
    New-Item -ItemType Directory -Force $fragDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'dot_config\windows-terminal\terminal-env.json') -Destination (Join-Path $fragDir 'terminal-env.json') -Force
    throw
}

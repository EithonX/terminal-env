$ErrorActionPreference='Stop'
$source=Join-Path $HOME '.local\share\terminal-env\source'; $state=Join-Path $HOME '.local\state\terminal-env'
$profile=(Get-Content (Join-Path $state 'profile') -Raw).Trim()
if(-not(Test-Path (Join-Path $source '.git'))){throw 'Installed source is not Git-backed; update from a fresh repository checkout.'}
if(git -C $source status --porcelain){throw 'Installed source has local changes; refusing to overwrite them.'}
$old=(git -C $source rev-parse HEAD).Trim(); Set-Content -LiteralPath (Join-Path $state 'previous-commit') -Value $old -NoNewline -Encoding utf8NoBOM
try {
  git -C $source fetch --prune; if($LASTEXITCODE){throw 'git fetch failed'}
  git -C $source pull --ff-only; if($LASTEXITCODE){throw 'git pull failed'}
  & (Join-Path $source 'tests\smoke.ps1')
  & (Join-Path $source 'install.ps1') -Profile $profile -Force
} catch {
  Write-Warning 'Update failed; restoring the previous known-good revision.'
  git -C $source reset --hard $old | Out-Null
  & (Join-Path $source 'install.ps1') -Profile $profile -Force
  throw
}

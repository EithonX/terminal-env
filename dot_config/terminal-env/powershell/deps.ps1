[CmdletBinding()]
param(
    [ValidateSet('status','sync')][string]$Action='status',
    [switch]$DryRun
)
$ErrorActionPreference='Stop'
$source=Join-Path $HOME '.local\share\terminal-env\source'
$state=Join-Path $HOME '.local\state\terminal-env'
if(-not(Test-Path (Join-Path $source 'versions.env'))){ throw 'Installed dependency manifest is missing.' }
$versions=@{}
Get-Content -LiteralPath (Join-Path $source 'versions.env') | Where-Object { $_ -match '^[A-Z0-9_]+=' } | ForEach-Object { $k,$v=$_ -split '=',2; $versions[$k]=$v }
if($Action -eq 'status'){
    Write-Host 'Terminal Environment dependencies' -ForegroundColor White
    foreach($name in 'oh-my-posh','atuin','fzf','zoxide','chezmoi'){
        $cmd=Get-Command $name -ErrorAction SilentlyContinue
        if($cmd){ $v=(& $cmd.Source --version 2>$null | Select-Object -First 1); Write-Host ("  {0,-18} {1}" -f $name,$v) }
        else { Write-Warning "$name is missing" }
    }
    Write-Host "`nPinned: OMP=$($versions.OH_MY_POSH_VERSION) Atuin=$($versions.ATUIN_VERSION) fzf=$($versions.FZF_VERSION) zoxide=$($versions.ZOXIDE_VERSION) chezmoi=$($versions.CHEZMOI_VERSION)"
    return
}
$profile=if(Test-Path (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'workstation'}
$args=@('-Profile',$profile,'-Force')
if($DryRun){$args+='-DryRun'}
& (Join-Path $source 'install.ps1') @args
if($LASTEXITCODE){ throw 'Dependency sync failed.' }
Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue
Write-Host 'Dependencies synced to the versions pinned by the installed source.' -ForegroundColor Green

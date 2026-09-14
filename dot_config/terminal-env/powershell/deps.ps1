$Action='status'
$DryRun=$false
$ActionSet=$false
for($i=0;$i -lt $args.Count;$i++){
    $arg=[string]$args[$i]
    if($arg -in @('-h','--help','-?','help')){Write-Output 'Usage: terminal-deps [status|sync] [--dry-run]';return}
    if($arg -in @('status','sync')){if($ActionSet){throw "Unexpected argument: $arg"};$Action=$arg.ToLowerInvariant();$ActionSet=$true;continue}
    if($arg -eq '-Action'){if($i+1 -ge $args.Count){throw 'Missing value for -Action.'};$i++;$value=[string]$args[$i];if($value -notin @('status','sync')){throw "Invalid action: $value"};if($ActionSet){throw "Unexpected action: $value"};$Action=$value.ToLowerInvariant();$ActionSet=$true;continue}
    if($arg -in @('--dry-run','-DryRun')){$DryRun=$true;continue}
    throw "Unknown option: $arg`nUsage: terminal-deps [status|sync] [--dry-run]"
}
if($DryRun -and $Action -ne 'sync'){throw '--dry-run is only valid with sync.'}
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
    $fontVersion=if(Test-Path (Join-Path $state 'fonts\version')){(Get-Content -LiteralPath (Join-Path $state 'fonts\version') -Raw).Trim()}else{'missing'}
    Write-Host "`nPinned: OMP=$($versions.OH_MY_POSH_VERSION) Atuin=$($versions.ATUIN_VERSION) fzf=$($versions.FZF_VERSION) zoxide=$($versions.ZOXIDE_VERSION) chezmoi=$($versions.CHEZMOI_VERSION) font=$($versions.NERD_FONTS_VERSION)"
    if($fontVersion -ne $versions.NERD_FONTS_VERSION){ Write-Warning "Managed font version is $fontVersion; pinned=$($versions.NERD_FONTS_VERSION)" }
    return
}
$profile=if(Test-Path (Join-Path $state 'profile')){(Get-Content -LiteralPath (Join-Path $state 'profile') -Raw).Trim()}else{'workstation'}
$args=@('-Profile',$profile,'-Force')
if($DryRun){$args+='-DryRun'}
& (Join-Path $source 'install.ps1') @args
if($LASTEXITCODE){ throw 'Dependency sync failed.' }
Remove-Item -LiteralPath (Join-Path $state 'deps-pending') -Force -ErrorAction SilentlyContinue
Write-Host 'Dependencies synced to the versions pinned by the installed source.' -ForegroundColor Green

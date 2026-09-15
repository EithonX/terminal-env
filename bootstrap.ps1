[CmdletBinding()]
param(
    [ValidateSet('auto','workstation','minimal')][string]$Profile = 'auto',
    [string]$Branch = 'master',
    [switch]$DryRun,
    [switch]$NoFont,
    [switch]$NoTerminalConfig,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if(-not $PSBoundParameters.ContainsKey('Profile') -and $env:TERMINAL_ENV_PROFILE){$Profile=$env:TERMINAL_ENV_PROFILE}
if(-not $PSBoundParameters.ContainsKey('Branch') -and $env:TERMINAL_ENV_BRANCH){$Branch=$env:TERMINAL_ENV_BRANCH}
if($Profile -notin @('auto','workstation','minimal')){throw "Invalid profile: $Profile"}
$repo = if($env:TERMINAL_ENV_REPO){$env:TERMINAL_ENV_REPO}else{'https://github.com/EithonX/terminal-env.git'}
$sourceName=$repo
if($sourceName.StartsWith('https://github.com/')){$sourceName=$sourceName.Substring(19)}
if($sourceName.EndsWith('.git')){$sourceName=$sourceName.Substring(0,$sourceName.Length-4)}
if ($env:OS -ne 'Windows_NT') { throw 'This bootstrap is for Windows. Use bootstrap.sh on macOS or Linux.' }
if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18'){throw 'Terminal Environment cannot be installed from the LocalSystem account.'}
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw "PowerShell language mode is $($ExecutionContext.SessionState.LanguageMode); FullLanguage is required." }
if ($Branch -notmatch '^[A-Za-z0-9._/-]+$' -or $Branch -match '(^|/)\.\.($|/)') { throw 'Invalid branch name.' }
if ([Environment]::OSVersion.Version.Build -lt 17763) { throw 'Windows 10 version 1809 (build 17763) or newer is required.' }
$osArch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($osArch -eq 'arm64' -and [Environment]::OSVersion.Version.Build -lt 22000) { throw 'Windows 10 on Arm cannot run the x64 portable dependencies required by Terminal Environment. Windows 11 or newer is required on Arm64.' }
if ($osArch -notin @('x64','arm64')) { throw "Unsupported Windows architecture: $osArch" }
function Test-WinGet([string]$Path) {
    if(-not $Path -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){ return $false }
    try { & $Path --version *> $null; return $LASTEXITCODE -eq 0 } catch { return $false }
}
function Resolve-WinGet {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-WinGet $cmd.Source)) { return $cmd.Source }
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-WinGet $cmd.Source)) { return $cmd.Source }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-WinGet $alias) { return $alias }
    try {
        $protocol = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = $protocol -bor [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser -AllowClobber | Out-Null
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -Force -Latest | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = $protocol
    } catch {
        if ($null -ne $protocol) { [Net.ServicePointManager]::SecurityProtocol = $protocol }
    }
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-WinGet $cmd.Source)) { return $cmd.Source }
    if (Test-WinGet $alias) { return $alias }
    throw 'WinGet could not be registered or repaired. Install Microsoft App Installer and rerun this command.'
}
function Resolve-Git {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) { try { & $cmd.Source --version *> $null; if($LASTEXITCODE -eq 0){ return $cmd.Source } } catch {} }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { try { & $candidate --version *> $null; if($LASTEXITCODE -eq 0){ return $candidate } } catch {} } }
    return $null
}
Write-Host 'Terminal Environment' -ForegroundColor White
Write-Host "  source  $sourceName@$Branch" -ForegroundColor DarkGray
Write-Host "  profile $Profile" -ForegroundColor DarkGray
$git = Resolve-Git
if (-not $git) {
    if ($DryRun) { throw 'Git is not installed. Bootstrap dry-run does not install prerequisites.' }
    $winget = Resolve-WinGet
    Write-Host '  Installing Git prerequisite...' -ForegroundColor Cyan
    & $winget install --id Git.Git --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw 'Git installation failed.' }
    $git = Resolve-Git
    if (-not $git) { throw 'Git was installed but git.exe could not be resolved in the current session.' }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('terminal-env-bootstrap-' + [guid]::NewGuid())
$checkout = Join-Path $temp 'repo'
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    Write-Host '  Fetching source...' -ForegroundColor Cyan
    $cloned=$false
    foreach($attempt in 1..3){
        Remove-Item -LiteralPath $checkout -Recurse -Force -ErrorAction SilentlyContinue
        & $git clone --quiet --depth 1 --single-branch --branch $Branch -- $repo $checkout
        if($LASTEXITCODE -eq 0){$cloned=$true;break}
        if($attempt -lt 3){Start-Sleep -Seconds ($attempt*2)}
    }
    if (-not $cloned) { throw "Could not clone $sourceName@$Branch." }
    $checkedOut = (& $git -C $checkout symbolic-ref --quiet --short HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $checkedOut -ne $Branch) { throw "'$Branch' is not an updateable branch." }
    $installer = Join-Path $checkout 'install.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Cloned repository does not contain install.ps1.' }
    $hostExe = if (Test-Path -LiteralPath (Join-Path $PSHOME 'pwsh.exe')) { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf)) { throw 'Current PowerShell executable could not be resolved.' }
    $installerArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-Profile',$Profile)
    if ($DryRun) { $installerArgs += '-DryRun' }
    if ($NoFont) { $installerArgs += '-NoFont' }
    if ($NoTerminalConfig) { $installerArgs += '-NoTerminalConfig' }
    if ($Force) { $installerArgs += '-Force' }
    & $hostExe @installerArgs
    if ($LASTEXITCODE -ne 0) { throw "Installer exited with code $LASTEXITCODE." }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

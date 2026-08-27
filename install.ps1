[CmdletBinding()]
param(
    [ValidateSet('auto','workstation','minimal')][string]$Profile = 'auto',
    [switch]$DryRun,
    [switch]$NoFont,
    [switch]$NoTerminalConfig,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Versions = @{}
Get-Content (Join-Path $Root 'versions.env') | Where-Object { $_ -match '^[A-Z0-9_]+=' } | ForEach-Object {
    $k,$v = $_ -split '=',2; $Versions[$k]=$v
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($DryRun) { Write-Host 'Would install PowerShell 7 and reinvoke the installer.' -ForegroundColor Cyan; exit 0 }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'PowerShell 7 and winget are required.' }
    Write-Host 'Installing PowerShell 7 before continuing...' -ForegroundColor Cyan
    & winget install --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path $pwsh)) { throw 'PowerShell 7 installed but pwsh.exe was not found.' }
    $forward=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Profile',$Profile)
    if($DryRun){$forward+='-DryRun'}; if($NoFont){$forward+='-NoFont'}; if($NoTerminalConfig){$forward+='-NoTerminalConfig'}; if($Force){$forward+='-Force'}
    & $pwsh @forward; exit $LASTEXITCODE
}
if ($Profile -eq 'auto') { $Profile='workstation' }
$State = Join-Path $HOME '.local\state\terminal-env'
$Source = Join-Path $HOME '.local\share\terminal-env\source'
$Bin = Join-Path $HOME '.local\bin'
$Backup = Join-Path $State ("backups\" + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
$Config = Join-Path $HOME '.config\terminal-env\chezmoi.toml'
$SameSource = ([IO.Path]::GetFullPath($Root).TrimEnd('\') -eq [IO.Path]::GetFullPath($Source).TrimEnd('\'))
$InstallActive = $false

function Info([string]$s) { Write-Host "  $s" -ForegroundColor Cyan }
function Good([string]$s) { Write-Host "  $s" -ForegroundColor Green }
function Warn([string]$s) { Write-Warning $s }
function Ensure-Directory([string]$p) { if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Install-Winget([string]$Id, [switch]$Required) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { if($Required){ throw 'winget is required on Windows 10/11.' }; Warn "winget unavailable; skipped $Id"; return }
    Info "Ensuring $Id"
    if ($DryRun) { return }
    $listed = (& winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null | Out-String)
    if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($Id)) { return }
    & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { if($Required){ throw "Failed to install $Id" } else { Warn "Optional package failed: $Id" } }
}
function Get-GitHubAsset([string]$Repo,[string]$Tag,[string]$Name,[string]$Out) {
    $headers=@{ 'User-Agent'='terminal-env-installer'; 'Accept'='application/vnd.github+json' }
    $release=Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    $asset=$release.assets | Where-Object name -eq $Name | Select-Object -First 1
    if(-not $asset){ throw "Asset $Name not found for $Repo $Tag" }
    Info "Downloading $Name"
    Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile $Out
    if($asset.digest -and $asset.digest.StartsWith('sha256:')){
        $actual=(Get-FileHash -Algorithm SHA256 $Out).Hash.ToLowerInvariant()
        if($actual -ne $asset.digest.Substring(7).ToLowerInvariant()){ throw "SHA-256 mismatch: $Name" }
    } else { Warn "GitHub did not expose an asset digest for $Name" }
}
function Install-Portable([string]$Repo,[string]$Tag,[string]$Asset,[string]$Binary,[string]$Name) {
    if($DryRun){ Info "Would install $Name $Tag"; return }
    $tmp=Join-Path ([IO.Path]::GetTempPath()) ("terminal-env-"+[guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $archive=Join-Path $tmp $Asset; Get-GitHubAsset $Repo $Tag $Asset $archive
        if($Asset.EndsWith('.exe')){ $dest=Join-Path $Bin "$Binary.exe"; $stage="$dest.new.$PID"; Copy-Item -Force $archive $stage; Move-Item -Force $stage $dest; return }
        if($Asset.EndsWith('.zip')){ Expand-Archive -Force $archive (Join-Path $tmp 'x') }
        else { tar -xf $archive -C $tmp }
        $found=Get-ChildItem $tmp -Recurse -File | Where-Object { $_.Name -eq $Binary -or $_.Name -eq "$Binary.exe" } | Select-Object -First 1
        if(-not $found){ throw "$Binary not found in $Asset" }
        $dest=Join-Path $Bin "$Binary.exe"; $stage="$dest.new.$PID"; Copy-Item -Force $found.FullName $stage; Move-Item -Force $stage $dest
    } finally { Remove-Item -Force -Recurse $tmp -ErrorAction SilentlyContinue }
}
function Backup-Path([string]$Path) {
    if(Test-Path $Path){
        $homeFull=[IO.Path]::GetFullPath($HOME).TrimEnd('\\')
        $pathFull=[IO.Path]::GetFullPath($Path)
        if($pathFull.StartsWith($homeFull,[StringComparison]::OrdinalIgnoreCase)){
            $rel=[IO.Path]::GetRelativePath($homeFull,$pathFull)
            $dest=Join-Path (Join-Path $Backup 'home') $rel
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            Copy-Item -Recurse -Force $Path $dest
        }
    }
}

function Restore-Transaction {
    if(-not $InstallActive -or -not(Test-Path $Backup)){ return }
    Warn 'Installation failed; restoring managed files from the transaction snapshot.'
    $targets=@(
      (Join-Path $HOME '.config\terminal-env'),(Join-Path $HOME '.config\oh-my-posh'),(Join-Path $HOME '.config\atuin'),
      (Join-Path $Bin 'oh-my-posh.exe'),(Join-Path $Bin 'atuin.exe'),(Join-Path $Bin 'fzf.exe'),(Join-Path $Bin 'zoxide.exe'),(Join-Path $Bin 'chezmoi.exe')
    )
    if(-not $SameSource){ $targets += $Source }
    foreach($t in $targets){ Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue }
    $hb=Join-Path $Backup 'home'; if(Test-Path $hb){ Get-ChildItem -Force $hb | Copy-Item -Destination $HOME -Recurse -Force }
    $ppState=Join-Path $State 'powershell-profile-path'; $oldpp=Join-Path $Backup 'external\PowerShell-profile.ps1'; $ppExisted=Join-Path $Backup 'external\PowerShell-profile-existed'
    if(Test-Path $ppState){ $pp=(Get-Content $ppState -Raw).Trim(); if(Test-Path $oldpp){Copy-Item -Force $oldpp $pp}elseif((Test-Path $ppExisted)-and((Get-Content $ppExisted -Raw).Trim()-eq '0')){Remove-Item -Force $pp -ErrorAction SilentlyContinue} }
    $wtState=Join-Path $State 'windows-terminal-settings-path'; $oldwt=Join-Path $Backup 'external\WindowsTerminal-settings.json'
    if((Test-Path $wtState)-and(Test-Path $oldwt)){ Copy-Item -Force $oldwt ((Get-Content $wtState -Raw).Trim()) }
    $frag=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'; $oldfrag=Join-Path $Backup 'external\WindowsTerminal-fragment'
    Remove-Item -Recurse -Force $frag -ErrorAction SilentlyContinue; if(Test-Path $oldfrag){ Copy-Item -Recurse -Force $oldfrag $frag }
}

try {
    Write-Host 'Terminal Environment installer' -ForegroundColor White
    Info "Profile: $Profile | Windows $([Environment]::OSVersion.Version)"
    Ensure-Directory $State; Ensure-Directory $Backup; Ensure-Directory $Bin; Ensure-Directory (Split-Path $Config)
    if(-not $DryRun){
        Backup-Path (Join-Path $HOME '.config\terminal-env')
        Backup-Path (Join-Path $HOME '.config\oh-my-posh')
        Backup-Path (Join-Path $HOME '.config\atuin')
        foreach($b in 'oh-my-posh.exe','atuin.exe','fzf.exe','zoxide.exe','chezmoi.exe'){ Backup-Path (Join-Path $Bin $b) }
        if(-not $SameSource){ Backup-Path $Source }
        # r5 briefly used positional Set-Content arguments. On a failed first run it
        # could create a file named after the profile in the checkout. Remove only
        # that exact artifact when its contents prove it belongs to this installer.
        $legacyMarker = Join-Path $Root $Profile
        if (Test-Path -LiteralPath $legacyMarker -PathType Leaf) {
            try {
                $legacyValue = (Get-Content -LiteralPath $legacyMarker -Raw).Trim()
                if ($legacyValue -eq (Join-Path $State 'profile')) { Remove-Item -LiteralPath $legacyMarker -Force }
            } catch {}
        }
        Set-Content -LiteralPath (Join-Path $State 'profile') -Value $Profile -NoNewline -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $State 'last-install-backup') -Value $Backup -NoNewline -Encoding utf8NoBOM
        if(-not(Test-Path (Join-Path $State 'original-backup'))){ Set-Content -LiteralPath (Join-Path $State 'original-backup') -Value $Backup -NoNewline -Encoding utf8NoBOM }
        $InstallActive = $true
    }

    # Native foundation. Portable CLI versions below are pinned independently.
    Install-Winget Microsoft.PowerShell -Required
    Install-Winget Microsoft.WindowsTerminal -Required
    Install-Winget Git.Git -Required
    foreach($pkg in 'eza-community.eza','sharkdp.bat','BurntSushi.ripgrep.MSVC','sharkdp.fd','dandavison.delta') { Install-Winget $pkg }

    Ensure-Directory $Bin
    Install-Portable JanDeDobbeleer/oh-my-posh ("v"+$Versions.OH_MY_POSH_VERSION) ("posh-windows-amd64.exe") 'oh-my-posh' 'Oh My Posh'
    Install-Portable atuinsh/atuin ("v"+$Versions.ATUIN_VERSION) 'atuin-x86_64-pc-windows-msvc.zip' 'atuin' 'Atuin'
    Install-Portable junegunn/fzf ("v"+$Versions.FZF_VERSION) ("fzf-"+$Versions.FZF_VERSION+'-windows_amd64.zip') 'fzf' 'fzf'
    Install-Portable ajeetdsouza/zoxide ("v"+$Versions.ZOXIDE_VERSION) ("zoxide-"+$Versions.ZOXIDE_VERSION+'-x86_64-pc-windows-msvc.zip') 'zoxide' 'zoxide'
    Install-Portable twpayne/chezmoi ("v"+$Versions.CHEZMOI_VERSION) ("chezmoi_"+$Versions.CHEZMOI_VERSION+'_windows_amd64.zip') 'chezmoi' 'chezmoi'

    # Deploy a dedicated chezmoi source so existing dotfile managers are untouched.
    if(-not $DryRun){
        if((Test-Path $Source) -and -not $Force -and -not (Test-Path (Join-Path $Source '.terminal-env-source'))){ throw "$Source already exists and is not ours; use -Force only if safe." }
        if(-not $SameSource){
        $new="$Source.new.$PID"; Remove-Item -Recurse -Force $new -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $new | Out-Null
        Get-ChildItem -Force $Root | Where-Object Name -ne '.git' | Copy-Item -Destination $new -Recurse -Force
        if(Test-Path (Join-Path $Root '.git')){ Copy-Item -Recurse -Force (Join-Path $Root '.git') (Join-Path $new '.git') }
        New-Item -ItemType File -Force (Join-Path $new '.terminal-env-source') | Out-Null
        Remove-Item -Recurse -Force $Source -ErrorAction SilentlyContinue; Move-Item $new $Source
        }
        Set-Content -LiteralPath $Config -Value "[data]`nprofile = `"$Profile`"`n" -Encoding utf8NoBOM -NoNewline
        $env:PATH="$Bin;$env:PATH"
        & (Join-Path $Bin 'chezmoi.exe') --source $Source --config $Config apply --force
        $atuinMarker=Join-Path $State 'atuin-imported'
        if((Test-Path (Join-Path $Bin 'atuin.exe')) -and -not(Test-Path $atuinMarker)){
            try { & (Join-Path $Bin 'atuin.exe') import powershell | Out-Null; if($LASTEXITCODE -eq 0){ New-Item -ItemType File -Force $atuinMarker | Out-Null } } catch { Warn 'Existing PowerShell history could not be imported into Atuin; it can be imported later.' }
        }
    }

    # Install the pinned Monaspice Neon Nerd Font for the current user.
    if(-not $NoFont -and $Profile -eq 'workstation' -and -not $DryRun){
        $tmp=Join-Path ([IO.Path]::GetTempPath()) ("terminal-font-"+[guid]::NewGuid()); New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $zip=Join-Path $tmp 'Monaspace.zip'; Get-GitHubAsset ryanoasis/nerd-fonts ("v"+$Versions.NERD_FONTS_VERSION) 'Monaspace.zip' $zip
            Expand-Archive -Force $zip (Join-Path $tmp 'x')
            $fontDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'; New-Item -ItemType Directory -Force $fontDir | Out-Null
            $reg='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
            Get-ChildItem (Join-Path $tmp 'x') -Recurse -File | Where-Object { $_.Name -match '^MonaspiceNeNerdFont.*\.(ttf|otf)$' } | ForEach-Object {
                $dest=Join-Path $fontDir $_.Name; Copy-Item -Force $_.FullName $dest
                New-ItemProperty -Path $reg -Name ($_.BaseName+' (TrueType)') -Value $dest -PropertyType String -Force | Out-Null
            }
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # Hook PowerShell 7 non-destructively by sourcing the managed profile from the user's existing profile.
    if(-not $DryRun){
        $pwsh=Get-Command pwsh -ErrorAction SilentlyContinue
        if($pwsh){
            $profilePath=(& $pwsh.Source -NoLogo -NoProfile -Command '$PROFILE.CurrentUserAllHosts').Trim()
            New-Item -ItemType Directory -Force (Split-Path $profilePath) | Out-Null
            New-Item -ItemType Directory -Force (Join-Path $Backup 'external') | Out-Null
            if(Test-Path $profilePath){ Copy-Item -Force $profilePath (Join-Path $Backup 'external\PowerShell-profile.ps1'); Set-Content -LiteralPath (Join-Path $Backup 'external\PowerShell-profile-existed') -Value '1' -NoNewline -Encoding utf8NoBOM } else { Set-Content -LiteralPath (Join-Path $Backup 'external\PowerShell-profile-existed') -Value '0' -NoNewline -Encoding utf8NoBOM }
            Set-Content -LiteralPath (Join-Path $State 'powershell-profile-path') -Value $profilePath -NoNewline -Encoding utf8NoBOM
            $text=if(Test-Path $profilePath){ Get-Content $profilePath -Raw }else{''}
            $begin='# BEGIN TERMINAL-ENV'; $end='# END TERMINAL-ENV'
            $block = "`r`n$begin`r`n`$managed = Join-Path `$HOME '.config\terminal-env\powershell\profile.ps1'`r`nif (Test-Path `$managed) { . `$managed }`r`n$end`r`n"
            $pattern='(?s)\r?\n?# BEGIN TERMINAL-ENV.*?# END TERMINAL-ENV\r?\n?'
            $text=[regex]::Replace($text,$pattern,'').TrimEnd()+$block
            Set-Content -LiteralPath $profilePath -Value $text -Encoding utf8NoBOM -NoNewline
        }
    }

    # Windows Terminal fragment is additive; preserve any pre-existing fragment at our namespace.
    if(-not $NoTerminalConfig -and -not $DryRun){
        $fragDir=Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\terminal-env'
        New-Item -ItemType Directory -Force (Join-Path $Backup 'external') | Out-Null
        if(Test-Path $fragDir){ Copy-Item -Recurse -Force $fragDir (Join-Path $Backup 'external\WindowsTerminal-fragment'); Set-Content -LiteralPath (Join-Path $Backup 'external\WindowsTerminal-fragment-existed') -Value '1' -NoNewline -Encoding utf8NoBOM }
        else { Set-Content -LiteralPath (Join-Path $Backup 'external\WindowsTerminal-fragment-existed') -Value '0' -NoNewline -Encoding utf8NoBOM }
        New-Item -ItemType Directory -Force $fragDir | Out-Null
        Copy-Item -Force (Join-Path $Source 'dot_config\windows-terminal\terminal-env.json') (Join-Path $fragDir 'terminal-env.json')
        $settingsCandidates=@(
          (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
          (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
        )
        $settings=$settingsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if($settings){
            New-Item -ItemType Directory -Force (Join-Path $Backup 'external') | Out-Null
            Copy-Item -Force $settings (Join-Path $Backup 'external\WindowsTerminal-settings.json')
            Set-Content -LiteralPath (Join-Path $State 'windows-terminal-settings-path') -Value $settings -NoNewline -Encoding utf8NoBOM
            $raw=Get-Content $settings -Raw; $guid='{f4fcbca4-728d-4e4d-a520-45a0e623d5ff}'
            if($raw -match '"defaultProfile"\s*:'){ $raw=[regex]::Replace($raw,'"defaultProfile"\s*:\s*"[^"]*"',('"defaultProfile": "'+$guid+'"'),1) }
            else { $raw=[regex]::Replace($raw,'\{',("{`n    `"defaultProfile`": `"$guid`","),1) }
            Set-Content -LiteralPath $settings -Value $raw -Encoding utf8NoBOM -NoNewline
        }
    }

    Good "Installation complete. Backup: $Backup"
    Write-Host 'Open a new Windows Terminal tab using the Terminal Environment profile.'
    $InstallActive = $false
} catch {
    Restore-Transaction
    throw
}

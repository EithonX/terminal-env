$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

[void](Get-Content -LiteralPath (Join-Path $root 'dot_config\oh-my-posh\terminal.omp.json') -Raw | ConvertFrom-Json)
[void](Get-Content -LiteralPath (Join-Path $root 'dot_config\windows-terminal\terminal-env.json') -Raw | ConvertFrom-Json)

$files = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count) {
        throw "PowerShell parse failed: $($file.FullName): $($errors[0].Message)"
    }

    # Inspect actual command ASTs instead of grepping text. This intentionally
    # ignores comments, strings and this validator's own diagnostics.
    $setContentCommands = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Set-Content'
    }, $true)

    foreach ($command in $setContentCommands) {
        $parameters = @(
            $command.CommandElements |
                Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
                ForEach-Object { $_.ParameterName }
        )
        if (-not (($parameters -contains 'LiteralPath') -or ($parameters -contains 'Path'))) {
            throw "Unsafe positional Set-Content path: $($file.FullName):$($command.Extent.StartLineNumber)"
        }
        if (-not ($parameters -contains 'Value')) {
            throw "Unsafe positional Set-Content value: $($file.FullName):$($command.Extent.StartLineNumber)"
        }
    }
}

$versionMap = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $root 'versions.env')) {
    if ($line -match '^\s*([^#=\s]+)\s*=(.*)$') {
        $versionMap[$Matches[1]] = $Matches[2].Trim()
    }
}
if ($versionMap['ZSH_AUTOSUGGESTIONS_REF'] -ne 'v0.7.1') { throw 'zsh-autosuggestions pin is missing' }
if ($versionMap.ContainsKey('DEJA_VERSION')) { throw 'Deja must not remain a managed default dependency' }
$profileText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\profile.ps1') -Raw
if ($profileText -notmatch 'RightArrow\s+-Function\s+ForwardChar') { throw 'RightArrow must preserve cursor movement through ForwardChar' }
if ($profileText -notmatch 'Ctrl\+RightArrow\s+-Function\s+ForwardWord') { throw 'Ctrl+RightArrow must preserve word movement through ForwardWord' }
if ($profileText -match 'RightArrow\s+-Function\s+AcceptSuggestion') { throw 'RightArrow must not be prediction-only' }
if ($profileText -match 'Ctrl\+RightArrow\s+-Function\s+AcceptNextSuggestionWord') { throw 'Ctrl+RightArrow must not be prediction-only' }
$ompText = Get-Content -LiteralPath (Join-Path $root 'dot_config\oh-my-posh\terminal.omp.json') -Raw
$omp = $ompText | ConvertFrom-Json
$promptTemplates = (($omp.blocks | Where-Object { $_.type -eq 'prompt' } | ForEach-Object { $_.segments } | ForEach-Object { $_.template }) -join "`n")
if ($promptTemplates -cmatch 'ROOT' -or $promptTemplates -cmatch 'ADMIN') { throw 'Elevated-shell prompt is too noisy' }
if ($promptTemplates -notmatch '\{\{ if \.Root \}\}#\{\{ else \}\}❯\{\{ end \}\}' -or $omp.console_title_template -notmatch '\.Root') { throw 'Compact elevated-shell prompt/title indicator is missing' }
$updateText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\update.ps1') -Raw
if ($updateText -match 'install\.ps1') { throw 'terminal-update must not conflate source updates with dependency installation' }
foreach ($option in '--check','--remote','--branch') { if ($updateText -notmatch [regex]::Escape($option)) { throw "PowerShell terminal-update does not accept $option" } }
foreach ($pair in @(
    @('update.ps1','terminal-update'),
    @('deps.ps1','terminal-deps'),
    @('doctor.ps1','terminal-doctor'),
    @('rollback.ps1','terminal-rollback'),
    @('backup.ps1','terminal-backup')
)) {
    $scriptPath = Join-Path $root ("dot_config\terminal-env\powershell\" + $pair[0])
    & $scriptPath '--help' *> $null
    $rejected = $false
    try { & $scriptPath '--terminal-env-invalid-option' *> $null } catch { $rejected = $true }
    if (-not $rejected) { throw "$($pair[1]) accepts unknown options" }
}
$depsText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\deps.ps1') -Raw
if ($depsText -notmatch '\$installArgs\s*=\s*@\{[^}]*Profile\s*=\s*\$targetProfile[^}]*Force\s*=\s*\$true[^}]*\}' -or $depsText -notmatch '@installArgs') { throw 'PowerShell terminal-deps sync must use named parameter splatting' }
if ($depsText.Contains("@('-Profile'") -or $depsText -match '\$LASTEXITCODE[^\r\n]*Dependency sync failed') { throw 'PowerShell terminal-deps sync uses invalid script invocation status handling' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\deps.ps1'))) { throw 'PowerShell terminal-deps implementation is missing' }
$wt = Get-Content -LiteralPath (Join-Path $root 'dot_config\windows-terminal\terminal-env.json') -Raw | ConvertFrom-Json
$hiddenUpdates = @($wt.profiles | Where-Object { $_.PSObject.Properties.Name -contains 'updates' -and $_.hidden })
foreach ($guid in '{574e775e-4f2a-5b96-ac1e-a2962a402336}','{5fb123f1-af88-5b5c-8953-d14a8def1978}') {
    if (-not ($hiddenUpdates | Where-Object updates -eq $guid)) { throw "Windows Terminal generated PowerShell profile is not hidden: $guid" }
}
$installText = Get-Content -LiteralPath (Join-Path $root 'install.ps1') -Raw
if ($installText -notmatch 'function\s+Stop-ManagedOhMyPosh') { throw 'Windows installer is missing the managed Oh My Posh lock handler' }
if ($installText -notmatch '\$env:GITHUB_TOKEN' -or $installText -notmatch '\$env:GH_TOKEN') { throw 'Windows GitHub release lookup does not support authenticated API requests' }
if ($installText -notmatch 'already installed' -or $installText -notmatch 'ConvertFrom-Json') { throw 'Windows dependency provisioning is not idempotent' }
if ($installText -notmatch 'if\(\$Binary\s+-eq\s+''oh-my-posh''\)\s*\{\s*Stop-ManagedOhMyPosh\s*\}') { throw 'Windows installer does not stop the managed renderer before dependency replacement' }
if ($installText -notmatch 'Restore-Transaction[\s\S]*Stop-ManagedOhMyPosh') { throw 'Windows rollback does not handle the managed renderer lock' }
if ($installText -notmatch '\$installError\s*=\s*\$_[\s\S]*throw\s+\$installError') { throw 'Windows installer can mask the original error during rollback' }
if ($installText -notmatch 'Monaspace\.tar\.xz' -or $installText -match 'Monaspace\.zip') { throw 'Windows font provisioning must use the compact tar.xz asset' }
foreach ($face in 'Regular','Bold','Italic','BoldItalic') { if ($installText -notmatch [regex]::Escape($face)) { throw "Windows font provisioning is missing RIBBI face: $face" } }
if ($installText -notmatch 'Get-AppxPackage -Name Microsoft\.PowerShell') { throw 'PowerShell bootstrap does not support the WinGet MSIX layout' }
if ($installText -notmatch 'Microsoft\\WindowsApps\\pwsh\.exe') { throw 'PowerShell bootstrap is missing the MSIX app-execution-alias fallback' }
if ($installText -notmatch 'backups\\transactions') { throw 'Windows transaction backups are not separated from manual backups' }
if ($installText -notmatch 'Prune-TransactionBackups\s+3') { throw 'Windows transaction retention policy is missing' }
$bootstrapText = Get-Content -LiteralPath (Join-Path $root 'bootstrap.ps1') -Raw
if ($bootstrapText -notmatch 'https://github.com/EithonX/terminal-env\.git') { throw 'Windows bootstrap repository is incorrect' }
if ($bootstrapText -notmatch 'TERMINAL_ENV_REPO') { throw 'Windows bootstrap repository override is missing' }
if ($bootstrapText -notmatch 'Repair-WinGetPackageManager -Force -Latest') { throw 'Windows bootstrap cannot repair WinGet' }
if ($bootstrapText -notmatch 'function\s+Test-WinGet' -or $bootstrapText -notmatch 'git\.exe[\s\S]*--version') { throw 'Windows bootstrap does not validate prerequisite executables' }
if (-not $bootstrapText.Contains("'-ExecutionPolicy','Bypass'")) { throw 'Windows bootstrap does not use process-scoped execution-policy bypass for the local installer' }
if ($bootstrapText -notmatch 'clone --quiet --depth 1 --single-branch --branch') { throw 'Windows bootstrap does not create an updateable Git-backed install source' }
$readmeText = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
if ($readmeText -notmatch [regex]::Escape('irm https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.ps1 | iex')) { throw 'README Windows bootstrap command is not compact' }
if ($readmeText -notmatch [regex]::Escape('curl -fsSL https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.sh | bash')) { throw 'README Unix bootstrap command is not compact' }
$backupText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\backup.ps1') -Raw
if ($backupText -notmatch 'backups\\manual') { throw 'Windows manual backups are not isolated from transaction retention' }

Write-Host 'smoke: PASS' -ForegroundColor Green

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

[void](Get-Content -LiteralPath (Join-Path $root 'dot_config\oh-my-posh\terminal.omp.json') -Raw | ConvertFrom-Json)
[void](Get-Content -LiteralPath (Join-Path $root 'dot_config\windows-terminal\terminal-env.json') -Raw | ConvertFrom-Json)

$files = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File
$asts = @{}
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
    $asts[$file.FullName] = $ast

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

$unixTextFiles = @(
    Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
        $_.Name -like '*.sh' -or
        $_.Name -like '*.zsh' -or
        $_.Name -like '*.zsh.tmpl' -or
        $_.Name -like 'executable_*' -or
        $_.FullName -eq (Join-Path $root 'dot_zshenv.tmpl') -or
        $_.FullName -eq (Join-Path $root 'dot_config\zsh\dot_zprofile') -or
        $_.FullName -eq (Join-Path $root 'dot_config\zsh\dot_zshrc')
    }
)
foreach ($file in $unixTextFiles) {
    if ([IO.File]::ReadAllBytes($file.FullName) -contains [byte]13) {
        throw "Unix shell source was checked out with CRLF: $($file.FullName)"
    }
}

foreach ($relativePath in 'dot_config\terminal-env\powershell\doctor.ps1','dot_config\terminal-env\powershell\deps.ps1','dot_config\terminal-env\powershell\update.ps1','dot_config\terminal-env\powershell\terminal.ps1') {
    $scriptPath = Join-Path $root $relativePath
    $profileCollisions = @($asts[$scriptPath].FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.VariablePath.UserPath -ieq 'PROFILE'
    }, $true))
    if ($profileCollisions.Count) {
        throw "Managed profile state collides with the PowerShell PROFILE automatic variable: $relativePath"
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
foreach ($option in '--check','--remote','--branch','--format','--color','--quiet') { if ($updateText -notmatch [regex]::Escape($option)) { throw "PowerShell terminal-update does not accept $option" } }
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
function Assert-TerminalEnvOutputLines {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$CapturedOutput,
        [Parameter(Mandatory=$true)][string[]]$RequiredLines,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $helpText = @($CapturedOutput | ForEach-Object { [string]$_ }) -join "`n"
    $helpLines = @($helpText -split '\r?\n' | ForEach-Object { $_.Trim() })
    foreach ($requiredLine in $RequiredLines) {
        if ($helpLines -notcontains $requiredLine) {
            throw "$Message`nMissing help line: $requiredLine`nActual help:`n$helpText"
        }
    }
}

$terminalPath=Join-Path $root 'dot_config\terminal-env\powershell\terminal.ps1'
$terminalHelp=@(& $terminalPath '--help')
Assert-TerminalEnvOutputLines -CapturedOutput $terminalHelp -RequiredLines @('Usage','terminal <command> [options]') -Message 'Unified terminal root help is invalid'
$terminalVersionJson=@(& $terminalPath 'version' '--format' 'json' '--color' 'never') -join "`n"
$terminalVersionPayload=$terminalVersionJson|ConvertFrom-Json
if($terminalVersionPayload.command -ne 'version' -or [string]::IsNullOrWhiteSpace([string]$terminalVersionPayload.profile)){throw 'Unified terminal version JSON contract is invalid'}
$terminalDoctorHelp=@(& $terminalPath 'doctor' '--help')
Assert-TerminalEnvOutputLines -CapturedOutput $terminalDoctorHelp -RequiredLines @('Usage: terminal doctor [options]','terminal-doctor [options]') -Message 'Unified terminal doctor delegation failed'
$terminalDepsCheckHelp=@(& $terminalPath 'deps' 'check' '--help')
Assert-TerminalEnvOutputLines -CapturedOutput $terminalDepsCheckHelp -RequiredLines @('Usage: terminal deps [status|sync] [options]','terminal-deps [status|sync] [options]') -Message 'Unified terminal deps check alias failed'
$terminalContextHelp=@(& $terminalPath 'context' '--help')
Assert-TerminalEnvOutputLines -CapturedOutput $terminalContextHelp -RequiredLines @('Usage: terminal context [options]','terminal-context [options]') -Message 'Unified terminal context help is inconsistent'
$contextScriptPath=Join-Path $root 'dot_config\terminal-env\powershell\context.ps1'
$standaloneContextHelp=@(& $contextScriptPath '--help')
Assert-TerminalEnvOutputLines -CapturedOutput $standaloneContextHelp -RequiredLines @('Usage: terminal context [options]','terminal-context [options]') -Message 'PowerShell terminal-context help emitted no usable output'
$standaloneContextJson=@(& $contextScriptPath '--cwd' $root '--format' 'json') -join "`n"
if([string]::IsNullOrWhiteSpace($standaloneContextJson)){throw 'PowerShell terminal-context JSON output is empty'}
$standaloneContextPayload=$standaloneContextJson|ConvertFrom-Json
if($standaloneContextPayload.schema_version -ne 1 -or [string]::IsNullOrWhiteSpace([string]$standaloneContextPayload.cwd)){throw 'PowerShell terminal-context JSON contract is invalid'}
$unifiedContextJson=@(& $terminalPath 'context' '--cwd' $root '--format' 'json') -join "`n"
if([string]::IsNullOrWhiteSpace($unifiedContextJson)){throw 'Unified terminal context JSON output is empty'}
$unifiedContextPayload=$unifiedContextJson|ConvertFrom-Json
if($unifiedContextPayload.schema_version -ne 1 -or [string]::IsNullOrWhiteSpace([string]$unifiedContextPayload.cwd)){throw 'Unified terminal context JSON contract is invalid'}
$pwshExecutable=(Get-Command pwsh -ErrorAction Stop).Source
$directContextJson=@(& $pwshExecutable -NoLogo -NoProfile -File $terminalPath 'context' '--cwd' $root '--format' 'json') -join "`n"
if($LASTEXITCODE -ne 0){throw "Unified terminal direct-process success returned exit code $LASTEXITCODE"}
$directContextPayload=$directContextJson|ConvertFrom-Json
if($directContextPayload.schema_version -ne 1){throw 'Unified terminal direct-process JSON contract is invalid'}
$missingContextPath=Join-Path ([IO.Path]::GetTempPath()) ("terminal-env-missing-"+[guid]::NewGuid().ToString('N'))
& $pwshExecutable -NoLogo -NoProfile -File $terminalPath 'context' '--cwd' $missingContextPath '--format' 'json' *> $null
if($LASTEXITCODE -eq 0){throw 'Unified terminal direct-process failure returned exit code 0'}
$profileTerminalFunctions=@($asts[(Join-Path $root 'dot_config\terminal-env\powershell\profile.ps1')].FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'terminal'},$true))
if($profileTerminalFunctions.Count -ne 1){throw 'PowerShell profile does not expose unified terminal command'}
$depsText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\deps.ps1') -Raw
if ($depsText -notmatch '\$installArgs\s*=\s*@\{[^}]*Profile\s*=\s*\$targetProfile[^}]*Force\s*=\s*\$true[^}]*\}' -or $depsText -notmatch '@installArgs') { throw 'PowerShell terminal-deps sync must use named parameter splatting' }
if ($depsText.Contains("@('-Profile'") -or $depsText -match '\$LASTEXITCODE[^\r\n]*Dependency sync failed') { throw 'PowerShell terminal-deps sync uses invalid script invocation status handling' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\deps.ps1'))) { throw 'PowerShell terminal-deps implementation is missing' }
$wt = Get-Content -LiteralPath (Join-Path $root 'dot_config\windows-terminal\terminal-env.json') -Raw | ConvertFrom-Json
$hiddenUpdates = @($wt.profiles | Where-Object { $_.PSObject.Properties.Name -contains 'updates' -and $_.hidden })
foreach ($guid in '{574e775e-4f2a-5b96-ac1e-a2962a402336}','{5fb123f1-af88-5b5c-8953-d14a8def1978}') {
    if (-not ($hiddenUpdates | Where-Object updates -eq $guid)) { throw "Windows Terminal generated PowerShell profile is not hidden: $guid" }
}
$installPath = Join-Path $root 'install.ps1'
$installText = Get-Content -LiteralPath $installPath -Raw
$installAst = $asts[$installPath]
$installParameters=@($installAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach($parameter in 'Format','Color','Quiet'){
    if($installParameters -notcontains $parameter){throw "Windows installer is missing output parameter: $parameter"}
}
$installFunctions = @($installAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
$stopFunction = @($installFunctions | Where-Object Name -eq 'Stop-ManagedOhMyPosh')
if ($stopFunction.Count -ne 1) { throw 'Windows installer is missing the managed Oh My Posh lock handler' }
if ($installText -notmatch '\$env:GITHUB_TOKEN' -or $installText -notmatch '\$env:GH_TOKEN') { throw 'Windows GitHub release lookup does not support authenticated API requests' }
if ($installText -notmatch 'already installed' -or $installText -notmatch 'ConvertFrom-Json') { throw 'Windows dependency provisioning is not idempotent' }
foreach ($functionName in 'Install-Portable','Restore-Transaction') {
    $functionAst = @($installFunctions | Where-Object Name -eq $functionName)
    if ($functionAst.Count -ne 1) { throw "Windows installer function is missing: $functionName" }
    $stopCalls = @($functionAst[0].FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Stop-ManagedOhMyPosh'
    }, $true))
    if ($stopCalls.Count -eq 0) { throw "$functionName does not stop the managed renderer" }
}
if ($installText -notmatch '\$installError\s*=\s*\$_[\s\S]*throw\s+\$installError') { throw 'Windows installer can mask the original error during rollback' }
if ($installText -notmatch 'Monaspace\.tar\.xz' -or $installText -match 'Monaspace\.zip') { throw 'Windows font provisioning must use the compact tar.xz asset' }
foreach ($face in 'Regular','Bold','Italic','BoldItalic') { if ($installText -notmatch [regex]::Escape($face)) { throw "Windows font provisioning is missing RIBBI face: $face" } }
if ($installText -notmatch 'Get-AppxPackage -Name Microsoft\.PowerShell') { throw 'PowerShell bootstrap does not support the WinGet MSIX layout' }
if ($installText -notmatch 'Microsoft\\WindowsApps\\pwsh\.exe') { throw 'PowerShell bootstrap is missing the MSIX app-execution-alias fallback' }
if ($installText -notmatch 'backups\\transactions') { throw 'Windows transaction backups are not separated from manual backups' }
if ($installText -notmatch 'Prune-TransactionBackups\s+3') { throw 'Windows transaction retention policy is missing' }
$dryInstallJson=@(& $installPath -Profile minimal -DryRun -NoFont -NoTerminalConfig -Format json -Color never) -join "`n"
$dryInstallPayload=$dryInstallJson | ConvertFrom-Json
if($dryInstallPayload.command -ne 'install' -or $dryInstallPayload.status -ne 'dry-run' -or -not $dryInstallPayload.dry_run){throw 'Windows installer JSON dry-run contract is invalid'}
$dryInstallHuman=@(& $installPath -Profile minimal -DryRun -NoFont -NoTerminalConfig -Format human -Color never)
Assert-TerminalEnvOutputLines -CapturedOutput $dryInstallHuman -RequiredLines @('Preflight','Plan','Finish') -Message 'Windows installer human output is missing a required stage'
$dryInstallQuiet=@(& $installPath -Profile minimal -DryRun -NoFont -NoTerminalConfig -Quiet)
if($dryInstallQuiet.Count){throw 'Windows installer quiet dry-run emitted stdout'}
$uninstallPath=Join-Path $root 'uninstall.ps1'
$uninstallHelp=@(& $uninstallPath '--help')
Assert-TerminalEnvOutputLines -CapturedOutput $uninstallHelp -RequiredLines @('Usage: ./uninstall.ps1 [options]') -Message 'Windows uninstall help is invalid'
$uninstallHelpText=@($uninstallHelp | ForEach-Object { [string]$_ }) -join "`n"
if($uninstallHelpText -notmatch '--no-restore'){throw 'Windows uninstall help is missing --no-restore'}
$uninstallRejected=$false
try{& $uninstallPath '--terminal-env-invalid-option' *> $null}catch{$uninstallRejected=$true}
if(-not $uninstallRejected){throw 'Windows uninstall accepts unknown options'}
$dryUninstallJson=@(& $uninstallPath '--no-restore' '--dry-run' '--format=json' '--color=never') -join "`n"
$dryUninstallPayload=$dryUninstallJson|ConvertFrom-Json
if($dryUninstallPayload.command -ne 'uninstall' -or $dryUninstallPayload.status -ne 'planned' -or $dryUninstallPayload.restore_requested){throw 'Windows uninstall JSON dry-run contract is invalid'}
$dryUninstallHuman=@(& $uninstallPath '--no-restore' '--dry-run' '--format=human' '--color=never')
Assert-TerminalEnvOutputLines -CapturedOutput $dryUninstallHuman -RequiredLines @('Terminal Environment · uninstall','Plan') -Message 'Windows uninstall human dry-run contract is invalid'
$dryUninstallQuiet=@(& $uninstallPath '--no-restore' '--dry-run' '--quiet')
if($dryUninstallQuiet.Count){throw 'Windows uninstall quiet dry-run emitted stdout'}
$uninstallConfirmationRejected=$false
try{& $uninstallPath '--no-restore' '--no-input' '--format=human' *> $null}catch{$uninstallConfirmationRejected=$true}
if(-not $uninstallConfirmationRejected){throw 'Windows uninstall mutates without explicit noninteractive confirmation'}
$bootstrapPath=Join-Path $root 'bootstrap.ps1'
$bootstrapText = Get-Content -LiteralPath $bootstrapPath -Raw
$bootstrapAst=$asts[$bootstrapPath]
$bootstrapParameters=@($bootstrapAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach($parameter in 'Format','Color','Quiet'){
    if($bootstrapParameters -notcontains $parameter){throw "Windows bootstrap is missing installer output parameter: $parameter"}
}
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

& (Join-Path $root 'tests\context_resolver.ps1')

$outputScript=Join-Path $root 'dot_config\terminal-env\powershell\output.ps1'
. $outputScript
$oldNoColor=$env:NO_COLOR;$oldColumns=$env:COLUMNS
try{
    $env:NO_COLOR='1';$env:COLUMNS='50'
    Initialize-TerminalEnvUI -Format human -ColorMode auto
    $row=@(Write-TerminalEnvRow 'PowerShell' '7.6.6') -join "`n"
    if($row -ne "  PowerShell`n    7.6.6"){throw 'PowerShell renderer narrow-row layout is incorrect'}
    $attention=@(Write-TerminalEnvAttention warn 'PowerShell' 'mixed provenance') -join "`n"
    if($attention -ne "  PowerShell`n    warning · mixed provenance"){throw 'PowerShell renderer attention layout is incorrect'}
    if((Format-TerminalEnvStyle warning 'warning') -match "`e\["){throw 'PowerShell renderer ignores NO_COLOR'}
    $unsafe="ok`e[31m red`e[0m`nnext"
    $clean=Get-TerminalEnvSafeText $unsafe
    if($clean -match "`e" -or $clean -match "`n"){throw 'PowerShell renderer does not sanitize terminal controls'}
}finally{
    $env:NO_COLOR=$oldNoColor;$env:COLUMNS=$oldColumns
}

Write-Host 'smoke: PASS' -ForegroundColor Green
exit 0

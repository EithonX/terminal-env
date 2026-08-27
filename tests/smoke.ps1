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
$updateText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\update.ps1') -Raw
if ($updateText -match 'install\.ps1') { throw 'terminal-update must not conflate source updates with dependency installation' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\deps.ps1'))) { throw 'PowerShell terminal-deps implementation is missing' }
$installText = Get-Content -LiteralPath (Join-Path $root 'install.ps1') -Raw
if ($installText -notmatch 'function\s+Stop-ManagedOhMyPosh') { throw 'Windows installer is missing the managed Oh My Posh lock handler' }
if ($installText -notmatch 'if\(-not \$DryRun\)\{ Stop-ManagedOhMyPosh \}') { throw 'Windows installer does not stop the managed renderer before dependency replacement' }
if ($installText -notmatch 'Restore-Transaction[\s\S]*Stop-ManagedOhMyPosh') { throw 'Windows rollback does not handle the managed renderer lock' }
if ($installText -notmatch '\$installError\s*=\s*\$_[\s\S]*throw\s+\$installError') { throw 'Windows installer can mask the original error during rollback' }
if ($installText -notmatch 'Monaspace\.tar\.xz' -or $installText -match 'Monaspace\.zip') { throw 'Windows font provisioning must use the compact tar.xz asset' }
foreach ($face in 'Regular','Bold','Italic','BoldItalic') { if ($installText -notmatch [regex]::Escape($face)) { throw "Windows font provisioning is missing RIBBI face: $face" } }
if ($installText -notmatch 'backups\\transactions') { throw 'Windows transaction backups are not separated from manual backups' }
if ($installText -notmatch 'Prune-TransactionBackups\s+3') { throw 'Windows transaction retention policy is missing' }
$backupText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\backup.ps1') -Raw
if ($backupText -notmatch 'backups\\manual') { throw 'Windows manual backups are not isolated from transaction retention' }

Write-Host 'smoke: PASS' -ForegroundColor Green

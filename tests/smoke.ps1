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

Write-Host 'smoke: PASS' -ForegroundColor Green

$versions = Get-Content -LiteralPath (Join-Path $root 'versions.env') -Raw
if ($versions -notmatch '(?m)^ZSH_AUTOSUGGESTIONS_REF=v0\.7\.1$') { throw 'zsh-autosuggestions pin is missing' }
if ($versions -match '(?m)^DEJA_VERSION=') { throw 'Deja must not remain a managed default dependency' }
$updateText = Get-Content -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\update.ps1') -Raw
if ($updateText -match 'install\.ps1') { throw 'terminal-update must not conflate source updates with dependency installation' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'dot_config\terminal-env\powershell\deps.ps1'))) { throw 'PowerShell terminal-deps implementation is missing' }

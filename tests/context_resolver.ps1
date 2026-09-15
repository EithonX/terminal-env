$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$contextScript = Join-Path $root 'dot_config\terminal-env\powershell\context.ps1'
. $contextScript

function New-ContextFixtureRepo {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    & git -C $Path init -q
    & git -C $Path config user.email terminal-env@example.invalid
    & git -C $Path config user.name 'Terminal Env Test'
    Set-Content -LiteralPath (Join-Path $Path '.seed') -Value 'fixture'
    & git -C $Path add .
    & git -C $Path commit -qm fixture
}

function Write-FakeCommand {
    param([string]$Path, [string[]]$Lines)
    Set-Content -LiteralPath $Path -Value (@('@echo off') + $Lines) -Encoding ascii
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('terminal-env-context-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$oldLog = $env:TERMINAL_ENV_TEST_LOG
$oldNode = $env:FAKE_NODE_VERSION
$oldPython = $env:FAKE_PYTHON_VERSION
$oldGo = $env:FAKE_GO_VERSION
$oldRust = $env:FAKE_RUST_VERSION
$oldGoToolchain = $env:GOTOOLCHAIN
try {
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $fake = Join-Path $temp 'fakebin'
    New-Item -ItemType Directory -Force -Path $fake | Out-Null
    $log = Join-Path $temp 'tools.log'
    Write-FakeCommand (Join-Path $fake 'node.cmd') @(
        'echo node %1 offline=%MISE_OFFLINE% auto=%MISE_AUTO_INSTALL% notfound=%MISE_NOT_FOUND_AUTO_INSTALL%>>"%TERMINAL_ENV_TEST_LOG%"',
        'echo v%FAKE_NODE_VERSION%'
    )
    Write-FakeCommand (Join-Path $fake 'python.cmd') @(
        'echo python %1>>"%TERMINAL_ENV_TEST_LOG%"',
        'echo Python %FAKE_PYTHON_VERSION%'
    )
    Copy-Item -LiteralPath (Join-Path $fake 'python.cmd') -Destination (Join-Path $fake 'python3.cmd')
    Write-FakeCommand (Join-Path $fake 'go.cmd') @(
        'echo go %1 toolchain=%GOTOOLCHAIN% offline=%MISE_OFFLINE%>>"%TERMINAL_ENV_TEST_LOG%"',
        'echo go version go%FAKE_GO_VERSION% test/test'
    )
    Write-FakeCommand (Join-Path $fake 'rustc.cmd') @(
        'echo rustc %1 auto=%RUSTUP_AUTO_INSTALL%>>"%TERMINAL_ENV_TEST_LOG%"',
        'echo rustc %FAKE_RUST_VERSION% (fixture 2026-01-01)'
    )
    $env:PATH = "$fake$([IO.Path]::PathSeparator)$oldPath"
    $env:TERMINAL_ENV_TEST_LOG = $log
    $env:FAKE_NODE_VERSION = '22.14.0'
    $env:FAKE_PYTHON_VERSION = '3.12.7'
    $env:FAKE_GO_VERSION = '1.23.4'
    $env:FAKE_RUST_VERSION = '1.85.1'
    $env:GOTOOLCHAIN = 'local'

    $quiet = Join-Path $temp 'quiet'
    New-ContextFixtureRepo $quiet
    $src = Join-Path $quiet 'src'
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    Set-Content -LiteralPath (Join-Path $src 'index.js') -Value '// source only'
    Set-Content -LiteralPath (Join-Path $src 'tool.py') -Value '# source only'
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $ctx = Resolve-TerminalEnvContext -Cwd $src
    if ($ctx.toolchains.Count -ne 0) { throw 'Source files without declarations produced runtime context' }
    if (Test-Path -LiteralPath $log) { throw 'Source files without declarations executed a runtime' }

    Set-Content -LiteralPath (Join-Path $temp '.nvmrc') -Value '99'
    $ctx = Resolve-TerminalEnvContext -Cwd $src
    if ($ctx.toolchains.Contains('node')) { throw 'Context discovery escaped the Git repository boundary' }

    $mono = Join-Path $temp 'mono'
    New-ContextFixtureRepo $mono
    Set-Content -LiteralPath (Join-Path $mono '.nvmrc') -Value '22'
    $nested = Join-Path $mono 'services\legacy'
    New-Item -ItemType Directory -Force -Path $nested | Out-Null
    Set-Content -LiteralPath (Join-Path $nested '.nvmrc') -Value '20'
    $env:FAKE_NODE_VERSION = '20.11.1'
    $ctx = Resolve-TerminalEnvContext -Cwd $nested
    if ($ctx.toolchains['node'].selector.value -ne '20' -or $ctx.toolchains['node'].prompt -ne 'node 20') { throw 'Nearest Node selector did not win within its source family' }
    $nodeLog = Get-Content -LiteralPath $log -Raw
    if ($nodeLog -notmatch 'offline=true' -or $nodeLog -notmatch 'auto=false' -or $nodeLog -notmatch 'notfound=false') { throw 'Runtime probing did not disable mise network/auto-install behavior' }
    $plain = @(Write-TerminalEnvContextPlain $ctx) -join "`n"
    if ($plain -notmatch [regex]::Escape("context`troot`t$mono")) { throw 'Context plain output lost the repository root' }
    if ($plain -notmatch [regex]::Escape("toolchain`tnode`tselector`t20`tnvmrc`t$(Join-Path $nested '.nvmrc')")) { throw 'Context plain output lost Node selector provenance' }
    if ($plain -notmatch [regex]::Escape("toolchain`tnode`tactive`t20.11.1`tpath`t")) { throw 'Context plain output lost the active runtime' }
    if ($plain -notmatch [regex]::Escape("prompt`ttext`tnode 20")) { throw 'Context plain output lost prompt context' }

    Set-Content -LiteralPath (Join-Path $nested '.node-version') -Value '22'
    $ctx = Resolve-TerminalEnvContext -Cwd $nested
    if (-not $ctx.toolchains['node'].conflict -or $null -ne $ctx.toolchains['node'].selector -or $ctx.toolchains['node'].prompt -ne 'node !') { throw 'Conflicting Node selectors were silently resolved' }

    $mismatch = Join-Path $mono 'services\mismatch'
    New-Item -ItemType Directory -Force -Path $mismatch | Out-Null
    Set-Content -LiteralPath (Join-Path $mismatch '.nvmrc') -Value '20'
    $env:FAKE_NODE_VERSION = '24.7.0'
    $ctx = Resolve-TerminalEnvContext -Cwd $mismatch
    if (-not $ctx.toolchains['node'].mismatch -or $ctx.toolchains['node'].prompt -ne 'node 24 ≠ 20') { throw 'Node active/selected mismatch is not reported' }

    $symbolic = Join-Path $mono 'services\symbolic'
    New-Item -ItemType Directory -Force -Path $symbolic | Out-Null
    Set-Content -LiteralPath (Join-Path $symbolic '.nvmrc') -Value 'lts/*'
    $ctx = Resolve-TerminalEnvContext -Cwd $symbolic
    if ($ctx.toolchains['node'].selector_status -ne 'unknown' -or $ctx.toolchains['node'].mismatch -or $ctx.toolchains['node'].prompt -ne 'node lts/*') { throw 'Non-numeric selector compatibility was guessed' }

    $packageRoot = Join-Path $temp 'package'
    New-ContextFixtureRepo $packageRoot
    $packageSatisfied = Join-Path $packageRoot 'satisfied'
    New-Item -ItemType Directory -Force -Path $packageSatisfied | Out-Null
    Set-Content -LiteralPath (Join-Path $packageSatisfied 'package.json') -Value '{"engines":{"node":">=22"}}'
    $ctx = Resolve-TerminalEnvContext -Cwd $packageSatisfied
    if ($ctx.toolchains['node'].constraint.kind -ne 'package-engines' -or $ctx.toolchains['node'].constraint_status -ne 'satisfied' -or $ctx.toolchains['node'].prompt -ne 'node ≥22') { throw 'package.json engines.node is not treated as a constraint' }

    $packageRange = Join-Path $packageRoot 'range'
    New-Item -ItemType Directory -Force -Path $packageRange | Out-Null
    Set-Content -LiteralPath (Join-Path $packageRange 'package.json') -Value '{"engines":{"node":">=22 <24"}}'
    $ctx = Resolve-TerminalEnvContext -Cwd $packageRange
    if ($ctx.toolchains['node'].constraint_status -ne 'unknown' -or $ctx.toolchains['node'].mismatch -or $ctx.toolchains['node'].prompt -ne 'node ≥22 <24') { throw 'Unsupported constraint syntax must remain explicit rather than guessed' }

    $packageFamily = Join-Path $packageRoot 'family'
    New-Item -ItemType Directory -Force -Path $packageFamily | Out-Null
    Set-Content -LiteralPath (Join-Path $packageFamily 'package.json') -Value '{"engines":{"node":"22"}}'
    $ctx = Resolve-TerminalEnvContext -Cwd $packageFamily
    if ($ctx.toolchains['node'].constraint_status -ne 'mismatch' -or $ctx.toolchains['node'].prompt -ne 'node 24 < 22.x') { throw 'Node partial-version constraint is not evaluated as a version family' }

    $packageMalformed = Join-Path $packageRoot 'malformed'
    New-Item -ItemType Directory -Force -Path $packageMalformed | Out-Null
    Set-Content -LiteralPath (Join-Path $packageMalformed 'package.json') -Value '{"devEngines":{"runtime":"invalid"},"engines":{"node":">=22"}}'
    $ctx = Resolve-TerminalEnvContext -Cwd $packageMalformed
    if ($null -ne $ctx.toolchains['node'].selector -or $ctx.toolchains['node'].constraint.kind -ne 'package-engines') { throw 'Malformed devEngines hid valid engines metadata' }

    $packageSelector = Join-Path $packageRoot 'selector'
    New-Item -ItemType Directory -Force -Path $packageSelector | Out-Null
    Set-Content -LiteralPath (Join-Path $packageSelector 'package.json') -Value '{"devEngines":{"runtime":{"name":"node","version":"22"}}}'
    $ctx = Resolve-TerminalEnvContext -Cwd $packageSelector
    if ($ctx.toolchains['node'].selector.kind -ne 'package-devEngines' -or -not $ctx.toolchains['node'].selector.source) { throw 'package.json devEngines.runtime is not treated as a selector' }

    $unsafeSelector = Join-Path $temp 'unsafe-selector'
    New-ContextFixtureRepo $unsafeSelector
    [IO.File]::WriteAllText((Join-Path $unsafeSelector '.nvmrc'), "22$([char]27)]0;unsafe$([char]7)`n")
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $ctx = Resolve-TerminalEnvContext -Cwd $unsafeSelector
    if ($ctx.toolchains.Contains('node')) { throw 'Control characters in selectors were accepted' }
    if (Test-Path -LiteralPath $log) { throw 'Rejected selector executed a runtime' }

    $unsafeConstraintRoot = Join-Path $temp 'unsafe-constraint'
    New-ContextFixtureRepo $unsafeConstraintRoot
    Set-Content -LiteralPath (Join-Path $unsafeConstraintRoot '.nvmrc') -Value '22'
    $unsafeConstraint = "{`"engines`":{`"node`":`">=22\u001b[31m`"}}"
    Set-Content -LiteralPath (Join-Path $unsafeConstraintRoot 'package.json') -Value $unsafeConstraint
    $env:FAKE_NODE_VERSION = '22.14.0'
    $ctx = Resolve-TerminalEnvContext -Cwd $unsafeConstraintRoot
    if ($null -ne $ctx.toolchains['node'].constraint -or $ctx.prompt.text.Contains([char]27)) { throw 'Control characters in constraints were accepted' }

    $python = Join-Path $temp 'python'
    New-ContextFixtureRepo $python
    Set-Content -LiteralPath (Join-Path $python 'pyproject.toml') -Value @('[project]','name = "fixture"','requires-python = ">=3.12" # inline comment')
    $env:FAKE_PYTHON_VERSION = '3.11.9'
    $ctx = Resolve-TerminalEnvContext -Cwd $python
    if (-not $ctx.toolchains['python'].mismatch -or $ctx.toolchains['python'].prompt -ne 'py 3.11 < ≥3.12') { throw 'Python requires-python mismatch is not reported' }
    Set-Content -LiteralPath (Join-Path $python '.python-version') -Value '3.11'
    $ctx = Resolve-TerminalEnvContext -Cwd $python
    if ($ctx.toolchains['python'].selector.value -ne '3.11' -or -not $ctx.toolchains['python'].mismatch -or $ctx.toolchains['python'].prompt -ne 'py 3.11 < ≥3.12') { throw 'Python selector must not hide an incompatible requires-python constraint' }

    $go = Join-Path $temp 'go'
    New-ContextFixtureRepo $go
    Set-Content -LiteralPath (Join-Path $go 'go.mod') -Value @('module example.test/fixture','','go 1.23','toolchain go1.24.1')
    $env:FAKE_GO_VERSION = '1.23.4'
    $ctx = Resolve-TerminalEnvContext -Cwd $go
    if (-not $ctx.toolchains['go'].mismatch -or $ctx.toolchains['go'].selector.value -ne 'go1.24.1') { throw 'Go toolchain directive mismatch is not reported' }
    $env:FAKE_GO_VERSION = '1.25.0'
    $ctx = Resolve-TerminalEnvContext -Cwd $go
    if ($ctx.toolchains['go'].mismatch -or $ctx.toolchains['go'].prompt -ne 'go 1.24.1') { throw 'A newer Go runtime should satisfy a toolchain suggestion' }
    $env:FAKE_GO_VERSION = '1.22.0'
    $env:GOTOOLCHAIN = 'auto'
    $ctx = Resolve-TerminalEnvContext -Cwd $go
    if ($null -ne $ctx.toolchains['go'].active -or -not $ctx.toolchains['go'].note -or $ctx.toolchains['go'].prompt -ne 'go 1.24.1 · active?') { throw 'Go auto-toolchain uncertainty is not surfaced without triggering a download' }
    $env:GOTOOLCHAIN = 'local'

    $rust = Join-Path $temp 'rust'
    New-ContextFixtureRepo $rust
    Set-Content -LiteralPath (Join-Path $rust 'rust-toolchain.toml') -Value @('[toolchain]','channel = "1.85"')
    Set-Content -LiteralPath (Join-Path $rust 'Cargo.toml') -Value @('[package]','name = "fixture"','version = "0.1.0"','rust-version = "1.80"')
    $env:FAKE_RUST_VERSION = '1.84.0'
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $ctx = Resolve-TerminalEnvContext -Cwd $rust
    if (-not $ctx.toolchains['rust'].mismatch) { throw 'Rust selected/active mismatch is not reported' }
    if ((Get-Content -LiteralPath $log -Raw) -notmatch 'auto=0') { throw 'Rust probing did not disable rustup auto-install' }

    $mise = Join-Path $temp 'mise'
    New-ContextFixtureRepo $mise
    Set-Content -LiteralPath (Join-Path $mise '.mise.toml') -Value @('[tools]','node = "22"')
    $miseNested = Join-Path $mise 'apps\legacy'
    New-Item -ItemType Directory -Force -Path $miseNested | Out-Null
    Set-Content -LiteralPath (Join-Path $miseNested '.mise.toml') -Value @('[tools]','node = "20" # nearest override')
    $env:FAKE_NODE_VERSION = '20.12.0'
    $miseContext = Resolve-TerminalEnvContext -Cwd $miseNested
    if ($miseContext.toolchains['node'].conflict -or $miseContext.toolchains['node'].selector.value -ne '20') { throw 'Nearest mise selector did not override the same source family at the repository root' }
    Set-Content -LiteralPath (Join-Path $miseNested 'mise.toml') -Value @('[tools]','node = "22"')
    $miseContext = Resolve-TerminalEnvContext -Cwd $miseNested
    if (-not $miseContext.toolchains['node'].conflict -or $null -ne $miseContext.toolchains['node'].selector) { throw 'Same-scope mise selector conflict was silently resolved' }

    $json = $ctx | ConvertTo-Json -Depth 8 -Compress
    $roundTrip = $json | ConvertFrom-Json
    if ($roundTrip.schema_version -ne 1 -or -not $roundTrip.toolchains.rust.selector.source -or -not $roundTrip.toolchains.rust.selectors[0].source) { throw 'Context JSON contract lost provenance' }

    $nongit = Join-Path $temp 'nongit\child'
    New-Item -ItemType Directory -Force -Path $nongit | Out-Null
    Set-Content -LiteralPath (Join-Path (Split-Path -Parent $nongit) '.node-version') -Value '99'
    $ctx = Resolve-TerminalEnvContext -Cwd $nongit
    if ($ctx.repository.name -or $ctx.toolchains.Contains('node')) { throw 'Non-repository context escaped the current directory' }
} finally {
    $env:PATH = $oldPath
    foreach ($item in @(
        @('TERMINAL_ENV_TEST_LOG',$oldLog),
        @('FAKE_NODE_VERSION',$oldNode),
        @('FAKE_PYTHON_VERSION',$oldPython),
        @('FAKE_GO_VERSION',$oldGo),
        @('FAKE_RUST_VERSION',$oldRust),
        @('GOTOOLCHAIN',$oldGoToolchain)
    )) {
        if ($null -eq $item[1]) { Remove-Item ("Env:" + $item[0]) -ErrorAction SilentlyContinue } else { Set-Item ("Env:" + $item[0]) $item[1] }
    }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'context resolver: PASS'

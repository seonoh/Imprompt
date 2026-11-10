# Imprompt one-line installer for Windows (PowerShell 5.1+/7), pinned to a release commit SHA. Paste into PowerShell (<SHA> = the 40-char release commit, use the command from the install page as is):
#   $env:IMPROMPT_COMMIT='<SHA>'; irm https://raw.githubusercontent.com/seonoh/Imprompt/<SHA>/get.ps1 | iex
# Same as the same commit's bootstrap.ps1 with IMPROMPT_MODE=use: clone/update into %LOCALAPPDATA%\Imprompt (an existing official Desktop\Imprompt is updated in place) and check out that commit (HEAD must equal it exactly), install Python / AutoHotkey v2 (winget)
# and the engine CLI (Claude Code official installer) if missing, register MCP, set up the global Ctrl+Q hotkey,
# and open the browser sign-in if no engine is signed in.
# Without IMPROMPT_COMMIT (development/testing) the DefaultRef tag is used and the commit it points to is printed.
# The release tag must equal the repository VERSION file (see "release procedure" at the bottom of README.md).
# ASCII only on purpose (irm | iex). Overrides: $env:AI_TOOLS_REF (version; developers: 'main') $env:AI_TOOLS_DIR $env:AI_TOOLS_REPO $env:IMPROMPT_BOOTSTRAP_URL (testing) - non-default addresses are reported with "!".
$DefaultRef = 'v2.0.0'
# result code for Imprompt-Setup.cmd: stays 1 unless bootstrap.ps1 reaches install.ps1 (then its exit code) - every early stop is a failure
$global:ImpromptRC = 1
# old Windows 10 PowerShell 5.1 may not offer TLS 1.2 by default (GitHub requires it)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
$env:IMPROMPT_MODE = 'use'
# Elevated (Administrator) PowerShell installs into the profile of the account that elevated, not the current user -> stop (IMPROMPT_ALLOW_ADMIN=1 overrides; CI runners are elevated, so CI=true only warns)
$isAdmin = $false
try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch {}
if ($isAdmin -and $env:IMPROMPT_ALLOW_ADMIN -ne '1') {
    Write-Host 'x This window runs as Administrator. Close it and run the setup again WITHOUT "Run as administrator" (an Administrator window installs into the administrator account, not yours).'
    if ($env:CI -eq 'true') { Write-Host '  (CI environment: continuing)' } else { Write-Host '  (Advanced: IMPROMPT_ALLOW_ADMIN=1 skips this check.)'; return }
}
# git is required by bootstrap.ps1; most non-developer PCs lack it -> install Git for Windows via winget first
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if ($env:IMPROMPT_NO_PKG -ne '1' -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host '... installing Git (winget install -e --id Git.Git) - a permission (UAC) window may appear'
        $base = @('install', '-e', '--id', 'Git.Git', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        $a1 = $base + @('--scope', 'user')
        & winget @a1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "... user-scope install failed (exit code $LASTEXITCODE), retrying with the default scope"
            & winget @base | Out-Host
        }
        if ($LASTEXITCODE -ne 0) { Write-Host "x winget could not install Git (exit code $LASTEXITCODE, see the winget output above)" }
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host 'x git is required -> install Git for Windows (https://git-scm.com/downloads/win) and run again'; return }
}
$ref = if ($env:AI_TOOLS_REF) { $env:AI_TOOLS_REF } else { $DefaultRef }
$commit = if ($env:IMPROMPT_COMMIT) { $env:IMPROMPT_COMMIT } else { '' }
if ($commit -and $commit -cnotmatch '^[0-9a-f]{40}$') { Write-Host "x IMPROMPT_COMMIT must be a 40-char lowercase hex commit SHA: $commit"; return }
if ($commit) { Write-Host "pinned commit: $commit" }
elseif ($ref -ne $DefaultRef) { Write-Host "! non-default version: $ref (the official release is $DefaultRef)" }
if ($env:AI_TOOLS_REPO) { Write-Host "! non-default address: AI_TOOLS_REPO=$($env:AI_TOOLS_REPO)" }
if ($env:IMPROMPT_BOOTSTRAP_URL) { Write-Host "! non-default address: IMPROMPT_BOOTSTRAP_URL=$($env:IMPROMPT_BOOTSTRAP_URL)" }
$env:AI_TOOLS_REF = $ref                                           # the same tag is checked out by bootstrap.ps1
$u = if ($env:IMPROMPT_BOOTSTRAP_URL) { $env:IMPROMPT_BOOTSTRAP_URL } else { "https://raw.githubusercontent.com/seonoh/Imprompt/$(if ($commit) { $commit } else { $ref })/bootstrap.ps1" }
try { $code = Invoke-RestMethod $u } catch { Write-Host "x could not download the installer: $u (check internet / repository visibility)"; return }
Invoke-Expression $code

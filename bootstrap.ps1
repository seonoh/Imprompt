# One-line installer for Windows PowerShell 5.1+/7 (no Git Bash needed), pinned to a release commit SHA (<SHA> = the 40-char release commit):
#   $env:IMPROMPT_COMMIT='<SHA>'; irm https://raw.githubusercontent.com/seonoh/Imprompt/<SHA>/bootstrap.ps1 | iex
# Clones (or updates) the repo into %LOCALAPPDATA%\Imprompt (an existing official Desktop\Imprompt from older installs is updated in place), checks out that commit and verifies HEAD equals it exactly (stops otherwise), then registers the MCP server via install.ps1.
#   $env:IMPROMPT_COMMIT='<40-char lowercase hex>'   pin to that commit (AI_TOOLS_REF is ignored; a moved tag cannot affect it)
#   $env:AI_TOOLS_REF='<tag|branch|commit>'   only without IMPROMPT_COMMIT; default is $DefaultRef below (must equal the VERSION file); developers: $env:AI_TOOLS_REF='main'
#   $env:AI_TOOLS_DIR='C:\path'   change location      $env:AI_TOOLS_REPO='<url>'   testing only (a "! non-default address" warning is printed)
#   $env:IMPROMPT_MODE='use'     install everything (Python/AutoHotkey via winget, MCP, global Ctrl+Q hotkey)
# Safety: stops if an existing folder's origin is not the official address; tags are never fetched with --force -
# if the tag already on disk points to a different commit than the remote tag, the install stops.
# ASCII only on purpose: works both via `irm | iex` (no BOM allowed) and as a file under PowerShell 5.1 (no BOM -> ANSI).
# Same logic as bootstrap.sh; every git step is checked and the install stops on failure (never installs a stale/unknown version).
$ErrorActionPreference = 'Continue'
$DefaultRef = 'v2.0.1'
function Fail([string]$msg) { Write-Host "x $msg"; throw "imprompt bootstrap stopped" }
function Git-Ok { & git @args; if ($LASTEXITCODE -ne 0) { Fail "git $($args -join ' ') failed" } }
function Norm-Url([string]$u) { $u = $u.Trim().TrimEnd('/'); if ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }; return $u.TrimEnd('/').ToLowerInvariant() }
function Is-Official([string]$u) { return (@('https://github.com/seonoh/imprompt', 'git@github.com:seonoh/imprompt', 'ssh://git@github.com/seonoh/imprompt') -contains (Norm-Url $u)) }
try {
    $fresh = $false                                                   # irm | iex runs in the caller's scope: never inherit a previous run's value
    $Repo = if ($env:AI_TOOLS_REPO) { $env:AI_TOOLS_REPO } else { 'https://github.com/seonoh/Imprompt.git' }
    $Dir = if ($env:AI_TOOLS_DIR) { $env:AI_TOOLS_DIR } else { '' }
    $Ref = if ($env:AI_TOOLS_REF) { $env:AI_TOOLS_REF } else { $DefaultRef }
    $Commit = if ($env:IMPROMPT_COMMIT) { $env:IMPROMPT_COMMIT } else { '' }
    if ($Commit -and $Commit -cnotmatch '^[0-9a-f]{40}$') { Fail "IMPROMPT_COMMIT must be a 40-char lowercase hex commit SHA: $Commit" }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is required -> install Git for Windows and run again' }
    if (-not $Dir) {
        # default %LOCALAPPDATA%\Imprompt (the Desktop is often OneDrive-synced, may contain '&', and is easy to delete by accident);
        # an older install on the Desktop whose origin is official keeps being updated in place
        $Dir = Join-Path $env:LOCALAPPDATA 'Imprompt'
        $old = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Imprompt'
        if (-not (Test-Path (Join-Path $Dir '.git')) -and (Test-Path (Join-Path $old '.git'))) {
            $oo = & git -C $old remote get-url origin 2>$null
            if ($LASTEXITCODE -eq 0 -and $oo -and (Is-Official ([string]$oo))) { $Dir = $old }
        }
    }
    if ($Ref -notmatch '^[A-Za-z0-9._/][A-Za-z0-9._/-]*$') { Fail "invalid version (AI_TOOLS_REF): $Ref" }
    if ($env:AI_TOOLS_REPO) { Write-Host "! non-default address: AI_TOOLS_REPO=$Repo" }
    if (Test-Path (Join-Path $Dir '.git')) {
        $origin = (& git -C $Dir remote get-url origin 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $origin) { Fail "cannot read the origin address of $Dir - install stopped" }
        $origin = ([string]$origin).Trim()
        if (-not (Is-Official $origin) -and (Norm-Url $origin) -ne (Norm-Url $Repo)) {
            Fail "origin of $Dir is not the official address (https://github.com/seonoh/Imprompt): $origin - install stopped (check the folder or delete it and run again)"
        }
    } else {
        & git clone $Repo $Dir
        if ($LASTEXITCODE -ne 0) { Fail 'clone failed - check the internet connection and that the repository is public' }
        $fresh = $true
    }
    if ($Commit) {
        # commit pin: do not trust tag/branch names, check out only this SHA (HEAD is verified to equal it below)
        # never fetch by SHA: GitHub serves fork-only commits under the original address, so only commits reachable from official branches/tags are accepted
        # judge only in a namespace that mirrors the remote (refs/imprompt-official/*, --prune + forced) - local tags or planted remote-tracking refs are not trusted
        Git-Ok -C $Dir fetch --quiet --prune --no-tags origin '+refs/heads/*:refs/imprompt-official/heads/*' '+refs/tags/*:refs/imprompt-official/tags/*'
        Git-Ok -C $Dir fetch --quiet origin
        & git -C $Dir cat-file -e "$Commit^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { Fail "commit $Commit is not on an official branch or tag (it may be a fork commit) - install stopped: use the command from the official README or guide page" }
        $refs = & git -C $Dir for-each-ref --contains $Commit refs/imprompt-official/heads/ refs/imprompt-official/tags/ 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $refs) { Fail "commit $Commit is not on an official branch or tag (it may be a fork commit) - install stopped: use the command from the official README or guide page" }
        $target = $Commit
    } else {
        $null = & git -C $Dir ls-remote --exit-code --tags origin "refs/tags/$Ref" 2>$null
        $rc = $LASTEXITCODE
        if ($rc -eq 0) {
            # tag: read the commit the remote points to (annotated tags are peeled with ^{}), then fetch WITHOUT force -
            # git refuses to overwrite an existing local tag of the same name that points elsewhere
            $l = @(& git -C $Dir ls-remote --tags origin "refs/tags/${Ref}^{}" 2>$null)
            if ($l.Count -eq 0 -or -not $l[0]) { $l = @(& git -C $Dir ls-remote --tags origin "refs/tags/$Ref" 2>$null) }
            $want = ([string]$l[0] -split '\s+')[0]
            & git -C $Dir fetch --quiet origin "refs/tags/${Ref}:refs/tags/${Ref}"
            if ($LASTEXITCODE -ne 0) { Fail "could not fetch tag $Ref - if a tag of the same name on disk differs from the remote it may have been tampered with, install stopped" }
            $have = [string](& git -C $Dir rev-parse "refs/tags/${Ref}^{commit}")
            if ($have.Trim() -ne $want) { Fail "tag $Ref on disk ($($have.Trim())) differs from the remote commit ($want) - install stopped" }
            $target = "refs/tags/$Ref"
        } elseif ($rc -eq 2) {
            # not a tag (branch/commit) - developer use. A branch name pins the freshly fetched remote branch, not a possibly stale local one
            Write-Host "! $Ref is not a release tag (developer use) - the official release is tag $DefaultRef"
            Git-Ok -C $Dir fetch --quiet origin
            $target = $Ref
            & git -C $Dir rev-parse --verify -q "refs/remotes/origin/$Ref" *> $null
            if ($LASTEXITCODE -eq 0) { $target = "origin/$Ref" }
        } else { Fail 'could not reach the remote repository - install stopped' }
    }
    Git-Ok -C $Dir -c advice.detachedHead=false checkout --quiet $target
    $got = ([string](& git -C $Dir rev-parse HEAD)).Trim()
    # checkout keeps local edits when the commit is the same -> never run modified tracked files (edits are left untouched)
    $chg = (@(& git -C $Dir status --porcelain --untracked-files=no) -join "`n"); if ($LASTEXITCODE -ne 0) { Fail "cannot check the state of $Dir - install stopped" }
    if ($chg) { Fail "files in $Dir differ from the downloaded commit (your edits are left untouched) - install stopped: undo the edits or delete the folder and run again" }
    if ($Commit) {
        if ($got -ne $Commit) { Fail "checked-out commit ($got) differs from the requested commit ($Commit) - install stopped" }
        Write-Host "pinned: commit $got"
    } else { Write-Host "pinned: $Ref (commit $got)" }
    # mark only a folder this installer cloned (remove deletes only marked folders - protects developer checkouts)
    # the marker records the checked-out commit; remove deletes the folder only while HEAD still equals it (updates rewrite it)
    $mark = Join-Path $Dir '.git\imprompt-installed'
    if ($fresh -or (Test-Path $mark)) { Set-Content -Path $mark -Value @('installed-by=bootstrap.ps1', "commit=$got") -Encoding ASCII }
    $mode = if ($env:IMPROMPT_MODE) { $env:IMPROMPT_MODE } else { 'mcp' }   # 'use' = everything (deps + MCP + global hotkey)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'install.ps1') $mode
    $global:ImpromptRC = $LASTEXITCODE                                 # read by Imprompt-Setup.cmd (0 only when install.ps1 succeeded)
} catch {
    if ("$_" -ne 'imprompt bootstrap stopped') { Write-Host "x $_" }
}

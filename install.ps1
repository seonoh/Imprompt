# Imprompt MCP 설치 (Windows PowerShell 5.1+ / PowerShell 7) — Git Bash 없이 MCP 서버만 등록한다.
#   powershell -ExecutionPolicy Bypass -File install.ps1          MCP 등록
#   powershell -ExecutionPolicy Bypass -File install.ps1 hotkey   전역 단축키(아무 앱에서 블록 → Ctrl+Q, AutoHotkey v2 필요)
#   powershell -ExecutionPolicy Bypass -File install.ps1 use      한 번에 쓸 수 있게: Python·AutoHotkey v2 없으면 winget 설치 → 엔진 CLI 없으면 Claude Code 공식 설치기
#                                                                  → MCP 등록 → 전역 단축키 → 로그인 안 됐으면 브라우저 승인 창. IMPROMPT_NO_PKG=1·IMPROMPT_NO_LOGIN=1 로 건너뜀
#   powershell -ExecutionPolicy Bypass -File install.ps1 uninstall 설치 해제: MCP 등록 해제(claude·codex·gemini) + 시작 프로그램 바로가기 제거 + AutoHotkey(imprompt.ahk) 종료. hotkey.ini·폴더 삭제는 안내만
# 설치된 CLI(claude·codex·gemini)마다 imprompt 를 사용자 범위로 지우고 다시 등록(멱등). 각 CLI 의 공식 'mcp add' 명령만 쓴다.
# Ctrl+Q 개선기(pi-edit)는 bash 가 필요하므로 Git Bash 에서 ./install.sh 를 쓴다.
# 이 파일은 UTF-8(BOM) — PowerShell 5.1 이 한글을 깨뜨리지 않게.
$ErrorActionPreference = 'Continue'   # 5.1 에서 Stop 이면 네이티브 명령의 stderr 리디렉션이 예외가 된다
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Srv = Join-Path $Repo 'prompt-improver\mcp\imprompt_mcp.py'
$Mode = if ($args.Count -gt 0) { [string]$args[0] } else { 'mcp' }

# 관리자 권한으로 실행하면(특히 다른 계정으로 '관리자 실행') 설치가 그 계정의 사용자 폴더·시작 프로그램·PATH 에 들어가 지금 사용자에게는 보이지 않는다.
# IMPROMPT_ALLOW_ADMIN=1 로 우회. GitHub Actions 러너(CI=true)는 관리자이므로 경고만 하고 계속한다
function Test-Admin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}
if ((Test-Admin) -and $env:IMPROMPT_ALLOW_ADMIN -ne '1') {
    Write-Host '! 관리자 권한 PowerShell 입니다. 관리자 권한이 아니라 일반 PowerShell 에서 실행하세요(다른 계정으로 관리자 실행하면 그 계정에 설치됩니다).'
    if ($env:CI -eq 'true') { Write-Host '  (CI 환경이라 경고만 하고 계속합니다)' }
    else { Write-Host '  그래도 진행하려면 IMPROMPT_ALLOW_ADMIN=1 로 다시 실행하세요.'; exit 1 }
}

# 후보 하나를 5초 안에 실행해 3.8+ 이면 sys.executable 을 돌려준다(멈추는 스텁에 걸리지 않게 타임아웃)
function Test-Python([string]$Exe, [string[]]$Pre) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = ((@($Pre) + @('-c', '"import sys; print(sys.executable) if sys.version_info >= (3, 8) else sys.exit(1)"')) -join ' ').Trim()
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit(5000)) { try { $p.Kill() } catch {}; return $null }
        if ($p.ExitCode -ne 0) { return $null }
        $out = ($p.StandardOutput.ReadToEnd() -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 1)
        if ($out) { return ([string]$out).Trim() }
    } catch {}
    return $null
}
# 3.8+ 인터프리터 절대 경로. PATH 의 py/python/python3(Microsoft Store 안내 스텁 = WindowsApps 별칭은 제외) →
# PATH 가 아직 갱신되지 않은 직후 설치본을 위해 %LOCALAPPDATA%\Programs\Python\Python3*, %ProgramFiles%\Python3* 직접 탐색(최신 버전 우선)
function Find-Python {
    $cands = @()
    foreach ($n in @('py', 'python', 'python3')) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
        if ($c) { $cands += @{ exe = $c.Source; pre = $(if ($n -eq 'py') { @('-3') } else { @() }) } }
    }
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs\Python'), $env:ProgramFiles)) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $dirs = @(Get-ChildItem -Path $root -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue | Sort-Object { [int](($_.Name -replace '\D', '0')) } -Descending)
        foreach ($d in $dirs) {
            $e = Join-Path $d.FullName 'python.exe'
            if (Test-Path $e) { $cands += @{ exe = $e; pre = @() } }
        }
    }
    foreach ($c in $cands) {
        $r = Test-Python $c.exe $c.pre
        if ($r) { return $r }
    }
    return $null
}

# Register <cli> <지우기 인자> <등록 인자>
function Register([string]$Cli, [string[]]$RemoveArgs, [string[]]$AddArgs) {
    # npm 전역 설치는 .ps1 shim 도 만들고 PowerShell 은 그것을 먼저 고른다 → .ps1 은 '--' 를 삼켜 서버 인자(--host)가 CLI 옵션으로 해석될 수 있다.
    # 그래서 .cmd/.exe 를 우선 실행한다
    $exe = Find-Cli $Cli
    if (-not $exe) { Write-Host "  - $Cli 없음(건너뜀)"; return 0 }
    & $exe @RemoveArgs *> $null
    & $exe @AddArgs *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ $Cli"; return 1 }
    Write-Host "  ✗ $Cli 등록 실패 → $Cli $($AddArgs -join ' ')"
    return 0
}

# 한 번에(use, "사용할 수 있게 해줘"): 필요한 프로그램이 없으면 winget 으로 설치 → MCP 등록 → 전역 단축키. IMPROMPT_NO_PKG=1 이면 설치 건너뜀
function Find-Ahk {
    $p = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $p) { $c = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue; if ($c) { $p = $c.Source } }
    return $p
}
function Install-Pkg([string]$Name, [string]$Id, [string]$Override = '') {
    if ($env:IMPROMPT_NO_PKG -eq '1') { Write-Host "  - $Name 자동 설치 건너뜀(IMPROMPT_NO_PKG=1)"; return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Host "  ✗ $Name 없음 · 자동 설치 도구(winget)도 없음 → Microsoft Store 에서 '앱 설치 관리자'를 설치·업데이트한 뒤 이 설치 파일을 다시 실행(또는 $Name 를 직접 설치)"; return }
    Write-Host "  … $Name 설치 중 (winget install -e --id $Id) — 관리자 권한(UAC) 확인 창이 뜰 수 있습니다"
    $base = @('install', '-e', '--id', $Id, '--silent', '--accept-package-agreements', '--accept-source-agreements')
    if ($Override) { $base += @('--override', $Override) }       # --override 는 설치기 인자 전체를 대체한다 → /quiet 도 직접 넣는다
    $a1 = $base + @('--scope', 'user')                                                 # 가능하면 사용자 범위(관리자 권한 없이)
    & winget @a1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  … 사용자 범위로는 설치되지 않아(종료 코드 $LASTEXITCODE) 기본 범위로 다시 시도합니다"
        & winget @base | Out-Host
    }
    if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ $Name 설치" } else { Write-Host "  ✗ $Name 설치 실패(종료 코드 $LASTEXITCODE, 위 winget 출력 참고) → winget install -e --id $Id" }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')   # 새 PATH 바로 반영
}
# 엔진 CLI(claude·codex·gemini) 실행 파일. npm 설치는 .cmd, 공식 설치기는 %USERPROFILE%\.local\bin\claude.exe
function Find-Cli([string]$Name) {
    foreach ($n in @("$Name.cmd", "$Name.exe", $Name)) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    if ($Name -eq 'claude') {
        # 공식 설치기는 claude.exe 를 두고도 사용자 PATH 에 넣지 않는다. Claude 데스크톱 앱의 번들 위치(%APPDATA%\Claude\claude-code\<버전>)도 본다
        $p = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
        if (Test-Path $p) { return $p }
        $d = Get-ChildItem -Path (Join-Path $env:APPDATA 'Claude\claude-code') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
            Where-Object { Test-Path (Join-Path $_.FullName 'claude.exe') } | Select-Object -First 1
        if ($d) { return (Join-Path $d.FullName 'claude.exe') }
    }
    # Codex 공식 설치기 기본 위치(https://chatgpt.com/codex/install.ps1 → %LOCALAPPDATA%\Programs\OpenAI\Codex\bin), npm 전역(%APPDATA%\npm)
    $fixed = @{ codex = @((Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'), (Join-Path $env:APPDATA 'npm\codex.cmd'))
                gemini = @((Join-Path $env:APPDATA 'npm\gemini.cmd')) }
    foreach ($p in @($fixed[$Name])) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}
# 쓸 구독(엔진): IMPROMPT_ENGINE(claude|codex|gemini, 에이전트가 자기 엔진을 넘긴다) → 이미 설치된 CLI 가 있으면 그대로($null)
#   → 사람이 직접 실행한 창이면 한 번 묻는다(Claude / ChatGPT / Gemini) → 묻지 못하면 claude
function Want-Engine {
    $e = ([string]$env:IMPROMPT_ENGINE).Trim().ToLower()
    if (@('claude', 'codex', 'gemini') -contains $e) { return $e }
    if ((Find-Cli 'claude') -or (Find-Cli 'codex') -or (Find-Cli 'gemini')) { return $null }
    $canAsk = ($env:IMPROMPT_NO_LOGIN -ne '1') -and ($env:CI -ne 'true') -and [Environment]::UserInteractive
    try { if ([Console]::IsInputRedirected) { $canAsk = $false } } catch { $canAsk = $false }
    if (-not $canAsk) { return 'claude' }
    Write-Host '  어떤 AI 구독을 쓰세요? (그 구독의 CLI 를 설치하고 로그인합니다)'
    Write-Host '    1) Claude (claude.ai)   2) ChatGPT (Codex CLI)   3) Gemini (Google)'
    $a = (Read-Host '  번호 [1]').Trim()
    switch ($a) { '2' { return 'codex' } '3' { return 'gemini' } default { return 'claude' } }
}
function Refresh-Path {
    $env:Path = (Join-Path $env:USERPROFILE '.local\bin') + ';' + (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin') + ';' + (Join-Path $env:APPDATA 'npm') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
# 공식 설치기(PowerShell 스크립트)를 별도 powershell 에서 실행한다 — 설치기가 exit 를 불러도 이 스크립트는 이어 간다.
# 주소는 문자열에 끼워 넣지 않고 인자로 넘긴다(주소에 따옴표 등이 있어도 명령이 바뀌지 않게)
function Run-Installer([string]$u) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -Command { param($u) irm $u | iex } -args $u 2>&1
    Refresh-Path
    return @($o)
}
# 사용자 PATH(레지스트리 HKCU\Environment)에 폴더를 추가한다(이미 있으면 그대로). 확장 문자열(%VAR%)을 보존하고, 환경 변경을 브로드캐스트해 새로 여는 터미널이 바로 보게 한다
function Add-UserPath([string]$Dir) {
    if (-not (Test-Path $Dir)) { return }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $cur = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $has = (@($cur -split ';' | Where-Object { $_ } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') }) -contains $Dir.TrimEnd('\'))
    if ($has) { Write-Host "  ✓ 터미널에서 claude 명령 사용 가능($Dir)"; $key.Close(); return }
    $new = if ($cur) { $cur.TrimEnd(';') + ';' + $Dir } else { $Dir }
    $key.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.Close()
    try { [Environment]::SetEnvironmentVariable('IMPROMPT_BROADCAST', '1', 'User'); [Environment]::SetEnvironmentVariable('IMPROMPT_BROADCAST', $null, 'User') } catch {}
    $env:Path = $Dir + ';' + $env:Path
    Write-Host "  ✓ 새로 연 터미널부터 claude 명령을 쓸 수 있게 했습니다 ($Dir)"
}
# 단축키가 쓸 주 엔진: 로그인된 엔진 우선(claude → codex → gemini), 없으면 설치된 첫 엔진, 그것도 없으면 claude (install.sh 의 pick_host 와 같은 규칙)
function Pick-Host([string]$Py) {
    $env:PYTHONIOENCODING = 'utf-8'
    $st = (& $Py $Srv --status-json 2>$null) -join ''
    try { $j = $st | ConvertFrom-Json } catch { return 'claude' }
    $order = @('claude', 'codex', 'gemini')
    $pref = ([string]$(if ($env:IMPROMPT_ENGINE) { $env:IMPROMPT_ENGINE } else { $env:IMPROMPT_PREFER })).Trim().ToLower()   # 사용자가 고른 구독을 같은 조건에서 먼저
    if ($order -contains $pref) {
        $order = @($pref) + @($order | Where-Object { $_ -ne $pref })
        if ($j.$pref -and $j.$pref -ne 'missing') { return $pref }   # 고른 구독이 설치돼 있으면 로그인 전이라도 그것(로그인은 뒤 단계·트레이 Sign in)
    }
    foreach ($e in $order) { if ($j.$e -eq 'ok') { return $e } }
    foreach ($e in $order) { if ($j.$e -and $j.$e -ne 'missing') { return $e } }
    return $order[0]
}
# 설치할 때 고르는 단축키: IMPROMPT_HOTKEY("Ctrl+Shift+Q" 같은 표기) → imprompt_mcp.py --hotkey-spec 이 검사해 AutoHotkey 키로. 실패하면 이유를 알리고 기존·기본 키 유지
function Hotkey-FromEnv([string]$Py) {
    if (-not $env:IMPROMPT_HOTKEY) { return '' }
    $env:PYTHONIOENCODING = 'utf-8'
    $o = & $Py $Srv --hotkey-spec $env:IMPROMPT_HOTKEY --target ahk 2>&1
    if ($LASTEXITCODE -eq 0 -and "$o".Trim() -match '^[\^!+#]+[a-z0-9]{1,3}$') { return "$o".Trim() }
    Write-Host "  ! 단축키 '$($env:IMPROMPT_HOTKEY)' 를 쓸 수 없습니다: $o → 기본(또는 지금) 단축키로 둡니다. 나중에 트레이 아이콘 → Change Hotkey..."
    return ''
}
function Hotkey-Label([string]$k) {
    $m = [regex]::Match($k, '^([\^!+#]*)(.*)$'); $s = ''
    foreach ($c in $m.Groups[1].Value.ToCharArray()) { $s += @{ '^' = 'Ctrl+'; '!' = 'Alt+'; '+' = 'Shift+'; '#' = 'Win+' }[[string]$c] }
    return $s + $m.Groups[2].Value.ToUpper()
}
# 단축키(AutoHotkey 의 imprompt.ahk)가 지금 실행 중인가
function Test-HotkeyRunning {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*imprompt.ahk*' })
    return ($procs.Count -gt 0)
}
# 엔진 CLI 공식 설치(사용자 범위, 관리자 권한 없음). 새 창 없이 이어서 찾도록 PATH 를 바로 갱신
#   claude: https://code.claude.com/docs/en/setup (irm https://claude.ai/install.ps1 | iex)
#   codex : https://learn.chatgpt.com/docs/codex/cli (irm https://chatgpt.com/codex/install.ps1 | iex, Node 불필요)
#   gemini: https://geminicli.com/docs/get-started/installation (Node.js 20+ → npm install -g @google/gemini-cli)
$EngineName = @{ claude = 'Claude Code'; codex = 'Codex CLI (ChatGPT)'; gemini = 'Gemini CLI' }
$EngineHint = @{ claude = 'irm https://claude.ai/install.ps1 | iex'; codex = 'irm https://chatgpt.com/codex/install.ps1 | iex'
                 gemini = 'winget install -e --id OpenJS.NodeJS.LTS 후 npm install -g @google/gemini-cli' }
function Ensure-Engine {
    Write-Host '엔진 CLI (개선을 실제로 하는 AI — 사용자 본인 구독):'
    $want = if ($script:EngineAsked) { $script:AskedEngine } else { Want-Engine }   # use 는 설치 시작 때 이미 물었다(긴 설치 중간에 기다리게 하지 않게)
    if (-not $want) { Write-Host '  ✓ 설치됨'; return 0 }
    $script:WantEngine = $want
    $env:IMPROMPT_PREFER = $want                                    # 하위 단계(hotkey 의 Pick-Host)도 고른 구독을 먼저 본다 — 엔진 고정(IMPROMPT_ENGINE)과는 다르다
    $nm = $EngineName[$want]
    if (Find-Cli $want) { Write-Host "  ✓ $nm 설치됨"; return 0 }
    if ($env:IMPROMPT_NO_PKG -eq '1') { Write-Host "  ✗ $nm 없음 · 자동 설치 건너뜀(IMPROMPT_NO_PKG=1) → $($EngineHint[$want])"; return 1 }
    $o = @()
    if ($want -eq 'gemini') {
        $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
        if (-not $npm) { Install-Pkg 'Node.js LTS (Gemini CLI 에 필요)' 'OpenJS.NodeJS.LTS'; Refresh-Path; $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue }
        if ($npm) {
            Write-Host '  … Gemini CLI 설치 중 (npm install -g @google/gemini-cli, 1~3분)'
            $o = @(& $npm.Source install -g '@google/gemini-cli' 2>&1); Refresh-Path
        } else { $o = @('npm 을 찾지 못함 (Node.js 설치 실패)') }
    } else {
        $def = if ($want -eq 'codex') { 'https://chatgpt.com/codex/install.ps1' } else { 'https://claude.ai/install.ps1' }
        $ov = if ($want -eq 'codex') { $env:IMPROMPT_CODEX_INSTALLER } else { $env:IMPROMPT_CLAUDE_INSTALLER }
        $u = if ($ov) { $ov } else { $def }
        if ($ov) { Write-Host "  ⚠ 기본값 아닌 주소: $u" }
        Write-Host "  … $nm 설치 중 (공식 설치기: irm $u | iex, 1~2분)"
        if ($want -eq 'codex') { $env:CODEX_NON_INTERACTIVE = '1' }   # 설치기의 y/N 질문 없이(관리자 권한 없이 사용자 범위)
        $o = Run-Installer $u
    }
    if (Find-Cli $want) { Write-Host "  ✓ $nm 설치"; return 0 }
    Write-Host '  ! 설치기 마지막 출력:'
    @($o) | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" }
    Write-Host "  ✗ $nm 설치 실패 → PowerShell 에서 $($EngineHint[$want]) 후 다시 실행"
    return 1
}
# 로그인된 엔진이 하나도 없으면 고른 구독(없으면 설치된 첫 엔진)의 로그인 창을 보이게 띄우고 최대 5분 기다린다. 실패해도 설치는 성공, 안내만
#   claude: claude auth login --claudeai / codex: codex login(브라우저에서 Sign in with ChatGPT) / gemini: 대화형 첫 화면에서 Login with Google
$LoginHow = @{ claude = 'auth login'; codex = 'login'; gemini = '(실행 후 Login with Google)' }
function Ensure-Login {
    if ($env:IMPROMPT_NO_LOGIN -eq '1') { return }
    $py = Find-Python; if (-not $py) { return }
    $st = (& $py $Srv --status-json 2>$null) -join ''
    $w = if ($script:WantEngine) { $script:WantEngine } else { ([string]$env:IMPROMPT_PREFER).Trim().ToLower() }
    if (@('claude', 'codex', 'gemini') -notcontains $w -or -not (Find-Cli $w)) { $w = '' }
    $okPat = if ($w) { '"' + $w + '": "ok"' } else { '"ok"' }      # 구독을 골랐으면 그 엔진의 로그인만 본다(다른 엔진 로그인으로 건너뛰지 않게)
    if ($st -match $okPat) { return }
    $order = @('claude', 'codex', 'gemini')
    $eng = if ($w) { $w } else { $order | Where-Object { Find-Cli $_ } | Select-Object -First 1 }
    if (-not $eng) { Write-Host '  ! 엔진 CLI 가 없어 로그인할 수 없습니다'; return }
    $cl = Find-Cli $eng
    $how = "& `"$cl`" $($LoginHow[$eng])"
    if (-not $st -or $st -match '"unknown"') {
        Write-Host "  ! 로그인 상태를 확인하지 못했습니다 → 쓰기 전에 PowerShell 에서 $how 로 로그인했는지 확인하세요"
        return
    }
    $wait = if ($env:IMPROMPT_LOGIN_WAIT) { [int]$env:IMPROMPT_LOGIN_WAIT } else { 300 }
    switch ($eng) {
        'claude' { Write-Host '로그인: 보이는 로그인 창을 열고 브라우저에 Claude 승인 창을 엽니다(본인 claude.ai 계정, 최대 5분 기다림)'; $a = @('auth', 'login', '--claudeai') }
        'codex'  { Write-Host '로그인: 보이는 로그인 창을 열고 브라우저에 ChatGPT 로그인 창을 엽니다(본인 ChatGPT 계정, 최대 5분 기다림)'; $a = @('login') }
        'gemini' { Write-Host '로그인: Gemini 창을 엽니다 → 창에서 Login with Google 을 고르고 브라우저에서 승인하세요(최대 5분 기다림, 끝나면 창은 자동으로 닫힘)'; $a = @() }
    }
    $p = if ($a.Count) { Start-Process -FilePath $cl -ArgumentList $a -PassThru } else { Start-Process -FilePath $cl -PassThru }
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $wait) {
        if ($p.HasExited -and $eng -ne 'gemini') { break }
        if ($eng -eq 'gemini' -and ((& $py $Srv --status-json 2>$null) -join '') -match '"gemini": "ok"') { break }
        Start-Sleep -Seconds 3
    }
    if (-not $p.HasExited) { & taskkill.exe /T /F /PID $p.Id *> $null }   # gemini 는 로그인 뒤 대화 화면으로 남는다(gemini.cmd → node) → 창째 닫는다
    $st = (& $py $Srv --status-json 2>$null) -join ''
    if ($st -match $okPat) { Write-Host '  ✓ 로그인 완료' } else { Write-Host "  ! 로그인 안 됨 → 나중에 PowerShell 에서 $how (또는 트레이 아이콘 → Sign in...)" }
}
# 설치 해제: MCP 등록·시작 프로그램 바로가기·실행 중인 단축키만 정리한다. hotkey.ini(단축키 설정)·폴더·엔진 CLI 는 남기고 안내만
# 설치 해제(uninstall: 연결만 끊음, 폴더·설정은 안내) / 완전 제거(remove: 설정 → 앱 → Imprompt → 제거, 트레이 → Uninstall Imprompt...)
#   remove 는 uninstall 에 더해 '설치된 앱' 등록·설정(%APPDATA%\imprompt)·기록(~\.imprompt)·설치 폴더까지 지운다.
#   설치 폴더는 설치기가 받은 그대로(특정 커밋에 고정·고친 파일 없음)일 때만 지운다 — 개발용 작업 폴더를 지우지 않게.
#   Git·Python·AutoHotkey·엔진 CLI 는 다른 곳에서도 쓸 수 있어 남기고 안내만.
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Imprompt'
if ($Mode -eq 'uninstall' -or $Mode -eq 'remove') {
    Write-Host $(if ($Mode -eq 'remove') { '== Imprompt 완전 제거 ==' } else { '== Imprompt 설치 해제 ==' })
    $undo = @{ claude = @('mcp', 'remove', '-s', 'user', 'imprompt'); codex = @('mcp', 'remove', 'imprompt'); gemini = @('mcp', 'remove', '-s', 'user', 'imprompt') }
    foreach ($c in @('claude', 'codex', 'gemini')) {
        $exe = Find-Cli $c
        if (-not $exe) { Write-Host "  - $c 없음(건너뜀)"; continue }
        $ra = $undo[$c]
        & $exe @ra *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ $c MCP 등록 해제" } else { Write-Host "  - $c 에 등록된 imprompt 없음(또는 이미 해제)" }
    }
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Imprompt hotkey.lnk'
    if (Test-Path $lnk) { Remove-Item -Force $lnk; Write-Host '  ✓ 시작 프로그램 바로가기 제거' } else { Write-Host '  - 시작 프로그램 바로가기 없음' }
    $procs = @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*imprompt.ahk*' })
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($procs.Count -gt 0) { Write-Host '  ✓ 실행 중인 Imprompt 단축키(AutoHotkey) 종료' } else { Write-Host '  - 실행 중인 단축키 없음' }
    if ($Mode -eq 'uninstall') {
        Write-Host '남은 것(직접 지우기 — 자동으로 지우지 않음. 한 번에 지우려면 설정 → 앱 → Imprompt → 제거):'
        Write-Host "  · 설치 폴더: $Repo  (삭제하려면 폴더를 지우면 됨)"
        Write-Host '  · 자동 설치된 Git·Python·AutoHotkey·Claude Code 는 설정 → 앱 에서 제거할 수 있음(사용자 PATH 의 .local\bin 항목은 그대로 남음)'
        Write-Host "  · 단축키 설정: $env:APPDATA\imprompt\hotkey.ini (바꾼 단축키 보관 — 다시 설치할 계획이면 남겨 두고, 아니면 폴더째 삭제)"
        Write-Host '  · 로컬 기록: ~\.imprompt\ (작업 내역·캐시). AutoHotkey·Python·엔진 CLI 는 그대로 둠'
        exit 0
    }
    Start-Sleep -Milliseconds 500                                  # 방금 끝낸 AutoHotkey 가 파일을 놓도록
    Set-Location $env:TEMP                                         # 지울 폴더 안에 머물지 않게
    $left = @()
    if (Test-Path $UninstKey) { Remove-Item -Path $UninstKey -Recurse -Force; Write-Host "  ✓ '설치된 앱' 목록에서 제거" }
    $cfg = Join-Path $env:APPDATA 'imprompt'
    if (Test-Path $cfg) { Remove-Item -Recurse -Force $cfg -ErrorAction SilentlyContinue; if (Test-Path $cfg) { $left += $cfg } else { Write-Host "  ✓ 설정 삭제: $cfg" } }
    $home0 = Join-Path $env:USERPROFILE '.imprompt'
    $home2 = if ($env:IMPROMPT_HOME) { $env:IMPROMPT_HOME } else { $home0 }
    # IMPROMPT_HOME 을 다른 폴더로 바꿔 둔 경우 그 폴더째 지우지 않는다(사용자 폴더 오삭제 방지) — 기본 위치만 자동 삭제
    if ($home2.TrimEnd('\') -ne $home0) { Write-Host "  - IMPROMPT_HOME 이 기본 위치가 아니라 지우지 않음: $home2 — Imprompt 기록만 직접 삭제" }
    elseif (Test-Path $home2) { Remove-Item -Recurse -Force $home2 -ErrorAction SilentlyContinue; if (Test-Path $home2) { $left += $home2 } else { Write-Host "  ✓ 기록·내 지침 삭제: $home2" } }
    # 입력창 개선기 기록(Git Bash 수동 설치의 ~\.claude\prompt-improver): Imprompt 가 만든 이름의 파일만(링크·다른 파일은 그대로)
    $pd = Join-Path $env:USERPROFILE '.claude\prompt-improver'; $gone = $false
    foreach ($n in @('invocations.log', 'invocations.log.1', 'last-original.txt', 'last-answers.txt', 'last-ask.log', 'last-run.log')) {
        $fp = Join-Path $pd $n
        if ((Test-Path -LiteralPath $fp -PathType Leaf) -and -not ((Get-Item -LiteralPath $fp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $fp -Force -ErrorAction SilentlyContinue; $gone = $true
        }
    }
    if ($gone) { Write-Host "  ✓ 입력창 개선기 기록 삭제: $pd (기록 파일만)" }
    # 지우는 조건(모두): 설치기가 새로 받은 표식(.git\imprompt-installed) · 브랜치가 아닌 고정 커밋 · git status 성공 + 고친 파일 없음 · 보관(stash) 없음.
    # 하나라도 확인하지 못하면(git 없음·명령 실패 포함) 지우지 않는다
    $git = Get-Command git -ErrorAction SilentlyContinue
    $pinned = $false
    $markF = Join-Path $Repo '.git\imprompt-installed'
    if ($git -and (Test-Path $markF)) {
        # 표식에 적힌 커밋 = HEAD 일 때만(받은 뒤 쌓은 커밋이 있으면 남김). 무시 목록 파일(--ignored)도 고친 파일로 본다(Thumbs.db·desktop.ini 만 예외)
        $mk = @(Get-Content -Path $markF -ErrorAction SilentlyContinue | Where-Object { $_ -cmatch '^commit=[0-9a-f]{40}$' } | ForEach-Object { $_.Substring(7) })[0]
        $hd = ([string](& $git.Source -C $Repo rev-parse HEAD 2>$null)).Trim(); $rcHd = $LASTEXITCODE
        & $git.Source -C $Repo symbolic-ref -q HEAD *> $null; $rcRef = $LASTEXITCODE        # 1 = 브랜치 아님(고정 커밋), 0 = 브랜치, 그 밖 = 오류
        $dirty = (@(& $git.Source -C $Repo status --porcelain --ignored 2>$null) | Where-Object { $_ -and $_ -notmatch '^.. (.*[\\/])?(Thumbs\.db|desktop\.ini)$' }) -join ''; $rcSt = $LASTEXITCODE
        $stash = (& $git.Source -C $Repo stash list 2>$null) -join ''; $rcSh = $LASTEXITCODE
        $pinned = $mk -and ($rcHd -eq 0) -and ($mk -eq $hd) -and ($rcRef -eq 1) -and ($rcSt -eq 0) -and (-not $dirty) -and ($rcSh -eq 0) -and (-not $stash)
    }
    if ($pinned) {
        Remove-Item -Recurse -Force $Repo -ErrorAction SilentlyContinue
        if (Test-Path $Repo) { $left += $Repo } else { Write-Host "  ✓ 설치 폴더 삭제: $Repo" }
    } else { Write-Host "  - 설치 폴더는 남김(설치기가 받은 폴더라는 표식이 없거나, 받은 뒤 커밋·브랜치·고친 파일·보관이 있거나, 확인 실패): $Repo — 필요 없으면 직접 삭제" }
    foreach ($l in $left) { Write-Host "  ! 지우지 못함(다른 프로그램이 사용 중일 수 있음 — 재부팅 뒤 직접 삭제): $l" }
    Write-Host '남겨 둔 것: Git·Python·AutoHotkey·AI CLI(Claude Code 등)는 다른 곳에서도 쓸 수 있어 그대로 둡니다 — 필요 없으면 설정 → 앱에서 제거.'
    if ($env:CI -ne 'true' -and [Environment]::UserInteractive -and $env:IMPROMPT_QUIET -ne '1') {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $msg = if ($left.Count) { "Imprompt 를 제거했어요. 일부는 지우지 못했어요(재부팅 뒤 직접 삭제):`n" + ($left -join "`n") } else { 'Imprompt 를 제거했어요. 단축키·설정·기록이 모두 지워졌어요.' }
            [void][System.Windows.Forms.MessageBox]::Show($msg + "`n`nGit·Python·AutoHotkey·AI CLI 는 남겨 두었어요(설정 → 앱에서 제거 가능).", 'Imprompt')
        } catch {}
    }
    if ($left.Count) { exit 1 } else { exit 0 }
}
if ($Mode -eq 'use') {
    Write-Host '== Imprompt 전체 설치: 필요 프로그램 → AI 프로그램 → 연결 → 단축키 → 로그인 =='
    $env:IMPROMPT_IN_USE = '1'                                     # 하위 단계(mcp)는 중간 점검 출력을 생략
    $script:AskedEngine = Want-Engine; $script:EngineAsked = $true   # 사람에게 묻는 것(엔진 CLI 가 하나도 없을 때 구독 번호)은 맨 처음 한 번 — 그 뒤로는 기다리기만
    if (Find-Python) { Write-Host '  ✓ Python 3.8+' } else { Install-Pkg 'Python 3' 'Python.Python.3.12' '/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 InstallLauncherAllUsers=0' }
    if (Find-Ahk) { Write-Host '  ✓ AutoHotkey v2' } else { Install-Pkg 'AutoHotkey v2' 'AutoHotkey.AutoHotkey' }
    $rcEng = Ensure-Engine
    Add-UserPath (Join-Path $env:USERPROFILE '.local\bin')       # 공식 설치기는 PATH 에 넣지 않는다 → 새 터미널에서 claude 가 되게
    $self = $MyInvocation.MyCommand.Path
    & powershell -NoProfile -ExecutionPolicy Bypass -File $self mcp
    $rcMcp = $LASTEXITCODE
    & powershell -NoProfile -ExecutionPolicy Bypass -File $self hotkey
    $rcKey = $LASTEXITCODE
    Ensure-Login
    $lnkOk = Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'Imprompt hotkey.lnk')
    $runOk = Test-HotkeyRunning
    Write-Host '요약(실제 상태):'
    Write-Host ('  ' + $(if ($rcEng -eq 0) { '✓' } else { '✗' }) + ' 엔진 CLI')
    Write-Host ('  ' + $(if ($rcMcp -eq 0) { '✓' } else { '✗' }) + ' MCP 등록')
    Write-Host ('  ' + $(if ($rcKey -eq 0 -and $lnkOk) { '✓' } else { '✗' }) + ' 시작 프로그램 바로가기')
    Write-Host ('  ' + $(if ($rcKey -eq 0 -and $runOk) { '✓' } else { '✗' }) + ' 단축키(AutoHotkey) 실행 중')
    if ($rcKey -eq 0 -and $lnkOk -and $runOk) { $rcKey = 0 } else { $rcKey = 1 }
    $stU = ''; $pyU = Find-Python; if ($pyU) { $stU = (& $pyU $Srv --status-json 2>$null) -join '' }
    $loginOk = $stU -match '": "ok"'
    Write-Host ('  ' + $(if ($loginOk) { '✓ AI 구독 로그인' } else { '! AI 구독 로그인 안 됨 — 작업 표시줄 ^ 안의 연필 아이콘 우클릭 → Sign in... (브라우저 승인)' }))
    if (-not $loginOk) { Write-Host '남은 일: 위 로그인 한 가지 — 트레이 연필 아이콘 우클릭 → Sign in... (고른 구독의 브라우저 승인 창이 열림)' }
    $iniU = Join-Path $env:APPDATA 'imprompt\hotkey.ini'
    $kU = if (Test-Path $iniU) { (Get-Content $iniU | Where-Object { $_ -match '^hotkey=' } | Select-Object -First 1) } else { $null }
    $labU = if ($kU) { Hotkey-Label (($kU -replace '^hotkey=', '').Trim()) } else { 'Ctrl+Q' }
    Write-Host "쓰는 법: 아무 앱에서 문장을 블록으로 잡고 $labU — 10~30초 뒤 그 자리에서 바뀝니다. 메뉴: 작업 표시줄 ^ 안의 연필 아이콘 우클릭(단축키 변경·로그인·작업 내역)"
    if ($rcEng -ne 0 -or $rcMcp -ne 0 -or $rcKey -ne 0) { Write-Host "  ✗ 일부 단계 실패(엔진=$rcEng, MCP=$rcMcp, 단축키=$rcKey) — 위 ✗ 줄의 안내대로 처리한 뒤 다시 실행"; exit 1 }
    exit 0
}

# 전역 단축키: AutoHotkey v2 + %APPDATA%\imprompt\hotkey.ini(파이썬·서버 경로) + 시작 프로그램 바로가기(로그인 때 자동 실행)
if ($Mode -eq 'hotkey') {
    Write-Host '전역 단축키 (아무 앱에서 문장 블록 → Ctrl+Q, 터미널은 기존 개선기 그대로):'
    $py = Find-Python
    if (-not $py) { Write-Host '  ✗ python 3.8+ 없음 → https://www.python.org 설치 후 다시 실행'; exit 1 }
    $ahk = Find-Ahk
    if (-not $ahk) { Write-Host '  ✗ AutoHotkey v2 없음 → winget install AutoHotkey.AutoHotkey (또는 https://www.autohotkey.com) 후 다시 실행'; exit 1 }
    # python·server 경로는 AutoHotkey 가 cmd.exe 명령줄에 큰따옴표로 박는다 → " % ^ & 와 개행이 있으면 해석되어 다른 명령이 될 수 있어 거부(Git Bash 래퍼의 install.sh 검사와 같은 취지).
    # 바로가기 인자(AutoHotkey·스크립트 경로)는 cmd 를 거치지 않으므로 따옴표와 개행만 거부한다(& ^ 는 허용)
    foreach ($p in @($py, $Srv)) {
        if ($p -match '["%^&\r\n]') { Write-Host "  ✗ 경로에 `" % ^ & 또는 개행이 있어 단축키를 설치하지 않는다: $p — 이 문자가 없는 폴더로 옮긴 뒤 다시 실행"; exit 1 }
    }
    foreach ($p in @($Repo, $ahk)) {
        if ($p -match '["\r\n]') { Write-Host "  ✗ 경로에 `" 또는 개행이 있어 단축키를 설치하지 않는다: $p — 이 문자가 없는 폴더로 옮긴 뒤 다시 실행"; exit 1 }
    }
    $dir = Join-Path $env:APPDATA 'imprompt'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $ini = Join-Path $dir 'hotkey.ini'
    $keep = @()                                                   # 트레이 메뉴에서 바꾼 단축키(hotkey=)는 재설치해도 유지 — 경로만 갱신
    if (Test-Path $ini) { $keep = @(Get-Content -Path $ini | Where-Object { $_ -match '^hotkey=' } | Select-Object -First 1) }
    $hk = Hotkey-FromEnv $py                                      # 설치할 때 고른 단축키가 있으면 그것으로(트레이에서 바꾼 키보다 우선)
    if ($hk) { $keep = @("hotkey=$hk") }
    $engine = Pick-Host $py                                       # 로그인된 엔진 우선(없으면 설치된 첫 엔진)
    Set-Content -Path $ini -Encoding Unicode -Value (@('[imprompt]', "python=$py", "server=$Srv", "host=$engine") + $keep)   # IniRead 는 UTF-16 ini 의 한글 경로도 읽는다
    $script = Join-Path $Repo 'hotkey\imprompt.ahk'
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Imprompt hotkey.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk); $s.TargetPath = $ahk; $s.Arguments = '"' + $script + '"'; $s.WorkingDirectory = (Split-Path $script); $s.Save()
    if (-not (Test-Path $lnk)) { Write-Host "  ✗ 시작 프로그램 바로가기를 만들지 못했습니다: $lnk — 보안 프로그램이 막았을 수 있습니다"; exit 1 }
    $proc = Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '" /ready') -PassThru
    Start-Sleep -Seconds 2
    if (-not $proc -or $proc.HasExited) {                       # 방금 끝난 옛 인스턴스와 겹치면 바로 종료될 수 있다 → 한 번만 다시
        Start-Sleep -Seconds 1
        $proc = Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '" /ready') -PassThru
        Start-Sleep -Seconds 2
    }
    if (-not $proc -or $proc.HasExited) { Write-Host '  ✗ AutoHotkey 가 바로 종료됐습니다 — 보안 프로그램이 AutoHotkey 를 막았을 수 있습니다(예외 등록 후 다시 실행)'; exit 1 }
    # Windows '설치된 앱' 목록에 등록(사용자 범위, 관리자 권한 없음) — 설정 → 앱 → Imprompt → 제거 = install.ps1 remove
    try {
        $ver = (Get-Content -Path (Join-Path $Repo 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
        New-Item -Path $UninstKey -Force | Out-Null
        $props = @{ DisplayName = 'Imprompt'; DisplayVersion = "$ver".Trim(); Publisher = 'Imprompt (github.com/seonoh/Imprompt)'
                    InstallLocation = $Repo; DisplayIcon = (Join-Path $Repo 'hotkey\imprompt.ico')
                    UninstallString = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Repo 'install.ps1')`" remove" }
        foreach ($k in $props.Keys) { Set-ItemProperty -Path $UninstKey -Name $k -Value $props[$k] }
        foreach ($k in @('NoModify', 'NoRepair')) { New-ItemProperty -Path $UninstKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
        Write-Host "  ✓ '설치된 앱' 목록에 등록(지우기: 설정 → 앱 → 설치된 앱 → Imprompt → 제거)"
    } catch { Write-Host "  ! '설치된 앱' 목록 등록 실패(삭제는 트레이 아이콘 → Uninstall Imprompt... 로): $_" }
    Write-Host "  ✓ 설정 $dir\hotkey.ini (엔진 $engine) · 시작 프로그램 바로가기 · 실행 중(AutoHotkey 실행 확인)"
    $cur = if ($keep.Count -gt 0) { Hotkey-Label (($keep[0] -replace '^hotkey=', '').Trim()) } else { 'Ctrl+Q' }
    Write-Host "적용: 아무 앱에서 문장을 블록으로 잡고 $cur (10~30초 뒤 그 자리에서 교체). 단축키 바꾸기: 트레이 연필 아이콘 → Change Hotkey..."
    exit 0
}

Write-Host 'MCP 등록 (imprompt → improve_prompt 도구):'
$py = Find-Python
if (-not $py) { Write-Host '  ✗ python 3.8+ 없음 → https://www.python.org 설치(“Add to PATH” 체크) 후 다시 실행'; exit 1 }
$n = 0
$n += Register 'claude' @('mcp', 'remove', '-s', 'user', 'imprompt') @('mcp', 'add', '-s', 'user', 'imprompt', '--', $py, $Srv, '--host', 'claude')
$n += Register 'codex'  @('mcp', 'remove', 'imprompt') @('mcp', 'add', 'imprompt', '--', $py, $Srv, '--host', 'codex')
# gemini 는 '--' 뒤를 서버 인자로 넘긴다(앞에 두면 --host 를 자기 옵션으로 해석). --trust 는 쓰지 않는다: 호출 확인 창을 우회하는 옵션이라 공개판에서는 gemini 기본(첫 호출 때 확인)을 따른다
$n += Register 'gemini' @('mcp', 'remove', '-s', 'user', 'imprompt') @('mcp', 'add', '-s', 'user', 'imprompt', $py, '--', $Srv, '--host', 'gemini')
if ($n -eq 0) { Write-Host '  ✗ 등록된 CLI 없음 → claude·codex·gemini 중 하나를 설치한 뒤 다시 실행' }
$env:PYTHONIOENCODING = 'utf-8'
if ($env:IMPROMPT_IN_USE -ne '1') {                              # 전체 설치(use)는 로그인 전이라 ✗ 줄이 실패처럼 보인다 → 끝 요약이 실제 상태를 보여 준다
    & $py $Srv --check
    if ($n -gt 0) { Write-Host '적용: CLI 를 새로 열고 "이 요청 improve_prompt 로 개선해줘: …"' }
}
if ($n -gt 0) { exit 0 } else { exit 1 }   # 성공 = 등록된 CLI 가 있음(로그인 여부는 위 --check 안내로, use 가 이어서 로그인 창을 띄운다)

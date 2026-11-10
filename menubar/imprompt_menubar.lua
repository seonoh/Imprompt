-- Imprompt 메뉴바 상태 아이콘(macOS · Hammerspoon).
-- 아이콘: 앱 아이콘(반짝이는 연필, assets/icon)의 단색판 — 연필 + 큰 별·작은 별(템플릿 이미지 → 라이트·다크 메뉴바 자동). 진행 중일 때만 두 별이 번갈아 반짝인다.
-- 로그인은 터미널 창을 띄우지 않는다(백그라운드 실행 → 브라우저 승인만).
-- 클릭: 작업 목록(작업마다 고유 ID 파일 → 병렬 작업이 따로 표시), 사용 중인 agent, 계정 로그인 상태와 로그인·로그아웃.
-- 이벤트 출처: imprompt_mcp.py 가 개선 1건마다 쓰는 ~/.imprompt/jobs/<id>.json(MCP·전역 단축키). 입력창 Ctrl+Q(pi-edit)는 대상 아님.
-- 설치: ./install.sh menubar → ~/.hammerspoon/init.lua 에 start(...) 블록.
local M = {}

local JOB_STALE = 600            -- 이 초보다 오래 running 이면 '응답 없음'(프로세스가 죽었을 때)
local SHOW_JOBS = 8
local STATUS_ICON = { running = "⏳", ok = "✅", fail = "⚠️", cancelled = "⏹", stale = "❔" }
local KIND_LABEL = { cache = "cache", skip = "passthrough", dedup = "deduplicated", engine = "" }
local ENGINES = { "claude", "codex", "gemini" }
-- 로그인: 터미널 창 없이 백그라운드로 실행 → 각 CLI 가 브라우저를 열고 승인을 기다린다(자격증명은 CLI 가 저장). gemini 는 대화형 화면에서만 가능
local LOGIN_CMD = { claude = { "claude", "auth", "login", "--claudeai" }, codex = { "codex", "login" } }
local LOGIN_TIMEOUT = 300
local LOGOUT_CMD = { claude = { "claude", "auth", "logout" }, codex = { "codex", "logout" } }
local STATE_LABEL = { ok = "Signed in", ["no-login"] = "Signed out", missing = "Not installed", unknown = "Checking..." }
-- 사용자에게 보이는 문구(한 곳, ASCII — 전역 단축키 hotkey/* 와 같은 어휘). %s 는 string.format 으로 채운다
local T = {
  tipBusy = "Imprompt - refining (%d)", tipIdle = "Imprompt - idle",
  geminiLogin = "%s sign-in is only available inside %s itself (Login with Google).",
  finishLogin = "Finish %s sign-in in your browser.", loginOk = "%s signed in.", loginFail = "%s sign-in failed: %s",
  noStart = "Could not start %s.", approveLogin = "Approve %s sign-in in your browser.",
  geminiLogout = "gemini has no sign-out command. Run gemini in a terminal and use /auth.",
  logoutTitle = "Sign out of %s?", logoutBody = "This removes the %s CLI credentials on this device. Sign in again to use it.",
  logoutBtn = "Sign Out", cancelBtn = "Cancel", logoutFail = "%s sign-out failed: %s",
  sec = "%ds", min = "%dm", hour = "%dh", elapsed = " elapsed", ago = " ago", took = "%.0fs",
  srcHotkey = "Hotkey", emptyPreview = "(empty)",
  running = "Running: %d", noJobs = "No active jobs",
  agent = "Agent in use: %s (hotkey default)", lastUsed = "  |  Last used: %s",
  accounts = "Accounts", signingIn = "   Signing in... (approve in browser)",
  signOut = "Sign Out...", signIn = "Sign In... (opens browser)", howTo = "How to Sign In",
  refresh = "Refresh Account Status", openJobs = "Open Job History",
  hotkey = "Hotkey: %s", hotkeyChange = "Change Hotkey...", hotkeyReset = "Reset to %s",
  hotkeyMissing = "Hotkey: not installed (run the install line again)",
  customOn = "Custom rules: on (%d chars)", customOff = "Custom rules: off",
  customEdit = "Edit Custom Rules...", customImport = "Import From My Agent Rules...",
  importing = "Reading your agent rules... (up to a minute)", importBusy = "Import already in progress.",
  importFail = "Import failed.", applyTitle = "Apply imported rules?",
  applyBody = "Review the draft that just opened. Apply it to your custom rules? Existing rules are kept.",
  applyBtn = "Apply", applied = "Custom rules updated.",
  editorTitle = "Imprompt - Custom Rules", editorMissing = "The Custom Rules window file is missing. Reinstall Imprompt.",
  delTitle = "Delete the rule \"%s\"?", delBody = "This removes it from your custom rules. You cannot undo this here.",
  delBtn = "Delete", editorFail = "Something went wrong. Please try again.",
  remove = "Uninstall Imprompt...", removeTitle = "Remove Imprompt from this Mac?",
  removeBody = "This turns off the hotkey and menu bar icon and deletes Imprompt, its settings, your custom rules and history. Hammerspoon and your AI app stay.",
  removeBtn = "Uninstall", removed = "Imprompt removed.", removeLeft = "Imprompt removed, but some files could not be deleted. See the details in Hammerspoon Console.",
  removeFail = "Could not start the uninstaller.",
}

local bar, animTimer, pollTimer, watcher, accountTimer
local rulesState = { on = false, chars = 0 }   -- imprompt_mcp.py --rules-status 결과(메뉴 상태 줄용)
local importing = false
local loginTasks = {}      -- 엔진 → 진행 중인 로그인 작업(같은 엔진 중복 실행 방지)
local frame = 0
local jobs = {}
local accounts = {}

-- ---------- 아이콘 ----------
-- 앱 아이콘(반짝이는 연필 — 2026-11-03 채택, assets/icon/imprompt-icon-1024.png)의 메뉴바용 단색판.
-- 연필(지우개·몸통·심)은 늘 또렷하고, 연필 끝 위의 큰 별·작은 별이 반짝임 담당: 대기 = 정지(또렷), 진행 중 = 두 별이 엇갈려 번갈아 반짝(투명도).
-- 검정 채움의 템플릿 이미지라 라이트·다크 메뉴바에서 자동으로 색이 맞는다. 18×18pt, 24프레임(0.1초 간격 → 2.4초에 한 바퀴)
local FRAMES = 24
local function star(cx, cy, r, inner, a)
  local pts = {}
  for i = 0, 7 do
    local ang = a + i * math.pi / 4 - math.pi / 2
    local rr = (i % 2 == 0) and r or r * inner
    pts[#pts + 1] = { x = cx + rr * math.cos(ang), y = cy + rr * math.sin(ang) }
  end
  return pts
end

-- 연필: 오른쪽 위(지우개) → 왼쪽 아래(심) 대각선. 축 위 거리 s0~s1 구간을 반폭 w0→w1 사각(사다리꼴)으로
local PENCIL_A, PENCIL_T, PENCIL_W = { x = 16.2, y = 1.8 }, { x = 4.0, y = 14.0 }, 2.15
local function pencilPart(s0, s1, w0, w1)
  local dx, dy = PENCIL_T.x - PENCIL_A.x, PENCIL_T.y - PENCIL_A.y
  local len = math.sqrt(dx * dx + dy * dy)
  local ux, uy = dx / len, dy / len          -- 축 방향(심 쪽)
  local nx, ny = -uy, ux                     -- 축에 수직
  local function p(s, w) return { x = PENCIL_A.x + ux * s + nx * w, y = PENCIL_A.y + uy * s + ny * w } end
  if w1 == 0 then return { p(s0, w0), p(s0, -w0), p(s1, 0) } end
  return { p(s0, w0), p(s0, -w0), p(s1, -w1), p(s1, w1) }
end
local PENCIL_LEN = math.sqrt((PENCIL_T.x - PENCIL_A.x) ^ 2 + (PENCIL_T.y - PENCIL_A.y) ^ 2)

-- 반짝임 투명도: 최저 MIN_ALPHA — 메뉴바에서 흐린 쪽 별도 윤곽이 보이게(너무 낮추면 아이콘이 사라져 보임)
local MIN_ALPHA = 0.3

local function drawIcon(f)
  local c = hs.canvas.new({ x = 0, y = 0, w = 18, h = 18 })
  local bigAlpha, smallAlpha = 1, 1                   -- 대기: 둘 다 또렷
  if f then
    -- 한 주기(24프레임·2.4초)에 두 번 엇갈림: 큰 별이 밝으면 작은 별은 흐리고, 반대도 마찬가지
    local wave = 0.5 + 0.5 * math.cos(f / FRAMES * 4 * math.pi)
    bigAlpha = MIN_ALPHA + (1 - MIN_ALPHA) * wave
    smallAlpha = MIN_ALPHA + (1 - MIN_ALPHA) * (1 - wave)
  end
  local ink = { white = 0, alpha = 1 }
  local L = PENCIL_LEN
  -- 지우개 | 틈 | 몸통 | 틈 | 깎은 나무+심(끝까지 좁아짐). 틈은 투명 → 실루엣만으로 연필로 읽힌다
  c[1] = { type = "segments", action = "fill", fillColor = ink, closed = true, coordinates = pencilPart(0, 2.8, PENCIL_W, PENCIL_W) }
  c[2] = { type = "segments", action = "fill", fillColor = ink, closed = true, coordinates = pencilPart(3.7, L - 4.6, PENCIL_W, PENCIL_W) }
  c[3] = { type = "segments", action = "fill", fillColor = ink, closed = true, coordinates = pencilPart(L - 3.9, L, PENCIL_W * 0.86, 0) }
  -- 반짝임 두 별: 연필 끝 위쪽 빈자리(연필과 겹치지 않음)
  c[4] = { type = "segments", action = "fill", fillColor = { white = 0, alpha = bigAlpha }, closed = true,
           coordinates = star(4.3, 5.6, 3.2, 0.32, 0) }
  c[5] = { type = "segments", action = "fill", fillColor = { white = 0, alpha = smallAlpha }, closed = true,
           coordinates = star(9.0, 2.4, 1.9, 0.36, 0) }
  local img = c:imageFromCanvas()
  c:delete()
  return img
end

local idleIcon
local animFrames = {}

-- ---------- 작업 읽기 ----------
local function jobsDir() return M.cfg.state .. "/jobs" end

local function pidAlive(pid)
  if not pid then return false end
  return os.execute("kill -0 " .. math.floor(pid) .. " 2>/dev/null") == true
end

local function readJobs()
  local list = {}
  local ok, iter, dirObj = pcall(hs.fs.dir, jobsDir())
  if not ok or not iter then return list end
  for name in iter, dirObj do
    if name:match("%.json$") then
      local j = hs.json.read(jobsDir() .. "/" .. name)
      if type(j) == "table" and j.id then
        if j.status == "running" and ((os.time() - (j.started or 0)) > JOB_STALE or not pidAlive(j.pid)) then
          j.status = "stale"                         -- 프로세스가 사라졌거나 너무 오래 → 진행 중으로 세지 않음
        end
        list[#list + 1] = j
      end
    end
  end
  table.sort(list, function(x, y)
    local xr, yr = x.status == "running", y.status == "running"
    if xr ~= yr then return xr end
    return (x.started or 0) > (y.started or 0)
  end)
  return list
end

local function runningCount()
  local n = 0
  for _, j in ipairs(jobs) do if j.status == "running" then n = n + 1 end end
  return n
end

-- ---------- 아이콘 상태 ----------
local function setAnimating(on)
  if on and not animTimer then
    animTimer = hs.timer.doEvery(0.1, function()
      frame = (frame + 1) % #animFrames
      bar:setIcon(animFrames[frame + 1], true)
    end)
  elseif not on and animTimer then
    animTimer:stop()
    animTimer = nil
    bar:setIcon(idleIcon, true)
  end
end

local function refresh()
  jobs = readJobs()
  local n = runningCount()
  setAnimating(n > 0)
  bar:setTooltip(n > 0 and string.format(T.tipBusy, n) or T.tipIdle)
end

-- 실행 중인 hs.task 를 끝날 때까지 붙잡아 둔다(참조가 없으면 GC 로 콜백이 사라질 수 있음 — hotkey/imprompt.lua 와 같은 이유)
local liveTasks = {}

-- 폴더 열기: 셸 문자열을 조립하지 않고 인자 배열로(경로에 따옴표·$ 가 있어도 해석되지 않음)
local function openFolder(path)
  local t
  t = hs.task.new("/usr/bin/open", function() liveTasks[t] = nil end, { path })
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil end
end

-- ---------- 작업 내역 보고서 ----------
-- "Open Job History": imprompt_mcp.py --jobs-html 이 만든 단일 HTML(~/.imprompt/jobs-report.html)을 기본 브라우저로 연다.
-- 만들지 못하면 예전처럼 기록 폴더를 연다
local function openJobHistory()
  local t
  t = hs.task.new(M.cfg.python, function(code, out)
    liveTasks[t] = nil
    local path = code == 0 and (out or ""):match("[^\n]+") or nil
    if path and hs.fs.attributes(path) then hs.urlevent.openURL("file://" .. path)
    else openFolder(jobsDir()) end
  end, { M.cfg.server, "--jobs-html" })
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil; openFolder(jobsDir()) end
end

-- ---------- 계정 ----------
local function refreshAccounts()
  local t
  t = hs.task.new(M.cfg.python, function(code, out)
    liveTasks[t] = nil
    local parsed = code == 0 and hs.json.decode(out or "") or nil
    if type(parsed) == "table" then accounts = parsed end
  end, { M.cfg.server, "--status-json" })
  local env = t:environment()
  env.PATH = (M.cfg.path or "") .. ":" .. (env.PATH or "")
  t:setEnvironment(env)
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil end
end

-- 로그인 직후 몇 분 동안은 자주 다시 확인(사용자가 브라우저에서 마치면 바로 반영)
local function watchAccountsFor(seconds)
  if accountTimer then accountTimer:stop() end
  local left = seconds
  accountTimer = hs.timer.doEvery(4, function()
    refreshAccounts()
    left = left - 4
    if left <= 0 then accountTimer:stop(); accountTimer = nil end
  end)
end

local function withPath(t)
  local env = t:environment()
  env.PATH = (M.cfg.path or "") .. ":" .. (env.PATH or "")
  t:setEnvironment(env)
  return t
end

local function openLogin(engine)
  local argv = LOGIN_CMD[engine]
  if not argv then
    hs.alert.show(string.format(T.geminiLogin, engine, engine), 5)
    return
  end
  if loginTasks[engine] then
    hs.alert.show(string.format(T.finishLogin, engine), 3)
    return
  end
  local t
  t = withPath(hs.task.new("/usr/bin/env", function(code, _, err)
    loginTasks[engine] = nil
    refreshAccounts()
    if code == 0 then hs.alert.show(string.format(T.loginOk, engine), 2)
    elseif code ~= 15 then hs.alert.show(string.format(T.loginFail, engine, (err or ""):match("[^\n]+") or ""), 5) end
  end, argv))
  if not t:start() then
    hs.alert.show(string.format(T.noStart, engine), 4)
    return
  end
  loginTasks[engine] = t
  hs.alert.show(string.format(T.approveLogin, engine), 4)
  hs.timer.doAfter(LOGIN_TIMEOUT, function()            -- 승인하지 않고 두면 5분 뒤 정리
    if loginTasks[engine] == t then t:terminate() end
  end)
  watchAccountsFor(LOGIN_TIMEOUT)
end

local function logout(engine)
  local argv = LOGOUT_CMD[engine]
  if not argv then
    hs.alert.show(T.geminiLogout, 5)
    return
  end
  local answer = hs.dialog.blockAlert(string.format(T.logoutTitle, engine),
    string.format(T.logoutBody, engine), T.logoutBtn, T.cancelBtn, "warning")
  if answer ~= T.logoutBtn then return end
  local t = withPath(hs.task.new("/usr/bin/env", function(code, _, err)
    if code ~= 0 then hs.alert.show(string.format(T.logoutFail, engine, err or ""), 5) end
    refreshAccounts()
  end, argv))
  t:start()
end

-- ---------- 완전 제거(Uninstall Imprompt...) ----------
-- 확인 창 → install.sh remove(AI_TOOLS_NO_LAUNCH=1: Hammerspoon 을 끄지 않게) → 끝나면 설정을 다시 읽어 단축키·메뉴바가 사라진다
local function removeImprompt()
  local root = M.cfg.server:match("^(.*)/prompt%-improver/mcp/[^/]+$")
  if not root or not hs.fs.attributes(root .. "/install.sh") then hs.alert.show(T.removeFail, 4); return end
  if hs.dialog.blockAlert(T.removeTitle, T.removeBody, T.removeBtn, T.cancelBtn, "warning") ~= T.removeBtn then return end
  local t
  t = withPath(hs.task.new("/bin/bash", function(code, out, err)
    liveTasks[t] = nil
    print("[imprompt remove]\n" .. (out or "") .. (err or ""))
    hs.alert.show(code == 0 and T.removed or T.removeLeft, 5)
    hs.timer.doAfter(1.5, hs.reload)
  end, { root .. "/install.sh", "remove" }))
  local env = t:environment(); env.AI_TOOLS_NO_LAUNCH = "1"; t:setEnvironment(env)
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil; hs.alert.show(T.removeFail, 4) end
end

-- ---------- 사용자 지침 ----------
-- 모든 외부 프로그램은 인자 배열로 부른다(셸 문자열 조립 없음). 편집기 열기는 /usr/bin/open -t (기본 텍스트 편집기)
local function openText(path)
  local t
  t = hs.task.new("/usr/bin/open", function() liveTasks[t] = nil end, { "-t", path })
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil end
end

local function refreshRules()
  local t
  t = withPath(hs.task.new(M.cfg.python, function(code, out)
    liveTasks[t] = nil
    local parsed = code == 0 and hs.json.decode(out or "") or nil
    if type(parsed) == "table" then rulesState = parsed end
  end, { M.cfg.server, "--rules-status" }))
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil end
end

-- "Edit Custom Rules...": 목록 + 이름·내용 칸이 있는 편집 창(hs.webview, menubar/rules-editor.html). 텍스트 편집기는 띄우지 않는다.
--   읽기·쓰기는 모두 imprompt_mcp.py(--rules-items / --rule-put / --rule-del)가 한다 — 검사(빈 이름·같은 이름·글자 수)와 .bak 백업도 그쪽.
--   이름·내용은 명령줄이 아니라 표준 입력으로 넘긴다(디스크에 남지 않게). 페이지는 네트워크·파일 접근이 없다(CSP).
local editor, editorUC

local function firstLine(s) return (s or ""):match("[^\n]+") end

local function runServer(args, cb, input)
  local argv = { M.cfg.server }
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  local t
  t = withPath(hs.task.new(M.cfg.python, function(code, out, err)
    liveTasks[t] = nil
    cb(code, out or "", err or "")
  end, argv))
  if input then t:setInput(input) end                          -- 표준 입력으로(파일을 만들지 않는다 — 단축키 실행과 같은 방식)
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil; cb(-1, "", "") end
end

local function editorJS(fn, a, b)
  if editor then editor:evaluateJavaScript("App." .. fn .. "(" .. a .. (b and ("," .. b) or "") .. ")") end
end

local function editorLoad(opt)
  runServer({ "--rules-items" }, function(code, out)
    local data = (code == 0 and hs.json.decode(out)) and out or '{"items":[],"chars":0,"limit":2000}'
    editorJS("load", data, hs.json.encode(opt or {}))
    refreshRules()
  end)
end

local function editorWrite(lines, flag, okSelect)
  -- 이름·내용은 표준 입력으로 넘긴다(예전엔 ~/.imprompt 안 임시 파일 — Hammerspoon 의 umask 로 644 가 될 수 있었다)
  runServer({ flag, "--stdin" }, function(code, out, err)
    if code == 0 then editorLoad({ msg = firstLine(out), ok = true, select = okSelect })
    else editorJS("error", hs.json.encode({ msg = firstLine(err) or T.editorFail })) end
  end, table.concat(lines, "\n"))
end

local function onEditorMessage(m)
  local b = type(m) == "table" and m.body or nil
  if type(b) ~= "table" then return end
  local s = function(v) return type(v) == "string" and v or "" end
  if b.op == "ready" then editorLoad()
  elseif b.op == "put" then editorWrite({ s(b.name), s(b.old), s(b.body) }, "--rule-put", s(b.name))
  elseif b.op == "del" then
    local name = s(b.name)
    if hs.dialog.blockAlert(string.format(T.delTitle, name), T.delBody, T.delBtn, T.cancelBtn, "warning") == T.delBtn then
      editorWrite({ name }, "--rule-del", nil)
    else
      editorJS("unlock", "")
    end
  elseif b.op == "close" and editor then editor:delete(); editor = nil end
end

local function editRules()
  if editor then hs.focus(); editor:show():bringToFront(true); return end   -- 이미 열린 창: 다시 읽지 않는다(고치던 내용 보존)
  local root = M.cfg.server:match("^(.*)/prompt%-improver/mcp/[^/]+$")
  local fh = root and io.open(root .. "/menubar/rules-editor.html", "r")
  if not fh then hs.alert.show(T.editorMissing, 5); return end
  local html = fh:read("*a")
  fh:close()
  editorUC = hs.webview.usercontent.new("imprompt"):setCallback(onEditorMessage)
  local scr = hs.screen.mainScreen():frame()
  local w, h = 760, 500
  editor = hs.webview.new({ x = scr.x + (scr.w - w) / 2, y = scr.y + (scr.h - h) / 3, w = w, h = h }, { developerExtrasEnabled = false }, editorUC)
  -- 제목 표시줄 닫기 없음: 웹뷰는 닫힘을 취소할 수 없어, 저장 안 한 변경을 묻는 화면 안 Close 로만 닫는다
  editor:windowStyle({ "titled", "resizable" }):windowTitle(T.editorTitle):allowTextEntry(true)
    :allowNewWindows(false):closeOnEscape(false):deleteOnClose(true)
    :windowCallback(function(action) if action == "closing" then editor = nil end end)
  editor:html(html)
  hs.focus()
  editor:show():bringToFront(true)
end

-- "Import From My Agent Rules...": 초안 생성(--import-rules) → 편집기로 열기 → 적용 확인 대화상자 → --import-rules --apply
local function applyImport()
  local t
  t = withPath(hs.task.new(M.cfg.python, function(code, out, err)
    liveTasks[t] = nil
    refreshRules()
    if code == 0 then hs.alert.show(T.applied, 3)
    else hs.alert.show((err or ""):match("[^\n]+") or T.importFail, 5) end
  end, { M.cfg.server, "--import-rules", "--apply" }))
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil end
end

local function importRules()
  if importing then hs.alert.show(T.importBusy, 3); return end
  importing = true
  hs.alert.show(T.importing, 3)
  local t
  t = withPath(hs.task.new(M.cfg.python, function(code, out, err)
    liveTasks[t] = nil
    importing = false
    local path = code == 0 and (out or ""):match("[^\n]+") or nil
    if not path then
      hs.alert.show((err or ""):match("[^\n]+") or T.importFail, 6)
      return
    end
    openText(path)
    if hs.dialog.blockAlert(T.applyTitle, T.applyBody, T.applyBtn, T.cancelBtn, "informational") == T.applyBtn then applyImport() end
  end, { M.cfg.server, "--import-rules", "--host", M.cfg.host }))
  liveTasks[t] = true
  if not t:start() then liveTasks[t] = nil; importing = false end
end

-- ---------- 메뉴(클릭할 때마다 새로 만듦) ----------
local function ago(ts)
  if not ts then return "" end
  local s = math.max(0, os.time() - ts)
  if s < 60 then return string.format(T.sec, math.floor(s)) end
  if s < 3600 then return string.format(T.min, math.floor(s / 60)) end
  return string.format(T.hour, math.floor(s / 3600))
end

local function jobLine(j)
  local icon = STATUS_ICON[j.status] or "•"
  local how
  if j.status == "running" then
    how = (j.engine ~= "" and j.engine or j.host) .. " · " .. ago(j.started) .. T.elapsed
  else
    local kind = KIND_LABEL[j.kind or ""] or ""
    local took = j.ended and j.started and string.format(T.took, j.ended - j.started) or ""
    how = (j.engine ~= "" and j.engine or (kind ~= "" and kind or j.host)) .. (kind ~= "" and j.engine ~= "" and (" · " .. kind) or "")
          .. (took ~= "" and (" · " .. took) or "") .. " · " .. ago(j.ended or j.started) .. T.ago
  end
  local src = j.source == "mcp" and "MCP" or T.srcHotkey
  local preview = (j.preview ~= "" and j.preview or T.emptyPreview)
  return string.format("%s  %s  —  %s · %s", icon, preview, src, how)
end

local function lastEngine()
  for _, j in ipairs(jobs) do if j.engine and j.engine ~= "" then return j.engine end end
  return nil
end

local function buildMenu()
  refresh()
  refreshRules()
  refreshAccounts()                                  -- 열 때마다 다시 확인(비동기 — 바깥에서 로그인·로그아웃한 것도 곧 반영)
  local items = {}
  local n = runningCount()
  items[#items + 1] = { title = n > 0 and string.format(T.running, n) or T.noJobs, disabled = true }
  local shown = 0
  for _, j in ipairs(jobs) do
    if shown >= SHOW_JOBS then break end
    items[#items + 1] = { title = jobLine(j), disabled = true }
    shown = shown + 1
  end
  items[#items + 1] = { title = "-" }
  local last = lastEngine()
  items[#items + 1] = { title = string.format(T.agent, M.cfg.host) .. (last and string.format(T.lastUsed, last) or ""), disabled = true }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = T.accounts, disabled = true }
  for _, e in ipairs(ENGINES) do
    local st = accounts[e] or "unknown"
    local item = { title = string.format("%s   %s %s", e, st == "ok" and "●" or "○", STATE_LABEL[st] or st) }
    if loginTasks[e] then
      item.title = e .. T.signingIn
      item.disabled = true
    elseif st == "ok" then
      item.menu = { { title = T.signOut, fn = function() logout(e) end } }
    elseif st == "no-login" then
      item.menu = { { title = LOGIN_CMD[e] and T.signIn or T.howTo, fn = function() openLogin(e) end } }
    else
      item.disabled = true
    end
    items[#items + 1] = item
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = T.refresh, fn = refreshAccounts }
  items[#items + 1] = { title = T.openJobs, fn = openJobHistory }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = rulesState.on and string.format(T.customOn, rulesState.chars or 0) or T.customOff, disabled = true }
  items[#items + 1] = { title = T.customEdit, fn = editRules }
  items[#items + 1] = { title = T.customImport, fn = importRules }
  -- 단축키 설정(keymap): 전역 단축키 모듈(hotkey/imprompt.lua, 같은 Hammerspoon 안)이 있으면 현재 키 표시·바꾸기·기본값
  local okHk, hkmod = pcall(require, "imprompt")
  if okHk and type(hkmod) == "table" and hkmod.cfg and hkmod.setHotkey then
    local sub = { { title = T.hotkeyChange, fn = function() hkmod.captureHotkey() end } }
    if hkmod.hotkeyLabel() ~= hkmod.defaultLabel() then
      sub[#sub + 1] = { title = string.format(T.hotkeyReset, hkmod.defaultLabel()), fn = function() hkmod.resetHotkey() end }
    end
    items[#items + 1] = { title = string.format(T.hotkey, hkmod.hotkeyLabel()), menu = sub }
  else
    items[#items + 1] = { title = T.hotkeyMissing, disabled = true }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = T.remove, fn = removeImprompt }
  return items
end

-- cfg: python, server(필수) · state(~/.imprompt) · host("claude") · path(셸 PATH)
function M.start(cfg)
  M.cfg = cfg or {}
  M.cfg.state = M.cfg.state or (os.getenv("HOME") .. "/.imprompt")
  M.cfg.host = M.cfg.host or "claude"
  hs.fs.mkdir(M.cfg.state)
  hs.fs.mkdir(jobsDir())
  idleIcon = drawIcon(nil)
  animFrames = {}
  for f = 0, FRAMES - 1 do animFrames[#animFrames + 1] = drawIcon(f) end
  if bar then bar:delete() end
  bar = hs.menubar.new(true, "imprompt")
  bar:setIcon(idleIcon, true)
  bar:setMenu(buildMenu)
  if watcher then watcher:stop() end
  watcher = hs.pathwatcher.new(jobsDir(), refresh):start()   -- 작업 파일이 바뀌는 즉시 아이콘 갱신
  if pollTimer then pollTimer:stop() end
  pollTimer = hs.timer.doEvery(2, refresh)                   -- 감시가 놓친 변화·죽은 프로세스 정리용
  refresh()
  refreshAccounts()
  refreshRules()
  if M.accountPoll then M.accountPoll:stop() end
  M.accountPoll = hs.timer.doEvery(15, refreshAccounts)       -- 토큰 0 상태 명령. CLI 에서 직접 로그인·로그아웃해도 15초 안에 반영
  return M
end

-- 시험·점검용: 지금 메뉴에 뜰 줄들(읽기 전용)
function M.menuTitles()
  local out = {}
  for _, it in ipairs(buildMenu()) do
    out[#out + 1] = it.title .. (it.menu and ("  ▸ " .. it.menu[1].title) or "")
  end
  return table.concat(out, "\n")
end

-- 디자인 확인용: 대기 1장 + 진행 프레임 n장을 PNG 로 저장(4배 크기)
function M.saveFrames(dir, n)
  hs.fs.mkdir(dir)
  local function save(img, name) img:setSize({ w = 72, h = 72 }):saveToFile(dir .. "/" .. name .. ".png") end
  save(drawIcon(nil), "idle")
  for k = 0, (n or 6) - 1 do save(drawIcon(math.floor(k * FRAMES / (n or 6))), string.format("run%02d", k)) end
end

-- 시험·점검용 상태(읽기 전용)
function M.state()
  return { running = runningCount(), animating = animTimer ~= nil, jobs = #jobs, accounts = accounts }
end

return M

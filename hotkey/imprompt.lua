-- Imprompt 전역 단축키(macOS · Hammerspoon): 아무 앱에서 문장을 블록으로 잡고 Ctrl+Q → 그 자리에서 개선본으로 교체.
-- 엔진은 MCP 서버의 단독 실행 모드(imprompt_mcp.py --improve) — 같은 규칙·캐시·폴백, API 키 없음(로그인된 claude·codex 구독).
-- 터미널·IDE(VS Code·Cursor·JetBrains 등 내장 터미널)에서는 Ctrl+Q 를 그대로 넘겨 기존 입력창 개선기(pi-edit)가 동작하게 한다.
-- 설치: ./install.sh hotkey  → ~/.hammerspoon/init.lua 에 아래 start(...) 블록을 넣는다(파이썬·서버 경로·셸 PATH 기록).
-- 안전장치: 선택이 없으면 아무것도 안 바꿈 · 실패하면 원문·클립보드 그대로 · 개선 중 다른 창으로 옮기면 붙여넣지 않고 클립보드에만 둠
--           · 끝나면 원래 클립보드 복원 · 동시에 두 번 누르면 무시.
local M = {}

-- 터미널(번들 ID): 여기서는 단축키를 앱에 그대로 넘긴다. cfg.passthrough 로 더할 수 있다
local TERMINALS = {
  ["com.apple.Terminal"] = true, ["com.googlecode.iterm2"] = true, ["com.mitchellh.ghostty"] = true,
  ["dev.warp.Warp-Stable"] = true, ["com.github.wez.wezterm"] = true, ["net.kovidgoyal.kitty"] = true,
  ["org.alacritty"] = true, ["co.zeit.hyper"] = true, ["com.raphaelamorim.rio"] = true,
  -- 내장 터미널이 있는 IDE: 그 안의 Claude Code·Codex 입력창 개선기(Ctrl+Q)를 쓰도록 그대로 넘긴다
  ["com.microsoft.VSCode"] = true, ["com.microsoft.VSCodeInsiders"] = true, ["com.todesktop.230313mzl4w4u92"] = true,
  ["com.exafunction.windsurf"] = true,
  ["org.tabby"] = true, ["com.termius-dmg.mac"] = true, ["dev.commandline.waveterm"] = true,
  ["dev.zed.Zed"] = true, ["dev.zed.Zed-Preview"] = true,
}
local function isTerminal(bid)
  return TERMINALS[bid] or bid:find("^com%.jetbrains%.") ~= nil   -- IntelliJ·PyCharm 등 JetBrains IDE
end
-- 목록에 없어도 번들 ID 에 term·shell·console 이 들어가면 터미널일 가능성이 높다 → 개선은 하되 붙여넣지 않고 클립보드에만 둔다
-- (셸에 붙여넣기는 줄바꿈이 있으면 명령이 바로 실행될 수 있다)
local function looksTerminal(bid)
  local l = bid:lower()
  return l:find("term", 1, true) ~= nil or l:find("shell", 1, true) ~= nil or l:find("console", 1, true) ~= nil
end

local busy = false
local hk
-- 실행 중인 타이머·작업을 붙잡아 둔다: Hammerspoon 은 참조가 없는 hs.timer·hs.task 를 GC 로 지울 수 있어
-- (그러면 클립보드 복원·잠금 해제·패널 닫기 콜백이 오지 않는다) 끝날 때까지 여기 두고, 콜백에서 놓는다
local live = {}
local function after(sec, fn)
  local t
  t = hs.timer.doAfter(sec, function() live[t] = nil; fn() end)
  live[t] = true
  return t
end

-- 사용자에게 보이는 문구(세 플랫폼 공통 — imprompt.ahk·imprompt-linux.sh 와 같은 글). Windows 콘솔·ahk 인코딩 때문에 ASCII 만
local MSG = {
  progress = "Refining prompt... (10-30s, keep this window focused)",
  hudTitle = "Refining prompt...",
  hudSub = "Keep this window focused. Usually 10-30s.",
  done = "Prompt refined.",
  failed = "Refinement failed: %s. Original text kept.",
  cancelled = "Paste cancelled: window changed. Refined prompt is on the clipboard (Cmd+V).",
  clipOnly = "Looks like a terminal: not pasted. Refined prompt is on the clipboard (Cmd+V).",
  busy = "Refinement already in progress.",
  noSelection = "Select the text to refine first.",
  empty = "Selected text is empty.",
  unknown = "unknown error",
  noStart = "could not start %s",
  keyPrompt = "Press the new shortcut (Esc to cancel)",
  keySet = "Hotkey set to %s.",
  keyKept = "Hotkey unchanged (%s): %s",
  keyCancelled = "Hotkey change cancelled.",
  keyNeedMod = "add Cmd, Ctrl or Option",
  keyReserved = "%s is a common app shortcut",
  keySystem = "%s is used by macOS",
  keyTaken = "%s is taken by another app",
  keySaveFail = "could not save the setting",
  keyStoredBad = "Saved hotkey %s could not be used, back to %s.",
  axAsk = "Imprompt: please allow Hammerspoon.\nIn the macOS window, click 'Open System Settings' and turn on Hammerspoon.\n(needed to copy and paste the selected text)",
  axDone = "Imprompt is ready. Select text in any app and press %s.",
  axTitle = "Imprompt needs one permission",
  axInfo = "Click Open Settings, then turn on Hammerspoon. That's all.",
  axOpen = "Open Settings",
  axLater = "Later",
}

-- 클립보드 기록 방지 표식(nspasteboard.org 관례): 클립보드 관리자(Maccy·Alfred·Paste 등)가 이 내용을 기록에 남기지 않게 한다.
-- 사용자의 프롬프트(비밀이 섞일 수 있음)가 기록 도구에 평문으로 쌓이는 것을 줄이는 완화책 — 표식을 무시하는 도구는 막지 못한다.
local PB_HIDE = { ["org.nspasteboard.TransientType"] = "1", ["org.nspasteboard.ConcealedType"] = "1" }
local function hiddenCopy(data)
  local t = {}
  for k, v in pairs(data or {}) do t[k] = v end
  for k, v in pairs(PB_HIDE) do t[k] = v end
  return t
end
local function putText(s)                                          -- 붙여넣기용으로 클립보드에 넣을 글(개선본)
  hs.pasteboard.writeAllData({ ["public.utf8-plain-text"] = s, ["org.nspasteboard.TransientType"] = "1", ["org.nspasteboard.ConcealedType"] = "1" })
end
local function restore(saved)
  if saved and next(saved) then hs.pasteboard.writeAllData(hiddenCopy(saved)) else hs.pasteboard.clearContents() end
end

-- 실패 원인 한 구절: 개선기(stderr) 첫 줄 "Refinement failed: <원인>. …" 에서 <원인>만, 형식이 다르면 첫 줄 그대로
local function reason(err)
  local line = (err or ""):match("[^\n]+") or ""
  line = line:gsub("^Refinement failed:%s*", ""):gsub("%.%s*Original text kept%.?$", ""):gsub("%.$", "")
  return line ~= "" and line or MSG.unknown
end

local function passthrough()
  hk:disable()
  hs.eventtap.keyStroke(M.cfg.mods, M.cfg.key, 0)                -- 지금 단축키 그대로(메뉴에서 바꿨으면 바뀐 키)
  hk:enable()
end

-- ---------- 진행 패널(HUD) ----------
-- 개선 중임을 알 수 있게 화면 중앙에 작은 패널: 연필 애니메이션(pi-anim.pl 과 같은 이야기 — ✎ 가 초안 ∿ 를 쓰고
-- 되돌아오며 ‿⁀ 로 다듬은 뒤 ✦) + 문구 + 경과 초. 칸마다 글자 요소를 고정 위치에 두어 글꼴 대체로 폭이 달라도 흔들리지 않는다.
-- 클릭은 통과(아래 창 조작을 막지 않음), 80ms 갱신(글자·색만 바꿈), 끝나면 stop() 으로 즉시 제거.
local HUD = { W = 10, EASE = 12, HOLD = 4, CELL = 18, FPS = 0.08 }
local PEN, DRAFT, SPARK, NEAT = "\u{270E}", "\u{223F}", "\u{2726}", { "\u{203F}", "\u{2040}" }
local C_PEN, C_DRAFT, C_SPARK = { hex = "#FFD60A" }, { hex = "#6F8F8F" }, { hex = "#FFFFFF" }
local C_NEAT = { { hex = "#2EC4B6" }, { hex = "#22B8C9" }, { hex = "#3AA8D8" }, { hex = "#5B97E3" }, { hex = "#7A86EA" },
                 { hex = "#8F7AEE" }, { hex = "#A070EE" }, { hex = "#AE68EC" }, { hex = "#B962E8" }, { hex = "#C25DE3" } }
local hudFrames
local function buildHudFrames()
  local W, E = HUD.W, HUD.EASE
  local function ease(t) return math.floor((W - 1) * (1 - math.cos(math.pi * t)) / 2 + 0.5) end
  local frames = {}
  for f = 0, 2 * E + HUD.HOLD - 1 do
    local c = {}
    for i = 1, W do c[i] = { "", C_DRAFT } end
    if f < E then                                              -- 쓱: 왼→오, 지나간 자리에 초안
      local p = ease(f / (E - 1))
      for i = 0, p - 1 do c[i + 1] = { DRAFT, C_DRAFT } end
      c[p + 1] = { PEN, C_PEN }
    elseif f < 2 * E then                                      -- 싹: 오→왼, 지나간 자리는 다듬은 줄
      local p = (W - 1) - ease((f - E) / (E - 1))
      for i = 0, p - 1 do c[i + 1] = { DRAFT, C_DRAFT } end
      for i = p + 1, W - 1 do c[i + 1] = { NEAT[i % 2 + 1], C_NEAT[i + 1] } end
      c[p + 1] = { PEN, C_PEN }
      if f <= E + 1 then c[W] = { SPARK, C_SPARK } end         -- 돌아서는 순간 끝에서 반짝
    else                                                       -- 완성: 다듬은 줄 + 연필 끝 반짝
      for i = 1, W - 1 do c[i + 1] = { NEAT[i % 2 + 1], C_NEAT[i + 1] } end
      c[1] = ((f - 2 * E) % 2 == 1) and { PEN, C_PEN } or { SPARK, C_SPARK }
    end
    frames[#frames + 1] = c
  end
  return frames
end

local function progressHud(title, sub)
  hudFrames = hudFrames or buildHudFrames()
  local scr = hs.screen.mainScreen():frame()
  local w, h = 540, 74
  local cv = hs.canvas.new({ x = scr.x + (scr.w - w) / 2, y = scr.y + scr.h * 0.40, w = w, h = h })
  cv:level(hs.canvas.windowLevels.overlay)
  cv:behavior({ "canJoinAllSpaces", "stationary" })            -- 어느 데스크탑에서든 보이게
  cv:clickActivating(false)
  cv[1] = { type = "rectangle", action = "strokeAndFill", roundedRectRadii = { xRadius = 16, yRadius = 16 },
            frame = { x = 1, y = 1, w = w - 2, h = h - 2 },
            fillColor = { red = 0.09, green = 0.10, blue = 0.12, alpha = 0.97 },
            strokeColor = { hex = "#2EC4B6", alpha = 0.75 }, strokeWidth = 1.5,
            withShadow = true, shadow = { blurRadius = 12, color = { alpha = 0.5 }, offset = { h = -3, w = 0 } } }
  local x0 = 20
  for i = 1, HUD.W do                                          -- 연필 트랙: 칸마다 고정 위치(글꼴 대체로 폭이 달라도 흔들림 없음)
    cv[1 + i] = { type = "text", text = "", textSize = 22, textFont = "Menlo", textAlignment = "center",
                  frame = { x = x0 + (i - 1) * HUD.CELL - 4, y = 20, w = HUD.CELL + 8, h = 34 } }
  end
  local tx = x0 + HUD.W * HUD.CELL + 16
  cv[HUD.W + 2] = { type = "text", text = title, textSize = 16, textColor = { white = 1 },
                    textFont = ".AppleSystemUIFontBold", frame = { x = tx, y = 15, w = w - tx - 64, h = 22 } }
  cv[HUD.W + 3] = { type = "text", text = sub, textSize = 12, textColor = { white = 1, alpha = 0.6 },
                    frame = { x = tx, y = 39, w = w - tx - 64, h = 18 } }
  cv[HUD.W + 4] = { type = "text", text = "0s", textSize = 15, textColor = { hex = "#2EC4B6" }, textAlignment = "right",
                    textFont = "Menlo", frame = { x = w - 70, y = 25, w = 52, h = 22 } }
  local t0, i, shown = hs.timer.secondsSinceEpoch(), 0, -1
  local function draw()
    local fr = hudFrames[i % #hudFrames + 1]
    for k = 1, HUD.W do cv[1 + k].text = fr[k][1]; cv[1 + k].textColor = fr[k][2] end
    local sec = math.floor(hs.timer.secondsSinceEpoch() - t0)
    if sec ~= shown then cv[HUD.W + 4].text = sec .. "s"; shown = sec end
    i = i + 1
  end
  draw(); cv:show()
  local timer = hs.timer.doEvery(HUD.FPS, draw)
  local self = {}
  function self.snapshot(path) if cv then cv:imageFromCanvas():saveToFile(path) end end
  function self.stop()
    if timer then timer:stop(); timer = nil end
    if cv then cv:delete(); cv = nil end
  end
  return self
end

-- 개선 실행(비동기): 선택 복사 → --improve → 같은 창이면 붙여넣기
-- busy 는 trigger 에서 키를 누르는 즉시 켜고, 여기서 결과 처리·클립보드 복원이 모두 끝난 뒤에 끈다(연타로 두 작업이 겹쳐 붙여넣지 않게)
local function run(text, saved, winId, clipOnly)
  local ok, hud = pcall(progressHud, MSG.hudTitle, MSG.hudSub)   -- 패널을 못 만들면(화면 없음 등) 예전 알림으로
  if not ok then
    local note = hs.alert.show(MSG.progress, 120)
    hud = { stop = function() hs.alert.closeSpecific(note) end }
  end
  local task
  task = hs.task.new(M.cfg.python, function(code, out, err)
    live[task] = nil
    hud.stop()
    if code ~= 0 or not out or out == "" then
      restore(saved)
      busy = false
      hs.alert.show(string.format(MSG.failed, reason(err)), 6)
      return
    end
    local cur = hs.window.focusedWindow()
    if not cur or cur:id() ~= winId then
      putText(out)
      busy = false
      hs.alert.show(MSG.cancelled, 5)
      return
    end
    putText(out)
    if clipOnly then
      busy = false
      hs.alert.show(MSG.clipOnly, 5)
      return
    end
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    after(0.6, function()                                -- 붙여넣기가 클립보드를 읽은 뒤 원래 내용으로, 그다음에야 잠금 해제
      restore(saved)
      busy = false
    end)
    hs.alert.show(MSG.done, 1.5)
  end, { M.cfg.server, "--improve", "--host", M.cfg.host })    -- --in 없음 = 엔진이 stdin 에서 읽는다(공용 /tmp 에 선택 텍스트를 쓰지 않음)
  task:setInput(text)
  local env = task:environment()
  env.IMPROMPT_PATH = M.cfg.path or ""                       -- GUI 앱은 PATH 가 짧다 → 설치 때 저장한 셸 PATH
  task:setEnvironment(env)
  if task:start() then live[task] = true else
    hud.stop()
    restore(saved)
    busy = false
    hs.alert.show(string.format(MSG.failed, string.format(MSG.noStart, tostring(M.cfg.python))), 6)
  end
end

local axTimer, axNote                                          -- 손쉬운 사용 안내 상태(M.askAccessibility 가 관리, trigger 도 본다)
function M.trigger()
  local app = hs.application.frontmostApplication()
  local bid = app and app:bundleID() or ""
  if isTerminal(bid) or M.cfg.passthrough[bid] then return passthrough() end
  if busy then
    hs.alert.show(MSG.busy, 1.5)
    return
  end
  -- 손쉬운 사용 권한이 없으면 Cmd+C 가 앱에 전달되지 않아 '선택하세요'로 잘못 안내된다 → 권한 안내(허용 창·Open Settings)를 다시 띄운다
  if not hs.accessibilityState() then
    if axTimer then hs.alert.show(MSG.axAsk, 3) else M.askAccessibility() end
    return
  end
  busy = true                                                  -- 복사 대기 중의 연타도 막는다
  local win = hs.window.focusedWindow()
  local winId = win and win:id()
  local saved = hs.pasteboard.readAllData()
  local before = hs.pasteboard.changeCount()
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  local tries, w = 0, nil
  w = hs.timer.waitUntil(function()
    tries = tries + 1
    return hs.pasteboard.changeCount() ~= before or tries >= 15   -- 최대 0.75초 복사 대기
  end, function()
    live[w] = nil
    if hs.pasteboard.changeCount() == before then
      busy = false
      hs.alert.show(MSG.noSelection, 2)
      return
    end
    local text = hs.pasteboard.getContents() or ""
    if text:match("^%s*$") then
      restore(saved)
      busy = false
      hs.alert.show(MSG.empty, 2)
      return
    end
    run(text, saved, winId, looksTerminal(bid))
  end, 0.05)
  live[w] = true
end

-- ---------- 단축키 설정 ----------
-- 사용자별 저장: ~/.imprompt/settings.json {"hotkey":{"mods":["ctrl"],"key":"q"}} — 메뉴바 아이콘 메뉴(imprompt_menubar.lua)가 바꾼다.
-- (config/keybindings.json 은 Claude Code 입력창 Ctrl+Q 용 파일이라 쓰지 않는다)
-- 바꾸기 = 검사(수식키 필요·흔한 앱 단축키·macOS 시스템 단축키) → 새 키 등록 시도 → 저장 → 성공하면 옛 키 해제. 어느 단계든 실패하면 옛 키 그대로.
local SETTINGS = os.getenv("HOME") .. "/.imprompt/settings.json"
local MOD_ORDER = { "ctrl", "alt", "shift", "cmd" }
local MOD_SYMBOL = { ctrl = "⌃", alt = "⌥", shift = "⇧", cmd = "⌘" }
local RESERVED = { ["cmd+q"] = 1, ["cmd+w"] = 1, ["cmd+c"] = 1, ["cmd+v"] = 1, ["cmd+x"] = 1, ["cmd+a"] = 1, ["cmd+z"] = 1,
                   ["cmd+s"] = 1, ["cmd+tab"] = 1, ["cmd+space"] = 1, ["cmd+h"] = 1, ["cmd+m"] = 1, ["cmd+n"] = 1, ["cmd+t"] = 1,
                   ["cmd+f"] = 1, ["cmd+p"] = 1, ["cmd+o"] = 1, ["shift+cmd+z"] = 1 }

local function normMods(mods)
  local set, out = {}, {}
  for _, m in ipairs(mods or {}) do
    m = ({ control = "ctrl", option = "alt", opt = "alt", command = "cmd" })[m] or m
    set[m] = true
  end
  for _, m in ipairs(MOD_ORDER) do if set[m] then out[#out + 1] = m end end
  return out
end
local function comboId(mods, key) return table.concat(normMods(mods), "+") .. (#normMods(mods) > 0 and "+" or "") .. key end
function M.hotkeyLabel(mods, key)
  mods, key = mods or M.cfg.mods, key or M.cfg.key
  local s = ""
  for _, m in ipairs(normMods(mods)) do s = s .. MOD_SYMBOL[m] end
  return s .. (#key == 1 and key:upper() or key:sub(1, 1):upper() .. key:sub(2))
end

-- 무효면 이유 한 구절, 괜찮으면 nil
local function invalidReason(mods, key)
  local nm, real = normMods(mods), false
  for _, m in ipairs(nm) do if m ~= "shift" then real = true end end
  if not key or key == "" or not real then return MSG.keyNeedMod end
  local id = comboId(nm, key)
  if RESERVED[id] then return string.format(MSG.keyReserved, M.hotkeyLabel(nm, key)) end
  if hs.hotkey.systemAssigned(nm, key) then return string.format(MSG.keySystem, M.hotkeyLabel(nm, key)) end
  return nil
end

local function readSettings()
  local f = io.open(SETTINGS, "r"); if not f then return {} end
  local ok, t = pcall(hs.json.decode, f:read("*a")); f:close()
  return (ok and type(t) == "table") and t or {}
end
local function writeSettings(t)
  hs.fs.mkdir(os.getenv("HOME") .. "/.imprompt")
  local tmp = SETTINGS .. ".tmp"
  local f = io.open(tmp, "w"); if not f then return false end
  local ok = f:write(hs.json.encode(t, true)); f:close()
  if not ok then os.remove(tmp); return false end
  return os.rename(tmp, SETTINGS) and true or false             -- 원자적 교체: 반쪽 파일이 남지 않게
end

-- 단축키 바꾸기: (true) 또는 (false, 이유). 실패하면 기존 단축키·설정 그대로
function M.setHotkey(mods, key, persist)
  mods, key = normMods(mods), key and key:lower() or key
  local bad = invalidReason(mods, key)
  if bad then return false, bad end
  if comboId(mods, key) == comboId(M.cfg.mods, M.cfg.key) and hk then return true end
  local new = hs.hotkey.new(mods, key, M.trigger)
  if not (new and new:enable()) then
    if new then new:delete() end
    return false, string.format(MSG.keyTaken, M.hotkeyLabel(mods, key))
  end
  if persist ~= false then
    local t = readSettings(); t.hotkey = { mods = mods, key = key }
    if not writeSettings(t) then new:delete(); return false, MSG.keySaveFail end
  end
  if hk then hk:delete() end
  hk, M.cfg.mods, M.cfg.key = new, mods, key
  return true
end

-- 다음에 누르는 키 조합을 새 단축키로(메뉴에서 부름). Esc = 취소, 10초 무입력 = 취소
local capture
function M.captureHotkey(done)
  if capture then capture:stop() end
  local note = hs.alert.show(MSG.keyPrompt, 10)
  local function finish(msg)
    if capture then capture:stop(); live[capture] = nil; capture = nil end
    hs.alert.closeSpecific(note)
    hs.alert.show(msg, 3)
    if done then done() end
  end
  capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    local key = hs.keycodes.map[e:getKeyCode()]
    if key == "escape" then finish(MSG.keyCancelled); return true end
    local f, mods = e:getFlags(), {}
    for _, m in ipairs(MOD_ORDER) do if f[m] then mods[#mods + 1] = m end end
    local before = M.hotkeyLabel()
    local ok, why = M.setHotkey(mods, key)
    finish(ok and string.format(MSG.keySet, M.hotkeyLabel()) or string.format(MSG.keyKept, before, why))
    return true                                                -- 이 키는 앱으로 보내지 않는다
  end)
  live[capture] = true
  capture:start()
  after(10, function() if capture then finish(MSG.keyCancelled) end end)
end

function M.resetHotkey()
  local ok, why = M.setHotkey(M.cfg.defaultMods, M.cfg.defaultKey)
  hs.alert.show(ok and string.format(MSG.keySet, M.hotkeyLabel()) or string.format(MSG.keyKept, M.hotkeyLabel(), why), 3)
end
function M.defaultLabel() return M.hotkeyLabel(M.cfg.defaultMods, M.cfg.defaultKey) end

-- 처음 한 번: 손쉬운 사용(macOS 27 '기기 제어 및 데이터 접근') 권한이 없으면 macOS 허용 창을 띄우고(이때 Hammerspoon 이 설정 목록에 올라간다),
-- 화면 가운데에 짧은 안내를 함께 띄운다. 8초 뒤에도 허용되지 않았으면(창을 닫았거나 예전에 거절해 시스템 창이 다시 안 뜨는 경우)
-- 'Open Settings' 버튼이 있는 팝업을 띄운다 — 누르면 그 설정 화면이 바로 열려 Hammerspoon 스위치만 켜면 된다.
-- 허용되면(2초마다 확인, 최대 15분) 안내를 닫고 '준비됨'을 알린다 — 그 뒤로 할 일은 없다(다시 시작·재실행 불필요). 이미 허용됐으면 아무것도 하지 않는다.
-- trusted/prompt/ui 는 시험용 주입(기본 hs.accessibilityState · hs.dialog.alert · hs.urlevent.openURL)
local AX_PANE = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
function M.askAccessibility(trusted, prompt, ui)
  trusted = trusted or hs.accessibilityState
  prompt = prompt or function() hs.accessibilityState(true) end
  ui = ui or {}
  local open = ui.open or function(url) hs.urlevent.openURL(url) end
  local dialog = ui.dialog or function(cb)
    local f = hs.screen.mainScreen():frame()
    hs.dialog.alert(f.x + f.w / 2 - 200, f.y + f.h / 3, cb, MSG.axTitle, MSG.axInfo, MSG.axOpen, MSG.axLater)
  end
  if trusted() then return false end
  if axTimer then return true end                                  -- 이미 안내 중(같은 Lua 상태에서 다시 부른 경우 — 설정 다시 읽기는 상태가 초기화돼 새로 띄운다)
  axNote = hs.alert.show(MSG.axAsk, { textSize = 20 }, hs.screen.mainScreen(), 900)
  prompt()
  local ticks, shown = 0, false
  axTimer = hs.timer.doEvery(2, function()
    ticks = ticks + 1
    if trusted() or ticks >= 450 then
      axTimer:stop(); axTimer = nil
      if axNote then hs.alert.closeSpecific(axNote); axNote = nil end
      if ticks < 450 then hs.alert.show(string.format(MSG.axDone, M.hotkeyLabel()), 6) end
    elseif ticks == 4 and not shown then
      shown = true
      dialog(function(button) if button == MSG.axOpen then open(AX_PANE) end end)
    end
  end)
  return true
end

-- cfg: python, server(필수) · host("claude") · path(셸 PATH) · mods({"ctrl"}) · key("q") · passthrough({번들ID=true})
function M.start(cfg)
  M.cfg = cfg or {}
  M.cfg.host = M.cfg.host or "claude"
  M.cfg.mods = normMods(M.cfg.mods or { "ctrl" })
  M.cfg.key = M.cfg.key or "q"
  M.cfg.defaultMods, M.cfg.defaultKey = M.cfg.mods, M.cfg.key       -- 설치 기본값(메뉴의 기본값으로 되돌리기)
  M.cfg.passthrough = M.cfg.passthrough or {}
  if hk then hk:delete(); hk = nil end
  local saved = readSettings().hotkey                              -- 메뉴에서 바꾼 단축키가 있으면 그것으로
  if type(saved) == "table" and type(saved.key) == "string" and type(saved.mods) == "table" then
    if not M.setHotkey(saved.mods, saved.key, false) then
      hs.alert.show(string.format(MSG.keyStoredBad, M.hotkeyLabel(saved.mods, saved.key), M.hotkeyLabel()), 5)
    end
  end
  if not hk then hk = hs.hotkey.bind(M.cfg.mods, M.cfg.key, M.trigger) end
  -- 처음 한 번: 손쉬운 사용(macOS 27 '기기 제어 및 데이터 접근') 권한이 없으면 macOS 허용 창을 띄운다 — 선택 글 복사·붙여넣기 대행에 필요.
  -- 이미 허용됐으면 아무것도 하지 않는다(설치기가 사람에게 설정 화면을 찾아가라고 하는 대신 시스템 창 하나로)
  M.askAccessibility()
  -- 미리보기·점검(개발용): ~/.imprompt/settings.json 에 "devPreview": true 일 때만 등록한다. 기본은 등록하지 않는다 —
  -- hammerspoon:// URL 은 웹 페이지·다른 앱도 열 수 있어 항상 열어 두면 외부가 화면 패널·파일 저장을 일으킬 수 있다.
  -- open -g "hammerspoon://imprompt-hud-demo" → 진행 패널을 4초 띄웠다 닫는다(키 입력·모델 호출 없음).
  -- ?save=1 이면 0.4초 간격 프레임 8장을 앱 전용 새 폴더 ~/.imprompt/hud-preview/<시각>/hud-NN.png 로 저장(화면 보호기 중에도 확인), 폴더는 최근 5개만 유지.
  -- 경로는 URL 에서 받지 않는다 — 기존 파일 덮어쓰기를 막는다
  if readSettings().devPreview == true then
    hs.urlevent.bind("imprompt-hud-demo", function(_, params)
      local d = progressHud(MSG.hudTitle, MSG.hudSub)
      if params and params.save == "1" then
        local base = os.getenv("HOME") .. "/.imprompt/hud-preview"
        local dir = base .. "/" .. os.date("%Y%m%d-%H%M%S") .. string.format("-%04d", math.random(0, 9999))
        hs.fs.mkdir(os.getenv("HOME") .. "/.imprompt"); hs.fs.mkdir(base)
        if hs.fs.mkdir(dir) then                               -- 새 폴더를 만든 경우에만 저장(이미 있으면 건너뜀)
          local names = {}
          for name in hs.fs.dir(base) do if name:match("^%d+%-%d+%-%d+$") then names[#names + 1] = name end end
          table.sort(names)
          for n = 1, #names - 5 do
            local rm; rm = hs.task.new("/bin/rm", function() live[rm] = nil end, { "-rf", base .. "/" .. names[n] })
            live[rm] = true; rm:start()
          end   -- 오래된 것부터(이름=시각순) 지움(셸 문자열 조립 없이)
          for k = 1, 8 do after(0.4 * k - 0.3, function() d.snapshot(string.format("%s/hud-%02d.png", dir, k)) end) end
        end
      end
      after(4, function() d.stop(); hs.alert.show(MSG.done, 1.5) end)
    end)
  end
  return M
end

return M

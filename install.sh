#!/usr/bin/env bash
# Imprompt 설치: 이 폴더의 파일을 각 도구가 읽는 위치에 연결한다(여러 번 실행해도 안전).
#  - macOS/Linux: 심볼릭 링크.   - Windows(Git Bash): 링크 대신 래퍼(.cmd + bash) 생성 + keybindings 복사.
# 공유 설정 파일(settings.json·config.toml·.zshrc/.bashrc)은 자동 수정하지 않고 snippets/ 병합 안내만 출력한다.
#  - MCP: 설치된 CLI(claude·codex·gemini)마다 imprompt MCP 서버를 사용자 범위로 등록(각 CLI 의 `mcp add` 명령 사용, 지우고 다시 = 멱등).
# 사용: ./install.sh        전체(링크 + MCP 등록)
#       ./install.sh mcp    MCP 등록만 ("mcp 사용해")      IMPROMPT_MCP=0 ./install.sh  MCP 등록 건너뛰기
#       $A/install.sh menubar 메뉴바 상태 아이콘(macOS · Hammerspoon)
#       $A/install.sh hotkey 전역 단축키(아무 앱에서 블록 → Ctrl+Q). macOS = Hammerspoon, Linux = 데스크톱 단축키 안내
#       ./install.sh use    한 번에 쓸 수 있게("사용할 수 있게 해줘"): MCP 등록 + 전역 단축키 + 메뉴바(macOS, Hammerspoon 없으면 Homebrew 로 설치)
#                           엔진 CLI(claude·codex·gemini)가 하나도 없으면 Claude Code 공식 설치기, 로그인이 없으면 브라우저 승인 창
#                           IMPROMPT_NO_PKG=1 이면 프로그램·엔진 자동 설치를, IMPROMPT_NO_LOGIN=1 이면 로그인 창을 건너뛴다
#       ./install.sh uninstall 설치 해제: MCP 등록 해제(claude·codex·gemini) + Hammerspoon 표식 블록 제거(백업). 폴더·로그 삭제는 안내만
#       ./install.sh remove    완전 제거: uninstall + ~/.imprompt + 설치 폴더(설치기가 받은 그대로일 때만). 메뉴바 → Uninstall Imprompt... 와 같음
set -e
A=$(cd "$(dirname "$0")" && pwd)
case "${AI_TOOLS_OSTYPE:-$OSTYPE}" in msys*|cygwin*) WIN=1 ;; *) WIN=0 ;; esac   # AI_TOOLS_OSTYPE=msys 로 Windows 분기 시험

# lua_str: 값을 Lua 긴 문자열로 안전하게 감싼다. 값에 ]] 가 있어도 깨지지 않게 [==[…]==] 처럼 등호를 늘린다
lua_str() {
  local v=$1 eq=
  while :; do
    case "$v" in *"]$eq]"*|*"]$eq") eq="$eq=" ;; *) break ;; esac
  done
  printf '[%s[%s]%s]' "$eq" "$v" "$eq"
}
# clean_path: 저장할 PATH — 절대 경로 항목만(빈 항목·.·상대 경로는 작업 폴더에 따라 다른 프로그램을 가리킬 수 있어 뺀다)
clean_path() {
  local parts p out=
  IFS=: read -ra parts <<< "$PATH"
  for p in ${parts[@]+"${parts[@]}"}; do
    case "$p" in /*) out=${out:+$out:}$p ;; esac
  done
  printf '%s' "$out"
}
# resolve_file <경로>: 심볼릭 링크면 실제 대상 파일 경로(링크 보존 — 링크 자리에 새 파일을 만들지 않고 대상 내용만 고친다)
resolve_file() {
  local f=$1 t
  while [ -L "$f" ]; do
    t=$(readlink "$f")
    case "$t" in /*) f=$t ;; *) f=$(dirname "$f")/$t ;; esac
  done
  printf '%s' "$f"
}
# block_open <파일> <표식 이름>: 시작 표식은 있는데 끝 표식이 없으면 0(참) — 이때 지우면 파일 끝까지 날아가므로 중단해야 한다
block_open() {
  awk -v b="-- $1:begin" -v e="-- $1:end" 'index($0, b) == 1 {o=1} index($0, e) == 1 {o=0} END {exit !o}' "$2"
}
# remove_block <init.lua> <표식 이름>: 표식 블록만 지운다(나머지 내용 보존). 끝 표식이 없으면 아무것도 안 바꾸고 1
remove_block() {
  local f tmp name=$2
  f=$(resolve_file "$1")
  if block_open "$name" "$f"; then echo "  ✗ $f 에 '-- $name:begin' 은 있는데 ':end' 가 없다 — 파일 손상을 막으려 중단. 직접 확인 후 다시 실행" >&2; return 1; fi
  tmp=$(mktemp)
  awk -v b="-- $name:begin" -v e="-- $name:end" 'index($0, b) == 1 {s=1} !s {print} index($0, e) == 1 {s=0}' "$f" > "$tmp" && cat "$tmp" > "$f"
  rm -f "$tmp"
}
# replace_block <init.lua> <표식 이름> <블록>: 옛 표식 블록을 지우고 새 블록을 끝에 붙인다. 끝 표식 없으면 중단(1), 링크면 대상 파일을 고친다
replace_block() {
  local f tmp name=$2
  f=$(resolve_file "$1")
  if [ -f "$f" ] && block_open "$name" "$f"; then
    echo "  ✗ $f 에 '-- $name:begin' 은 있는데 ':end' 가 없다 — 파일 손상을 막으려 중단했다(아무것도 바꾸지 않음). 표식 줄을 직접 고치거나 지운 뒤 다시 실행" >&2; return 1
  fi
  tmp=$(mktemp)
  [ -f "$f" ] && awk -v b="-- $name:begin" -v e="-- $name:end" 'index($0, b) == 1 {s=1} !s {print} index($0, e) == 1 {s=0}' "$f" > "$tmp"
  printf '%s\n' "$3" >> "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"
}

# find_python: 3.8+ 인터프리터의 절대 경로 — 등록은 절대 경로로 해야 GUI·다른 셸에서 띄워도 같은 python 을 쓴다.
#   macOS·Linux 는 PATH 상의 경로(/usr/bin/python3·/opt/homebrew/bin/python3 같은 안정 링크). sys.executable 은 Xcode·Homebrew
#   업데이트 때 바뀌는 버전 경로라 쓰지 않는다. Windows 는 sys.executable(py 런처·Store 스텁 대신 실제 python.exe).
#   Windows 의 python3/python 이 Microsoft Store 안내 스텁이면 버전 확인에서 걸러진다.
# Hammerspoon 이 있는지: 응용 프로그램 폴더(/Applications 또는 ~/Applications). AI_TOOLS_HS_APP(시험용)이 있으면 있는 것으로 본다
#   AI_TOOLS_SYS_APPS 는 시험용(/Applications 대신 볼 폴더 — 이미 깔린 기기에서 '없는 Mac' 흉내)
hs_present() {
  [ -n "${AI_TOOLS_HS_APP:-}" ] || [ -d "${AI_TOOLS_SYS_APPS:-/Applications}/Hammerspoon.app" ] || [ -d "$HOME/Applications/Hammerspoon.app" ]
}
# Homebrew 가 없을 때 Hammerspoon 설치: 공식 GitHub 릴리스(Hammerspoon/hammerspoon) 의 zip 을 받아 ~/Applications 에 둔다 — 관리자 암호 없음.
#   설치 전 검증(하나라도 다르면 설치하지 않음): ① 릴리스가 알려 준 sha256 ② 서명 팀 VQCYSNZB89(Hammerspoon 개발자 ID) ③ Apple 공증(spctl)
#   curl 로 받은 파일은 '인터넷에서 받은 앱' 표식이 없어 처음 열 때 '열기' 확인 창도 뜨지 않는다(대신 위 검증을 설치기가 한다)
HS_TEAM=VQCYSNZB89
install_hammerspoon_direct() {
  local py tmp meta url sum got app dest=$HOME/Applications
  py=$(find_python) || { echo "  ✗ python 3.8+ 없음 — Hammerspoon 을 받지 못함"; return 1; }
  tmp=$(mktemp -d) || return 1
  meta=$(curl -fsSL --max-time 30 https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest | "$py" -c '
import json, re, sys
d = json.load(sys.stdin)
for a in d.get("assets", []):
    u, g = a.get("browser_download_url", ""), a.get("digest") or ""
    if re.fullmatch(r"Hammerspoon-[0-9.]+\.zip", a.get("name", "")) and u.startswith("https://github.com/Hammerspoon/hammerspoon/releases/download/") \
            and re.fullmatch(r"sha256:[0-9a-f]{64}", g):
        print(u, g[7:]); break
' 2>/dev/null) || meta=""
  url=${meta% *}; sum=${meta#* }
  if [ -z "$meta" ]; then echo "  ✗ Hammerspoon 릴리스 정보를 받지 못함(인터넷 연결 확인) → https://www.hammerspoon.org 에서 받아 응용 프로그램 폴더에 넣은 뒤 다시 실행"; rm -rf "$tmp"; return 1; fi
  echo "  … Hammerspoon 받는 중 ($url)"
  if ! curl -fsSL --max-time 300 "$url" -o "$tmp/hs.zip"; then echo "  ✗ Hammerspoon 을 받지 못함: $url"; rm -rf "$tmp"; return 1; fi
  got=$(shasum -a 256 "$tmp/hs.zip" | cut -d' ' -f1)
  if [ "$got" != "$sum" ]; then echo "  ✗ Hammerspoon 파일 해시가 릴리스 값과 다름 — 설치하지 않음"; rm -rf "$tmp"; return 1; fi
  app=$tmp/x/Hammerspoon.app
  if ! ditto -x -k "$tmp/hs.zip" "$tmp/x" || [ ! -d "$app" ]; then echo "  ✗ Hammerspoon 압축을 풀지 못함"; rm -rf "$tmp"; return 1; fi
  if ! codesign --verify --deep --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"$HS_TEAM\"" "$app" 2>/dev/null \
     || ! spctl -a -t exec "$app" 2>/dev/null; then
    rm -rf "$tmp"
    # macOS 기본 앱도 확인이 안 되면 파일이 아니라 실행 환경 탓(에이전트 샌드박스가 macOS 보안 서비스를 막음) → 이유를 알리고 brew 대체도 하지 않는다(같은 이유로 멈춤)
    if ! spctl -a -t exec /System/Applications/Calculator.app 2>/dev/null; then
      echo "  ✗ 이 실행 환경(에이전트 샌드박스)에서는 macOS 서명 확인을 할 수 없음 — 같은 한 줄을 샌드박스 밖(권한 상승·승인)에서 다시 실행"; return 2
    fi
    echo "  ✗ Hammerspoon 서명·공증 확인 실패 — 설치하지 않음"; return 1
  fi
  mkdir -p "$dest" && ditto "$app" "$dest/Hammerspoon.app" || { echo "  ✗ $dest 에 넣지 못함"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  # open -a Hammerspoon 이 바로 찾게 등록(시험 실행 AI_TOOLS_NO_LAUNCH 는 앱을 열지 않으므로 시스템 앱 목록에 남기지 않는다)
  [ -n "${AI_TOOLS_NO_LAUNCH:-}" ] || /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest/Hammerspoon.app" >/dev/null 2>&1 || true
  echo "  ✓ Hammerspoon 설치($dest/Hammerspoon.app — 서명·공증 확인)"
}
find_python() {
  local c out
  for c in python3 python "py -3"; do
    command -v "${c%% *}" >/dev/null 2>&1 || continue
    out=$($c -c 'import sys; print(sys.executable) if sys.version_info >= (3, 8) else sys.exit(1)' 2>/dev/null | tr -d '\r' | tail -1) || continue
    [ -n "$out" ] || continue
    if [ "$WIN" = 1 ] || [ "$c" = "py -3" ]; then printf '%s\n' "$out"; else command -v "$c"; fi
    return 0
  done
  return 1
}
# pick_host <python>: 단축키가 쓸 주 엔진. 로그인된 엔진 우선(claude → codex → gemini), 없으면 설치된 첫 엔진, 그것도 없으면 claude.
#   판정은 imprompt_mcp.py --status-json(상태 명령만, 토큰 0). Windows install.ps1 의 Pick-Host 와 같은 규칙
pick_host() {
  local st e
  local order p
  p=$(printf '%s' "${IMPROMPT_ENGINE:-${IMPROMPT_PREFER:-}}" | tr '[:upper:]' '[:lower:]')   # 사용자가 고른 구독을 같은 조건에서 먼저
  case "$p" in claude|codex|gemini) order="$p $(for e in claude codex gemini; do [ "$e" = "$p" ] || printf '%s ' "$e"; done)" ;; *) order="claude codex gemini"; p="" ;; esac
  st=$(PYTHONIOENCODING=utf-8 "$1" "$A/prompt-improver/mcp/imprompt_mcp.py" --status-json 2>/dev/null) || { echo "${order%% *}"; return 0; }
  if [ -n "$p" ]; then                                                               # 고른 구독이 설치돼 있으면 로그인 전이라도 그것
    case "$st" in *"\"$p\": \"missing\""*) ;; *"\"$p\""*) echo "$p"; return 0 ;; esac
  fi
  for e in $order; do case "$st" in *"\"$e\": \"ok\""*) echo "$e"; return 0 ;; esac; done
  for e in $order; do case "$st" in *"\"$e\": \"missing\""*) ;; *"\"$e\""*) echo "$e"; return 0 ;; esac; done
  echo "${order%% *}"
}
# register_mcp: 설치된 CLI 마다 'imprompt' 를 지우고 다시 등록. 각 CLI 의 공식 명령만 쓴다(설정 파일 직접 편집 없음, 자격증명 무관)
register_mcp() {
  local py srv n=0
  echo "MCP 등록 (imprompt → improve_prompt 도구):"
  py=$(find_python) || { echo "  ✗ python 3.8+ 없음 → MCP 등록 건너뜀 (python.org 설치 후 $A/install.sh mcp)"; return 0; }
  srv=$A/prompt-improver/mcp/imprompt_mcp.py
  [ "$WIN" = 1 ] && srv=$(cygpath -w "$srv")
  if command -v claude >/dev/null 2>&1; then
    claude mcp remove -s user imprompt >/dev/null 2>&1 || true
    if claude mcp add -s user imprompt -- "$py" "$srv" --host claude >/dev/null 2>&1; then echo "  ✓ claude (사용자 범위)"; n=$((n + 1)); else echo "  ✗ claude 등록 실패 → claude mcp add -s user imprompt -- \"$py\" \"$srv\" --host claude"; fi
  else echo "  - claude 없음(건너뜀)"; fi
  if command -v codex >/dev/null 2>&1; then
    codex mcp remove imprompt >/dev/null 2>&1 || true
    if codex mcp add imprompt -- "$py" "$srv" --host codex >/dev/null 2>&1; then echo "  ✓ codex"; n=$((n + 1)); else echo "  ✗ codex 등록 실패 → codex mcp add imprompt -- \"$py\" \"$srv\" --host codex"; fi
  else echo "  - codex 없음(건너뜀)"; fi
  if command -v gemini >/dev/null 2>&1; then
    gemini mcp remove -s user imprompt >/dev/null 2>&1 || true
    # gemini 는 '--' 뒤를 서버 인자로 넘긴다(앞에 두면 --host 를 자기 옵션으로 해석). --trust 는 쓰지 않는다: 호출 확인 창을 우회하는 옵션이라 공개판에서는 gemini 기본(첫 호출 때 확인)을 따른다
    if gemini mcp add -s user imprompt "$py" -- "$srv" --host gemini >/dev/null 2>&1; then echo "  ✓ gemini (사용자 범위)"; n=$((n + 1)); else echo "  ✗ gemini 등록 실패 → gemini mcp add -s user imprompt \"$py\" -- \"$srv\" --host gemini"; fi
  else echo "  - gemini 없음(건너뜀)"; fi
  MCP_N=$n                                                                                # use 모드가 성공 여부 판단에 쓴다(mcp 모드 반환값은 그대로 0)
  [ "$n" -eq 0 ] && echo "  ✗ 등록된 CLI 없음 → claude·codex·gemini 중 하나를 설치한 뒤 $A/install.sh mcp"
  # 로그인 상태 안내(토큰 0). 전체 설치(use)에서는 생략 — 로그인 전이라 쓰지 않는 엔진·미로그인 ✗ 줄이 실패처럼 보인다(끝 요약이 실제 상태를 보여 준다)
  [ -n "${IN_USE:-}" ] || PYTHONIOENCODING=utf-8 "$py" "$srv" --check || true
  [ -n "${IN_USE:-}" ] || { [ "$n" -gt 0 ] && echo "적용: CLI 를 새로 열고 \"이 요청 improve_prompt 로 개선해줘: …\""; }
  return 0
}
# register_hotkey: 전역 단축키(아무 앱에서 블록 → Ctrl+Q). macOS = Hammerspoon init.lua 에 표식 블록(지우고 다시 = 멱등, 기존 내용 보존·백업)
register_hotkey() {
  local py f block
  echo "전역 단축키 (아무 앱에서 문장 블록 → 단축키, 기본 Ctrl+Q · 터미널은 기존 개선기 그대로):"
  case "${AI_TOOLS_UNAME:-$(uname -s)}" in
    Darwin) ;;
    Linux) chmod +x "$A/hotkey/imprompt-linux.sh"
           [ -n "${IN_USE:-}" ] && { echo "  - Linux: 데스크톱 단축키는 직접 연결(아래 요약의 안내)"; return 0; }
           echo "  Linux: 데스크톱 설정의 사용자 단축키에 $A/hotkey/imprompt-linux.sh 를 연결하세요(권장 Super+Q — 데스크톱 단축키는 터미널의 Ctrl+Q 도 가로챔)."
           echo "  필요: X11 = xclip·xdotool(그 자리 교체) / Wayland = wl-clipboard(복사한 글 → 결과는 클립보드에만), 알림 notify-send(없으면 진행·실패 표시 없음)"; return 0 ;;
    *) echo "  Windows: PowerShell 에서 powershell -ExecutionPolicy Bypass -File install.ps1 hotkey (AutoHotkey v2 필요)"; return 0 ;;
  esac
  py=$(find_python) || { echo "  ✗ python 3.8+ 없음 → python.org 설치 후 $A/install.sh hotkey"; return 0; }
  if ! hs_present; then
    echo "  ✗ Hammerspoon 없음 → https://www.hammerspoon.org 에서 받아 응용 프로그램 폴더에 넣은 뒤 $A/install.sh hotkey"; return 0
  fi
  # 설치할 때 고른 단축키(IMPROMPT_HOTKEY="Ctrl+Shift+Q" 등): imprompt_mcp.py 가 검사해 ~/.imprompt/settings.json 에 저장 → Hammerspoon 이 시작할 때 읽는다
  local hkl hko
  hkl=$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --hotkey-show 2>/dev/null) || hkl="Ctrl+Q"   # 지금 저장된 단축키(없으면 Ctrl+Q)
  if [ -n "${IMPROMPT_HOTKEY:-}" ]; then
    if hko=$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --hotkey-spec "$IMPROMPT_HOTKEY" --target mac 2>&1); then
      hkl=$hko; echo "  ✓ 단축키 $hkl 로 설정(~/.imprompt/settings.json)"
    else
      echo "  ! 단축키 '$IMPROMPT_HOTKEY' 를 쓸 수 없습니다: $hko → 기본(또는 지금) 단축키로 둡니다. 나중에 메뉴바 연필 아이콘 → Hotkey → Change Hotkey..."
    fi
  fi
  mkdir -p "$HOME/.hammerspoon"; f=$HOME/.hammerspoon/init.lua
  [ -s "$f" ] && cp "$f" "$f.bak-$(date +%Y%m%d%H%M%S)"
  # 경로는 Lua 긴 문자열로 — 따옴표·역슬래시·]] 가 들어 있어도 안전(lua_str). PATH 는 GUI 앱에서 claude·codex 를 찾게 지금 셸 값(절대 경로 항목만)을 저장.
  # 전역 package.path 는 건드리지 않는다(저장소 폴더가 Hammerspoon 의 모든 require 를 가로채지 않게) — dofile 로 읽어 menubar 가 찾는 require("imprompt") 자리에만 등록
  block="-- imprompt-hotkey:begin (install.sh hotkey 가 관리 — 이 블록만 지우고 다시 씀)
hs.autoLaunch(true)   -- 로그인할 때 자동 실행(단축키 상시 대기)
package.loaded[\"imprompt\"] = dofile($(lua_str "$A/hotkey/imprompt.lua"))
require(\"imprompt\").start({ python = $(lua_str "$py"), server = $(lua_str "$A/prompt-improver/mcp/imprompt_mcp.py"), host = $(lua_str "$(pick_host "$py")"), path = $(lua_str "$(clean_path)") })
-- imprompt-hotkey:end"
  replace_block "$f" imprompt-hotkey "$block" || return 1
  echo "  ✓ ~/.hammerspoon/init.lua 에 단축키 블록 기록(기존 내용 유지, 백업 .bak-시각)"
  if [ -z "${AI_TOOLS_NO_LAUNCH:-}" ]; then
    osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
    sleep 1
    if open -g -a Hammerspoon; then echo "  ✓ Hammerspoon 다시 시작(설정 적용)"
    else echo "  ✗ Hammerspoon 을 열지 못함 → Finder → 응용 프로그램(또는 홈 폴더의 응용 프로그램)에서 Hammerspoon 을 직접 열기"; HS_FAIL=1; fi
  fi
  [ -n "${IN_USE:-}" ] && return 0                                # 전체 설치는 끝 요약에서 한 번만 안내
  echo "  처음 한 번: 'Hammerspoon 이 … 제어하려고 합니다' 창에서 시스템 설정 열기 → Hammerspoon 켜기(화면 가운데 안내와 함께 뜸, 키 입력·복사·붙여넣기용)"
  echo "적용: 아무 앱에서 문장을 블록으로 잡고 $hkl (10~30초 뒤 그 자리에서 교체). 바꾸기: 메뉴바 연필 아이콘 → Hotkey"
  return 0
}
# register_menubar: 메뉴바 상태 아이콘(macOS · Hammerspoon). 작업 목록·사용 중 agent·계정 로그인 상태/조작. 표식 블록 멱등
register_menubar() {
  local py f block
  echo "메뉴바 상태 아이콘 (개선 중에만 움직임, 클릭 = 작업·agent·계정):"
  [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ] || { echo "  - macOS 전용(건너뜀)"; return 0; }
  py=$(find_python) || { echo "  ✗ python 3.8+ 없음"; return 0; }
  if ! hs_present; then
    echo "  ✗ Hammerspoon 없음 → https://www.hammerspoon.org 설치 후 $A/install.sh menubar"; return 0
  fi
  mkdir -p "$HOME/.hammerspoon"; f=$HOME/.hammerspoon/init.lua
  [ -s "$f" ] && cp "$f" "$f.bak-$(date +%Y%m%d%H%M%S)"
  block="-- imprompt-menubar:begin (install.sh menubar 가 관리 — 이 블록만 지우고 다시 씀)
hs.autoLaunch(true)
dofile($(lua_str "$A/menubar/imprompt_menubar.lua")).start({ python = $(lua_str "$py"), server = $(lua_str "$A/prompt-improver/mcp/imprompt_mcp.py"), path = $(lua_str "$(clean_path)") })
-- imprompt-menubar:end"
  replace_block "$f" imprompt-menubar "$block" || return 1
  echo "  ✓ ~/.hammerspoon/init.lua 에 메뉴바 블록 기록(기존 내용 유지, 백업 .bak-시각)"
  if [ -z "${AI_TOOLS_NO_LAUNCH:-}" ]; then
    osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
    sleep 1
    if open -g -a Hammerspoon; then echo "  ✓ Hammerspoon 다시 시작(설정 적용)"
    else echo "  ✗ Hammerspoon 을 열지 못함 → Finder → 응용 프로그램(또는 홈 폴더의 응용 프로그램)에서 Hammerspoon 을 직접 열기"; HS_FAIL=1; fi
  fi
  [ -n "${IN_USE:-}" ] && return 0
  echo "적용: 우측 상단 메뉴바의 연필 아이콘 — 개선 중에만 별이 반짝이고, 누르면 작업·agent·계정"
  return 0
}
# want_engine: 쓸 구독(엔진). IMPROMPT_ENGINE(claude|codex|gemini, 에이전트가 자기 엔진을 넘긴다) → 이미 설치된 CLI 가 있으면 빈 값
#   → 사람이 직접 실행한 터미널(/dev/tty)이면 한 번 묻는다(Claude / ChatGPT / Gemini) → 묻지 못하면 claude. install.ps1 의 Want-Engine 과 같은 규칙
want_engine() {
  local e a
  e=$(printf '%s' "${IMPROMPT_ENGINE:-}" | tr '[:upper:]' '[:lower:]')
  case "$e" in claude|codex|gemini) echo "$e"; return 0 ;; esac
  if command -v claude >/dev/null 2>&1 || command -v codex >/dev/null 2>&1 || command -v gemini >/dev/null 2>&1; then echo ""; return 0; fi
  if [ "${IMPROMPT_NO_LOGIN:-0}" != 1 ] && [ "${CI:-}" != true ] && [ -z "${AI_TOOLS_NO_ASK:-}" ] && ( : </dev/tty ) 2>/dev/null; then
    { echo "  어떤 AI 구독을 쓰세요? (그 구독의 CLI 를 설치하고 로그인합니다)"
      echo "    1) Claude (claude.ai)   2) ChatGPT (Codex CLI)   3) Gemini (Google)"
      printf "  번호 [1]: "; } >/dev/tty
    IFS= read -r a </dev/tty || a=""
    case "$a" in 2) echo codex ;; 3) echo gemini ;; *) echo claude ;; esac
    return 0
  fi
  echo claude
}
engine_name() { case "$1" in codex) echo "Codex CLI (ChatGPT)" ;; gemini) echo "Gemini CLI" ;; *) echo "Claude Code" ;; esac; }
engine_hint() {
  case "$1" in
    codex) echo "curl -fsSL https://chatgpt.com/codex/install.sh | sh" ;;
    gemini) echo "brew install gemini-cli (또는 Node.js 20+ 에서 npm install -g @google/gemini-cli)" ;;
    *) echo "curl -fsSL https://claude.ai/install.sh | bash" ;;
  esac
}
# ensure_engine: 쓸 구독의 엔진 CLI 가 없으면 공식 설치(사용자 범위). 새 셸 없이 이어서 찾도록 PATH 에 바로 더한다
#   claude: https://code.claude.com/docs/en/setup (curl -fsSL https://claude.ai/install.sh | bash → ~/.local/bin/claude)
#   codex : https://learn.chatgpt.com/docs/codex/cli (curl -fsSL https://chatgpt.com/codex/install.sh | sh → ~/.local/bin/codex)
#   gemini: https://geminicli.com/docs/get-started/installation (brew install gemini-cli, 또는 Node.js 20+ 의 npm install -g @google/gemini-cli)
ensure_engine() {
  echo "엔진 CLI (개선을 실제로 하는 AI — 사용자 본인 구독):"
  local want nm url def ov sh log run
  want=$(want_engine)
  if [ -z "$want" ]; then echo "  ✓ 설치됨"; return 0; fi
  WANT_ENGINE=$want; export IMPROMPT_PREFER=$want
  nm=$(engine_name "$want")
  if command -v "$want" >/dev/null 2>&1; then echo "  ✓ $nm 설치됨"; return 0; fi
  if [ "${IMPROMPT_NO_PKG:-0}" = 1 ]; then echo "  ✗ $nm 없음 · 자동 설치 건너뜀(IMPROMPT_NO_PKG=1) → $(engine_hint "$want")"; return 1; fi
  log=$(mktemp)
  if [ "$want" = gemini ]; then
    if command -v brew >/dev/null 2>&1; then
      echo "  … Gemini CLI 설치 중 (brew install gemini-cli, 1~3분)"; brew install gemini-cli >"$log" 2>&1 || true
    elif command -v npm >/dev/null 2>&1; then
      echo "  … Gemini CLI 설치 중 (npm install -g @google/gemini-cli, 1~3분)"
      npm install -g @google/gemini-cli >"$log" 2>&1 || npm install -g @google/gemini-cli --prefix "$HOME/.local" >"$log" 2>&1 || true
    else
      echo "Homebrew·npm 이 없음 (Node.js 20+ 필요)" >"$log"
    fi
  else
    if [ "$want" = codex ]; then def=https://chatgpt.com/codex/install.sh; ov=${IMPROMPT_CODEX_INSTALLER:-}
    else def=https://claude.ai/install.sh; ov=${IMPROMPT_CLAUDE_INSTALLER:-}; fi
    url=${ov:-$def}
    if [ -n "$ov" ]; then echo "  ⚠ 기본값 아닌 주소: $url"; fi
    echo "  … $nm 설치 중 (공식 설치기: curl -fsSL $url | $([ "$want" = codex ] && echo sh || echo bash), 1~2분)"
    sh=$(mktemp)
    run=bash; [ "$want" = codex ] && run=sh                                           # 공식 안내 그대로: codex 는 | sh, claude 는 | bash
    if curl -fsSL "$url" -o "$sh" && CODEX_NON_INTERACTIVE=1 "$run" "$sh" >"$log" 2>&1 < /dev/null; then :; fi
    rm -f "$sh"
  fi
  export PATH="$HOME/.local/bin:$PATH"; hash -r
  if command -v "$want" >/dev/null 2>&1; then echo "  ✓ $nm 설치"; rm -f "$log"; return 0; fi
  echo "  ! 설치기 마지막 출력:"; tail -n 5 "$log" | sed 's/^/    /'; rm -f "$log"
  echo "  ✗ $nm 설치 실패 → 터미널에서 $(engine_hint "$want") 후 다시 실행"; return 1
}
# ensure_login: 엔진이 있는데 로그인된 것이 하나도 없으면 고른 구독(없으면 설치된 첫 엔진)의 로그인을 띄우고 최대 5분 기다린다.
#   claude: claude auth login --claudeai / codex: codex login(브라우저에서 Sign in with ChatGPT) / gemini: 대화형 첫 화면(macOS 는 새 터미널 창)
#   판정은 imprompt_mcp.py --status-json(상태 명령만, 토큰 0). 실패해도 설치는 성공으로 두고 안내만
ensure_login() {
  [ "${IMPROMPT_NO_LOGIN:-0}" = 1 ] && return 0
  local py st pid dog eng e how t w okpat
  py=$(find_python) || return 0
  st=$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --status-json 2>/dev/null) || return 0
  w=${WANT_ENGINE:-${IMPROMPT_PREFER:-}}
  case "$w" in claude|codex|gemini) command -v "$w" >/dev/null 2>&1 || w="" ;; *) w="" ;; esac
  if [ -n "$w" ]; then okpat="\"$w\": \"ok\""; else okpat='"ok"'; fi              # 구독을 골랐으면 그 엔진의 로그인만 본다
  case "$st" in *$okpat*|*'"unknown"'*|'') return 0 ;; esac                         # 로그인돼 있으면(또는 확인 불가면) 그대로
  eng=$w
  [ -n "$eng" ] || for e in claude codex gemini; do command -v "$e" >/dev/null 2>&1 && { eng=$e; break; }; done
  [ -n "$eng" ] || { echo "  ! 엔진 CLI 가 없어 로그인할 수 없습니다"; return 0; }
  case "$eng" in claude) how="claude auth login" ;; codex) how="codex login" ;; gemini) how="gemini (실행 후 Login with Google)" ;; esac
  if [ "$eng" = gemini ]; then
    if [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ] && [ -z "${AI_TOOLS_NO_LAUNCH:-}" ]; then
      echo "로그인: 새 터미널 창에 Gemini 를 엽니다 → Login with Google 을 고르고 브라우저에서 승인하세요(최대 5분 기다림)"
      osascript -e 'tell application "Terminal" to do script "gemini"' >/dev/null 2>&1 || true
      t=0; while [ "$t" -lt "${IMPROMPT_LOGIN_WAIT:-300}" ]; do
        case "$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --status-json 2>/dev/null)" in *'"gemini": "ok"'*) break ;; esac
        sleep 3; t=$((t + 3))
      done
    else
      echo "  ! Gemini 로그인 필요 → 새 터미널에서 gemini 실행 후 Login with Google"; return 0
    fi
  else
    if [ "$eng" = claude ]; then echo "로그인: 브라우저에 Claude 승인 창을 엽니다(본인 claude.ai 계정, 최대 5분 기다림)"
      claude auth login --claudeai < /dev/null > >(sed 's/^/    /') 2>&1 & pid=$!   # 출력은 보인다(브라우저가 저절로 안 열리면 여기 나온 주소를 열면 된다). $! = claude 자신(시간 초과 때 끝낼 대상)
    else echo "로그인: 브라우저에 ChatGPT 로그인 창을 엽니다(본인 ChatGPT 계정, 최대 5분 기다림)"
      codex login < /dev/null > >(sed 's/^/    /') 2>&1 & pid=$!
    fi
    ( sleep "${IMPROMPT_LOGIN_WAIT:-300}" && kill "$pid" ) 2>/dev/null & dog=$!
    wait "$pid" 2>/dev/null || true                                                   # set -e: 로그인 실패·시간 초과가 설치를 멈추지 않게
    pkill -P "$dog" 2>/dev/null || true; kill "$dog" 2>/dev/null || true; wait "$dog" 2>/dev/null || true
  fi
  st=$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --status-json 2>/dev/null) || true
  case "$st" in *$okpat*) echo "  ✓ 로그인 완료" ;; *) if [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ]; then echo "  ! 로그인 안 됨 → 메뉴바 연필 아이콘 → Accounts 아래 $eng → Sign In...(브라우저 승인), 또는 터미널에서 $how"
     else echo "  ! 로그인 안 됨 → 터미널에서 $how (브라우저 승인)"; fi ;; esac
  return 0
}

# uninstall: 설치 해제(연결만 끊음). MCP 등록(claude·codex·gemini)과 Hammerspoon 표식 블록만 지운다 — 폴더·기록은 안내만
# remove: 완전 제거(메뉴바 → Uninstall Imprompt...). uninstall + 기록·설정(~/.imprompt) + 설치 폴더.
#   설치 폴더는 설치기가 받은 그대로(특정 커밋에 고정·고친 파일 없음)일 때만 지운다 — 개발용 작업 폴더를 지우지 않게.
#   Hammerspoon·엔진 CLI 는 다른 곳에서도 쓸 수 있어 남긴다. AI_TOOLS_NO_LAUNCH=1 이면 Hammerspoon 재시작 생략(메뉴바가 직접 다시 읽는다)
if [ "${1:-}" = uninstall ] || [ "${1:-}" = remove ]; then
  mode=$1
  if [ "$mode" = remove ]; then echo "== Imprompt 완전 제거 =="; else echo "== Imprompt 설치 해제 =="; fi
  for c in claude codex gemini; do
    command -v "$c" >/dev/null 2>&1 || { echo "  - $c 없음(건너뜀)"; continue; }
    case $c in codex) set -- mcp remove imprompt ;; *) set -- mcp remove -s user imprompt ;; esac
    if "$c" "$@" >/dev/null 2>&1; then echo "  ✓ $c MCP 등록 해제"; else echo "  - $c 에 등록된 imprompt 없음(또는 이미 해제)"; fi
  done
  if py=$(find_python); then PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --editor-keys-off || true; fi   # 설치기가 바꾼 Claude Code 입력창 설정만 되돌림
  hs=$HOME/.hammerspoon/init.lua
  if [ -f "$hs" ] && grep -q -e '^-- imprompt-hotkey:begin' -e '^-- imprompt-menubar:begin' "$hs"; then
    cp "$hs" "$hs.bak-$(date +%Y%m%d%H%M%S)"
    remove_block "$hs" imprompt-hotkey && remove_block "$hs" imprompt-menubar || { echo "  ✗ 블록 제거 중단(위 안내 참고)"; exit 1; }
    echo "  ✓ ~/.hammerspoon/init.lua 에서 Imprompt 블록 제거(백업 .bak-시각, 다른 내용 유지)"
    if [ -z "${AI_TOOLS_NO_LAUNCH:-}" ] && [ "$(uname -s)" = Darwin ]; then
      osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
      sleep 1; open -g -a Hammerspoon >/dev/null 2>&1 && echo "  ✓ Hammerspoon 다시 시작(단축키·메뉴바 해제 적용)"
    fi
  else echo "  - Hammerspoon 에 Imprompt 블록 없음"; fi
  if [ "$mode" = uninstall ]; then
    echo "남은 것(직접 지우기 — 자동으로 지우지 않음. 한 번에 지우려면 메뉴바 연필 아이콘 → Uninstall Imprompt... 또는 ./install.sh remove):"
    echo "  · 설치 폴더: $A  (삭제하려면 폴더를 지우면 됨)"
    echo "  · 로컬 기록: ~/.imprompt/ (작업 내역·캐시·설정), ~/.claude/prompt-improver/*.log — 필요 없으면 삭제"
    echo "  · 전체 설치(./install.sh)를 했다면 만든 링크: ~/bin/pi-edit · ~/.claude/prompt-improver/instructions.md · ~/.claude/hooks/codex-review-gate.py · ~/.claude/keybindings.json 와 settings.json·config.toml·셸 rc 에 직접 병합한 항목"
    echo "  · 엔진 CLI(Claude Code 등)와 Hammerspoon 은 그대로 둠"
    exit 0
  fi
  left=""
  st=${IMPROMPT_HOME:-$HOME/.imprompt}
  # IMPROMPT_HOME 을 다른 폴더로 바꿔 둔 경우 그 폴더째 지우지 않는다(사용자 폴더 오삭제 방지) — 기본 위치만 자동 삭제
  if [ "$st" != "$HOME/.imprompt" ]; then echo "  - IMPROMPT_HOME 이 기본 위치가 아니라 지우지 않음: $st — Imprompt 기록만 직접 삭제"
  elif [ -d "$st" ]; then rm -rf -- "$st" 2>/dev/null; if [ -e "$st" ]; then left="$left
$st"; else echo "  ✓ 기록·설정·내 지침 삭제: $st"; fi; fi
  # 입력창 개선기 기록(~/.claude/prompt-improver): Imprompt 가 만든 이름의 파일만 지운다(같은 폴더의 다른 파일·폴더는 그대로)
  pd=$HOME/.claude/prompt-improver; gone=0
  for n in invocations.log invocations.log.1 last-original.txt last-answers.txt last-ask.log last-run.log; do
    if [ -f "$pd/$n" ] && [ ! -L "$pd/$n" ]; then rm -f -- "$pd/$n" && gone=1; fi
  done
  [ "$gone" = 1 ] && echo "  ✓ 입력창 개선기 기록 삭제: $pd (기록 파일만)"
  rmdir "$pd" 2>/dev/null || true
  rmdir "$HOME/.cache/imprompt" 2>/dev/null || true             # Linux 단축키 잠금 폴더(비어 있을 때만)
  # 지우는 조건(모두): 설치기가 새로 받은 표식 · 표식에 적힌 커밋 = HEAD(그 위에 쌓은 커밋 없음) · 브랜치가 아닌 고정 커밋(symbolic-ref 종료 코드 1)
  #   · status 성공 + 고친·새·무시 목록 파일 없음(.DS_Store 만 예외) · stash 없음. 하나라도 확인 못 하면 남긴다
  rcref=0; git -C "$A" symbolic-ref -q HEAD >/dev/null 2>&1 || rcref=$?
  mk=$(sed -n 's/^commit=\([0-9a-f]\{40\}\)$/\1/p' "$A/.git/imprompt-installed" 2>/dev/null | head -n 1)
  hd=$(git -C "$A" rev-parse HEAD 2>/dev/null) || hd=""
  if [ -f "$A/.git/imprompt-installed" ] && [ -n "$mk" ] && [ "$mk" = "$hd" ] && [ "$rcref" = 1 ] \
     && stv=$(git -C "$A" status --porcelain --ignored 2>/dev/null) && [ -z "$(printf '%s\n' "$stv" | grep -v -E -e '^$' -e '^.. (.*/)?\.DS_Store$')" ] \
     && shv=$(git -C "$A" stash list 2>/dev/null) && [ -z "$shv" ]; then
    cd / && rm -rf -- "$A" 2>/dev/null
    if [ -e "$A" ]; then left="$left
$A"; else echo "  ✓ 설치 폴더 삭제: $A"; fi
  else
    echo "  - 설치 폴더는 남김(설치기가 받은 폴더라는 표식이 없거나, 받은 뒤 커밋·브랜치·고친 파일·보관이 있거나, 확인 실패): $A — 필요 없으면 직접 삭제"
  fi
  printf '%s\n' "$left" | while IFS= read -r l; do if [ -n "$l" ]; then echo "  ! 지우지 못함 — 직접 삭제: $l"; fi; done   # 줄 단위(공백 든 경로 유지)
  echo "남겨 둔 것: Hammerspoon·AI CLI(Claude Code 등)는 다른 곳에서도 쓸 수 있어 그대로 둡니다 — 필요 없으면 응용 프로그램 폴더에서 삭제."
  [ -z "$left" ] || exit 1
  exit 0
fi

# register_editor_keys: Claude Code 입력창 Ctrl+Q → 개선기(config/keybindings.json 과 같은 바인딩 + settings.json env.VISUAL = ~/bin/pi-edit).
#   ~/bin/pi-edit 은 없을 때만 링크로 만든다(사용자가 둔 다른 파일은 그대로). 병합 규칙·되돌리기는 imprompt_mcp.py --editor-keys(-off)
register_editor_keys() {
  case "${AI_TOOLS_UNAME:-$(uname -s)}" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac
  local py pe="$HOME/bin/pi-edit" made=""
  py=$(find_python) || { echo "입력창 단축키: ✗ python 3.8+ 없음(건너뜀)"; return 0; }
  chmod +x "$A/prompt-improver/pi-edit" 2>/dev/null || true
  if [ ! -e "$pe" ] && [ ! -L "$pe" ]; then                      # 없을 때만 만든다 — 다른 곳을 가리키는 사용자 링크·파일은 그대로
    mkdir -p "$HOME/bin" && ln -s "$A/prompt-improver/pi-edit" "$pe" && made="--created-link"
  fi
  if [ ! -L "$pe" ] || [ "$(readlink "$pe")" != "$A/prompt-improver/pi-edit" ]; then
    echo "입력창 단축키: - $pe 가 이미 다른 파일이라 건너뜀(전역 단축키는 그대로 동작)"; return 0
  fi
  PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --editor-keys "$pe" $made
}

# use: 일반 사용자용 한 번에 설치. 사람 손이 꼭 필요한 일(손쉬운 사용 허용·CLI 로그인)만 마지막에 안내한다
if [ "${1:-}" = use ]; then
  # Windows(Git Bash): 프로그램 설치·단축키는 PowerShell 쪽이 맡는다 → install.ps1 use 에 그대로 넘기고 그 결과 코드로 끝낸다
  case "${AI_TOOLS_UNAME:-$(uname -s)}" in MINGW*|MSYS*|CYGWIN*)
    ps=$(command -v powershell.exe || command -v pwsh.exe || true)
    [ -n "$ps" ] || { echo "  ✗ PowerShell 을 찾지 못함 → PowerShell 에서 install.ps1 use 실행"; exit 1; }
    w=$(cygpath -w "$A/install.ps1" 2>/dev/null || echo "$A/install.ps1")
    "$ps" -NoProfile -ExecutionPolicy Bypass -File "$w" use; exit $? ;;
  esac
  echo "== Imprompt 전체 설치: AI 프로그램 → 연결 → 단축키$([ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ] && echo ' → 메뉴바') → 로그인 =="
  IN_USE=1; HS_FAIL=0
  [ -n "${IMPROMPT_HOME:-}" ] || { mkdir -p "$HOME/.imprompt" && chmod 700 "$HOME/.imprompt"; } 2>/dev/null   # 기록·설정 폴더는 처음부터 본인만(Hammerspoon 이 먼저 만들면 755)
  fail=0
  ensure_engine || fail=1
  MCP_N=0; register_mcp
  [ "$MCP_N" -gt 0 ] || fail=1
  if [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ]; then
    if ! hs_present; then
      if [ "${IMPROMPT_NO_PKG:-0}" = 1 ]; then echo "  - Hammerspoon 자동 설치 건너뜀(IMPROMPT_NO_PKG=1)"
      # 공식 릴리스 직접 설치를 먼저(검증·빠름·관리자 암호와 '열기' 확인 창 없음). 실패할 때만 Homebrew —
      # brew 는 처음 쓰면 패키지 목록을 받느라 출력 없이 오래 걸릴 수 있어(에이전트 시간 제한) 기본 경로로 두지 않는다
      else
        hrc=0; install_hammerspoon_direct || hrc=$?
        if [ "$hrc" = 1 ] && command -v brew >/dev/null 2>&1; then
          echo "  … Hammerspoon 설치 중 (brew install --cask hammerspoon — 진행 출력이 이어짐)"
          if HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask hammerspoon 2>&1 | sed 's/^/    /'; [ "${PIPESTATUS[0]}" = 0 ]; then echo "  ✓ Hammerspoon 설치"
          else echo "  ✗ Hammerspoon 설치 실패 → brew install --cask hammerspoon"; fi
        fi
      fi
    fi
    if ! hs_present; then fail=1; fi
    # 단축키·메뉴바 블록을 다 쓴 뒤 Hammerspoon 을 한 번만 다시 시작한다(두 번 재시작하면 권한 창·안내문이 깜빡이며 두 번 뜬다)
    AI_TOOLS_NO_LAUNCH=${AI_TOOLS_NO_LAUNCH:-1} register_hotkey || fail=1
    register_menubar || fail=1
    register_editor_keys || fail=1
    [ "$HS_FAIL" = 1 ] && fail=1
  else
    register_hotkey || fail=1
    register_editor_keys || fail=1                                # Linux 도 Claude Code 입력창 Ctrl+Q 연결(macOS 와 같은 규칙·되돌리기)
  fi
  ensure_login
  # 끝 요약(실제 상태) — install.ps1 과 같은 형식. ✗ = 다시 실행 전에 고칠 것, ! = 사람이 할 한 가지
  mac=0; [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ] && mac=1
  mark() { if [ "$1" = 0 ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fi; }
  py=$(find_python) || py=""
  st=""; [ -n "$py" ] && st=$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --status-json 2>/dev/null)
  hkl=Ctrl+Q; [ -n "$py" ] && { hkl=$(PYTHONIOENCODING=utf-8 "$py" "$A/prompt-improver/mcp/imprompt_mcp.py" --hotkey-show 2>/dev/null) || hkl=Ctrl+Q; }
  echo "요약(실제 상태):"
  e=1; { command -v claude || command -v codex || command -v gemini; } >/dev/null 2>&1 && e=0; mark $e "AI 프로그램(Claude Code·Codex·Gemini 중 하나)"
  m=1; [ "${MCP_N:-0}" -gt 0 ] && m=0; mark $m "AI 프로그램에 Imprompt 연결"
  case "$st" in *'": "ok"'*) login=0 ;; *) login=1 ;; esac
  if [ "$mac" = 1 ]; then
    h=1; hs_present && grep -q '^-- imprompt-hotkey:begin' "$HOME/.hammerspoon/init.lua" 2>/dev/null && [ "$HS_FAIL" = 0 ] && h=0; mark $h "단축키(Hammerspoon)"
    b=1; grep -q '^-- imprompt-menubar:begin' "$HOME/.hammerspoon/init.lua" 2>/dev/null && b=0; mark $b "메뉴바 연필 아이콘"
  else
    if { command -v xclip && command -v xdotool; } >/dev/null 2>&1 || command -v wl-copy >/dev/null 2>&1; then echo "  ✓ 클립보드 도구"; else echo "  ! 클립보드 도구 없음 — X11: xclip·xdotool / Wayland: wl-clipboard (Ubuntu·Debian: sudo apt install xclip xdotool libnotify-bin)"; fi
    echo "  ! 단축키는 직접 연결(한 번): 설정 → 키보드 → 사용자 지정 단축키 → 명령 $A/hotkey/imprompt-linux.sh , 키 Super+Q"
  fi
  if [ "$login" = 0 ]; then echo "  ✓ AI 구독 로그인"
  elif [ "$mac" = 1 ]; then echo "  ! AI 구독 로그인 안 됨 → 메뉴바 연필 아이콘 → Accounts 아래 claude → Sign In...(브라우저 승인)"
  else echo "  ! AI 구독 로그인 안 됨 → 터미널에서 claude auth login (브라우저 승인)"; fi
  if [ "$mac" = 1 ]; then
    echo "남은 일: 'Hammerspoon 이 … 제어하려고 합니다' 창에서 시스템 설정 열기 → Hammerspoon 켜기(처음 한 번 — 놓쳤으면 화면 가운데 'Open Settings' 를 누름). 켜면 'Imprompt is ready' 가 뜬다"
    echo "쓰는 법: 아무 앱에서 문장을 블록으로 잡고 $hkl — 10~30초 뒤 그 자리에서 바뀐다. 우측 상단 메뉴바 연필 아이콘에서 단축키 변경·로그인·작업 내역"
  else
    echo "쓰는 법: 단축키를 연결한 뒤 아무 앱에서 문장을 블록으로 잡고 Super+Q(X11 은 그 자리 교체, Wayland 는 먼저 Ctrl+C 로 복사 → 결과는 클립보드)"
  fi
  if [ "$fail" != 0 ]; then echo "  ✗ 일부 단계 실패 — 위 ✗ 줄을 처리한 뒤 같은 설치 한 줄을 다시 실행하세요(다시 실행해도 안전)"; exit 1; fi
  exit 0
fi
if [ "${1:-}" = menubar ]; then register_menubar || exit 1; exit 0; fi
if [ "${1:-}" = mcp ]; then register_mcp; exit 0; fi
if [ "${1:-}" = hotkey ]; then register_hotkey || exit 1; exit 0; fi
backup() {  # backup <설치위치> : 링크가 아닌 기존 파일은 .bak-시각 으로 보존
  mkdir -p "$(dirname "$1")"
  if [ -e "$1" ] && [ ! -L "$1" ]; then mv "$1" "$1.bak-$(date +%Y%m%d%H%M%S)"; echo "백업: $1"; fi
}
link() {  # link <원본> <설치위치>
  backup "$2"; ln -sfn "$1" "$2"; echo "링크: $2 -> $1"
}
chmod +x "$A/prompt-improver/pi-edit" "$A/review-gate/codex-review-gate.py" 2>/dev/null || true
if [ "$WIN" = 1 ]; then
  # 래퍼는 경로를 큰따옴표 안에 문자열로 박는다 → 셸·cmd 가 해석하는 문자(" % $ ` 와 개행)가 설치 경로에 있으면 만들지 않는다
  case "$A" in
    *[\"%\$\`]*|*"
"*) echo "✗ 설치 경로에 \" % \$ \` 또는 개행이 있어 Windows 래퍼를 만들 수 없다: $A — 이 문자가 없는 폴더로 옮긴 뒤 다시 실행" >&2; exit 1 ;;
  esac
  # Git Bash 의 ln -s 는 기본적으로 복사본을 만든다 → 원본을 가리키는 래퍼로 SSOT 유지
  mkdir -p "$HOME/bin" "$HOME/.claude/prompt-improver" "$HOME/.claude/hooks"
  BASH_EXE=$(cygpath -w "$(command -v bash)")
  REPO_W=$(cygpath -w "$A")
  printf '#!/usr/bin/env bash\nexec "%s/prompt-improver/pi-edit" "$@"\n' "$A" > "$HOME/bin/pi-edit"; chmod +x "$HOME/bin/pi-edit"
  # Claude Code 는 Windows 에서 .exe/.cmd/.bat 만 직접 실행하므로 VISUAL 에는 이 .cmd 를 넣는다
  printf '@echo off\r\n"%s" "%s\\prompt-improver\\pi-edit" %%*\r\n' "$BASH_EXE" "$REPO_W" > "$HOME/bin/pi-edit.cmd"
  echo "래퍼: $HOME/bin/pi-edit, $HOME/bin/pi-edit.cmd -> $A/prompt-improver/pi-edit (bash: $BASH_EXE)"
  backup "$HOME/.claude/keybindings.json"; cp "$A/config/keybindings.json" "$HOME/.claude/keybindings.json"; echo "복사: ~/.claude/keybindings.json (변경 시 재실행; 기존 파일은 .bak 보존 → 직접 병합)"
  cp "$A/prompt-improver/instructions.md" "$HOME/.claude/prompt-improver/instructions.md"  # pi-edit 은 저장소 옆 파일을 우선 읽는다. 참고용 복사
  # Stop 훅은 python 으로 실행되므로 래퍼도 Python 파일이어야 한다(Codex 리뷰 지적). 저장소 원본을 __main__ 으로 실행
  backup "$HOME/.claude/hooks/codex-review-gate.py"
  printf 'import runpy, sys\nP = r"%s\\review-gate\\codex-review-gate.py"\nsys.argv[0] = P\nrunpy.run_path(P, run_name="__main__")\n' "$REPO_W" > "$HOME/.claude/hooks/codex-review-gate.py"
  echo "래퍼(py): ~/.claude/hooks/codex-review-gate.py -> $REPO_W\\review-gate\\codex-review-gate.py"
else
  link "$A/prompt-improver/pi-edit"              "$HOME/bin/pi-edit"
  link "$A/prompt-improver/instructions.md"      "$HOME/.claude/prompt-improver/instructions.md"
  link "$A/review-gate/codex-review-gate.py"     "$HOME/.claude/hooks/codex-review-gate.py"
  link "$A/config/keybindings.json"              "$HOME/.claude/keybindings.json"
fi
command -v perl >/dev/null && perl -MJSON::PP -e1 2>/dev/null && echo "  ✓ perl JSON::PP (pi-edit 의존)" || echo "  ✗ perl JSON::PP 없음 → pi-edit 이 settings·응답을 못 읽는다 (macOS·Git Bash 는 기본 포함)"
echo
echo "수동 병합 확인:"
if [ "$WIN" = 1 ]; then
  command -v python >/dev/null && python -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null && echo "  ✓ python 3.8+ (리뷰 게이트 의존)" || echo "  ✗ python 3.8+ 없음 → python.org 설치 후 PATH 확인 (리뷰 게이트)"
  grep -q 'codex-review-gate.py' "$HOME/.claude/settings.json" 2>/dev/null && ! grep -q '/usr/bin/python3' "$HOME/.claude/settings.json" 2>/dev/null && echo "  ✓ settings.json Stop 훅(Windows 명령)" || echo "  ✗ settings.json Stop 훅 → snippets/windows-claude-settings-stop-hook.json 병합 (macOS 용 /usr/bin/python3 명령은 Windows 에 없음)"
else
  grep -q 'codex-review-gate.py' "$HOME/.claude/settings.json" 2>/dev/null && echo "  ✓ settings.json Stop 훅" || echo "  ✗ settings.json Stop 훅 → snippets/claude-settings-stop-hook.json 병합"
fi
grep -q 'open_external_editor' "$HOME/.codex/config.toml" 2>/dev/null && echo "  ✓ codex config.toml 키" || echo "  ✗ codex config.toml → snippets/codex-config.toml 병합"
if [ "$WIN" = 1 ]; then
  grep -q 'pi-edit' "$HOME/.claude/settings.json" 2>/dev/null && echo "  ✓ settings.json env.VISUAL" || echo "  ✗ settings.json env.VISUAL → snippets/windows-claude-settings-env.json 병합 (값: $(cygpath -w "$HOME")\\bin\\pi-edit.cmd)"
else
  grep -q 'bin/pi-edit' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null && echo "  ✓ 셸 rc VISUAL" || echo "  ✗ ~/.zshrc(또는 ~/.bashrc) → snippets/zshrc.sh 추가"
fi
echo "적용: 새 터미널 탭에서 claude / codex 실행"
echo
if [ "${IMPROMPT_MCP:-1}" != 0 ]; then register_mcp; fi

#!/usr/bin/env bash
# Imprompt 전역 단축키(Linux): 데스크톱 환경의 사용자 단축키에 이 스크립트를 연결한다(예: GNOME 설정 → 키보드 → 사용자 지정 단축키).
#   권장 키 Super+Q — 데스크톱 단축키는 터미널에서도 가로채므로 터미널의 Ctrl+Q(pi-edit)와 겹치지 않게.
# X11(xclip·xdotool): 지금 활성 창에서 Ctrl+C 로 직접 복사해(다른 앱에 남은 PRIMARY 선택을 잘못 쓰지 않게) 개선 →
#   같은 창일 때만 Ctrl+V 로 교체, 끝나면 원래 클립보드(글자) 복원. 터미널·IDE 창에서는 Ctrl+C 가 실행 중 명령을 끊으므로 동작하지 않는다.
# Wayland(wl-clipboard): 활성 창·선택을 확인할 수 없어 사용자가 먼저 Ctrl+C 로 복사한 글만 개선하고, 결과는 클립보드에만 넣는다(자동 붙여넣기 없음).
# 실패하면 원문·클립보드를 건드리지 않고 알림(notify-send)만 띄운다.
set -u
D=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SRV=$D/prompt-improver/mcp/imprompt_mcp.py
PY=${IMPROMPT_PY:-$(command -v python3)}
TERMS='terminal|konsole|xterm|alacritty|kitty|wezterm|tilix|terminator|urxvt|rxvt|st-256color|foot|guake|yakuake|code|cursor|windsurf|jetbrains|ghostty|tabby|termius|waveterm|(^|[^a-z])zed([^a-z]|$)|term|shell|console'   # 마지막 3개: 목록에 없어도 이름에 term·shell·console 이 들어가면 터미널로 본다
# 사용자에게 보이는 문구(세 플랫폼 공통 — imprompt.lua·imprompt.ahk 와 같은 글). Windows 콘솔·ahk 인코딩 때문에 ASCII 만
MSG_PROGRESS="Refining prompt... (10-30s, keep this window focused)"
MSG_DONE="Prompt refined."
MSG_FAILED="Refinement failed: %s. Original text kept."
MSG_CANCELLED="Paste cancelled: window changed. Refined prompt is on the clipboard (Ctrl+V)."
MSG_BUSY="Refinement already in progress."
MSG_NO_SELECTION="Select the text to refine first."
MSG_UNKNOWN="unknown error"
MSG_WL_PROGRESS="Refining prompt... (10-30s)"
MSG_WL_DONE="Prompt refined. Result is on the clipboard (Ctrl+V)."
MSG_WL_NO_TEXT="Wayland: no text on the clipboard. Copy the text with Ctrl+C first."
MSG_WL_EMPTY="Wayland: copy the text with Ctrl+C first, then press the shortcut."
MSG_NO_WINDOW="Stopped: could not detect the active window."
MSG_NO_CLASS="Stopped: could not detect the window type (install xprop), to avoid interrupting a terminal."
MSG_TERMINAL="Not available in terminal or IDE windows (Ctrl+C would interrupt running commands)."
MSG_NON_TEXT="Stopped: the clipboard holds non-text data (left untouched)."
MSG_NO_BACKUP="Stopped: could not back up the clipboard."
failed() { local r; r=$(printf '%s' "$1" | head -1 | sed -E 's/^Refinement failed:[[:space:]]*//; s/\.?[[:space:]]*Original text kept\.?$//; s/\.$//')
           printf "$MSG_FAILED" "${r:-$MSG_UNKNOWN}"; }   # 실패 원인 한 구절: 개선기 stderr 첫 줄에서 원인만
note() { command -v notify-send >/dev/null 2>&1 && notify-send -t "${2:-3000}" "Imprompt" "$1"; }
# 중복 실행 잠금: 단축키를 누를 때마다 새 프로세스가 뜨므로, 클립보드를 건드리기 전부터 마지막 복원까지 하나만 돌게 한다(연타 시 중복 붙여넣기 방지)
# 잠금 폴더: XDG_RUNTIME_DIR(사용자 전용), 없으면 ~/.cache/imprompt(700) — 모두가 쓰는 /tmp 에는 두지 않는다(다른 사용자가 미리 만든 파일·링크로 막거나 가로채지 못하게)
LOCKDIR=${XDG_RUNTIME_DIR:-$HOME/.cache/imprompt}
[ -n "${XDG_RUNTIME_DIR:-}" ] || { mkdir -p "$LOCKDIR" && chmod 700 "$LOCKDIR"; } 2>/dev/null
LOCK=$LOCKDIR/imprompt-hotkey-$(id -u).lock
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"; flock -n 9 || { note "$MSG_BUSY"; exit 0; }
else
  [ -n "$(find "$LOCK.d" -maxdepth 0 -mmin +10 2>/dev/null)" ] && rmdir "$LOCK.d" 2>/dev/null   # 강제 종료로 남은 10분 넘은 잠금
  mkdir "$LOCK.d" 2>/dev/null || { note "$MSG_BUSY"; exit 0; }
  trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
fi
improve() { err=$(mktemp); out=$(printf '%s' "$1" | "$PY" "$SRV" --improve --host "${IMPROMPT_HOST:-claude}" 2>"$err"); rc=$?
            msg=$(head -1 "$err"); rm -f "$err"; return $rc; }

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  # 글자 형식으로 읽힐 때만 진행(이미지 등은 개선기로 넘기지도, 덮어쓰지도 않는다)
  text=$(wl-paste -n -t text 2>/dev/null) || { note "$MSG_WL_NO_TEXT"; exit 0; }
  [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || { note "$MSG_WL_EMPTY"; exit 0; }
  note "$MSG_WL_PROGRESS" 30000
  if improve "$text"; then printf '%s' "$out" | wl-copy 9>&- && note "$MSG_WL_DONE" 5000
  else note "$(failed "$msg")" 6000; fi
  exit 0
fi

win=$(xdotool getactivewindow 2>/dev/null) || { note "$MSG_NO_WINDOW"; exit 0; }
# 창 종류: 새 xdotool 의 getwindowclassname, 없으면(Ubuntu·Debian 의 3.20160805) 표준 xprop WM_CLASS. 둘 다 모르면 Ctrl+C 를 보내지 않고 중단
cls=$(xdotool getactivewindow getwindowclassname 2>/dev/null) || cls=""
[ -n "$cls" ] || cls=$(xprop -id "$win" WM_CLASS 2>/dev/null | sed -n 's/^WM_CLASS[^=]*= *//p')
[ -n "$cls" ] || { note "$MSG_NO_CLASS"; exit 0; }
if printf '%s' "$cls" | grep -qiE "$TERMS"; then note "$MSG_TERMINAL"; exit 0; fi
# 클립보드 백업: 형식 목록(TARGETS)을 먼저 본다. 비어 있으면 잃을 것 없음, 글자 형식이면 백업, 글자가 아닌 것(이미지 등)만 있으면
# 백업할 수 없으므로 아무것도 건드리지 않고 중단(클립보드를 비우면 사용자의 데이터가 사라진다)
targets=$(xclip -o -selection clipboard -t TARGETS 2>/dev/null)
saved=""
if [ -n "$targets" ]; then
  printf '%s\n' "$targets" | grep -qE '^(UTF8_STRING|STRING|TEXT|text/plain)' \
    || { note "$MSG_NON_TEXT"; exit 0; }
  saved=$(xclip -o -selection clipboard 2>/dev/null && printf x) || { note "$MSG_NO_BACKUP"; exit 0; }
  saved=${saved%x}                                                                       # 끝 줄바꿈까지 보존
fi
# 클립보드에 쓰는 xclip·wl-copy 는 내용을 들고 백그라운드에 남는다 → 잠금 핸들(fd 9)을 물려주지 않게 9>&- (안 그러면 끝나도 잠금이 안 풀림)
restore() { printf '%s' "$saved" | xclip -selection clipboard 9>&-; }
printf '' | xclip -selection clipboard 9>&-
xdotool key --clearmodifiers ctrl+c
text=""
for _ in $(seq 1 15); do text=$(xclip -o -selection clipboard 2>/dev/null); [ -n "$text" ] && break; sleep 0.05; done
if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then restore; note "$MSG_NO_SELECTION"; exit 0; fi
note "$MSG_PROGRESS" 30000
if ! improve "$text"; then restore; note "$(failed "$msg")" 6000; exit 0; fi
printf '%s' "$out" | xclip -selection clipboard 9>&-
if [ "$(xdotool getactivewindow 2>/dev/null)" = "$win" ]; then
  xdotool key --clearmodifiers ctrl+v; sleep 0.6; restore; note "$MSG_DONE" 1500
else
  note "$MSG_CANCELLED" 5000
fi

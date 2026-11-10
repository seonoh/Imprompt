#!/usr/bin/env bash
# 원라인 설치: 저장소를 ~/.local/share/Imprompt 로 받고(있으면 갱신 — 예전 ~/Desktop/Imprompt 설치는 그 자리 갱신) 릴리스 커밋(또는 태그)을 checkout 한 뒤 install.sh 실행. macOS·Linux·Git Bash 공통.
#   공식 안내 명령은 커밋 SHA 주소 + IMPROMPT_COMMIT 쌍이다(docs/index.html·README 참고). <SHA> 는 릴리스 커밋의 40자 SHA:
#   curl -fsSL https://raw.githubusercontent.com/seonoh/Imprompt/<SHA>/bootstrap.sh | IMPROMPT_COMMIT=<SHA> bash -s -- mcp   MCP 등록만
#   IMPROMPT_COMMIT=<40자 소문자 hex>  그 커밋을 checkout 하고 rev-parse HEAD 가 정확히 같은지 확인(다르면 중단) — 태그가 옮겨져도 영향 없음
#   AI_TOOLS_DIR=~/다른경로  로 위치 변경.  AI_TOOLS_REPO=<주소> 는 시험용(기본값이 아니면 ⚠ 로 알림)
#   AI_TOOLS_REF=<태그·브랜치·커밋>  IMPROMPT_COMMIT 이 없을 때만 쓴다. 기본은 아래 DEFAULT_REF(저장소 VERSION 파일과 같아야 함). 개발자용 main 최신은 AI_TOOLS_REF=main
# 안전: 이미 받은 폴더의 origin 이 공식 주소가 아니면 중단. 태그는 --force 로 덮어쓰지 않는다 — 받아 둔 태그와 원격 태그가 가리키는 커밋이 다르면 중단.
set -e
DEFAULT_REF=v2.0.0
REF=${AI_TOOLS_REF:-$DEFAULT_REF}
COMMIT=${IMPROMPT_COMMIT:-}
REPO=${AI_TOOLS_REPO:-https://github.com/seonoh/Imprompt.git}
DIR=${AI_TOOLS_DIR:-}
fail() { echo "✗ $*"; exit 1; }
norm() { local u=${1%/}; u=${u%.git}; u=${u%/}; printf '%s' "$u" | tr 'A-Z' 'a-z'; }
is_official() {
  case "$(norm "$1")" in
    https://github.com/seonoh/imprompt|git@github.com:seonoh/imprompt|ssh://git@github.com/seonoh/imprompt) return 0 ;;
  esac
  return 1
}
FRESH=0   # 환경변수로 들어온 값을 쓰지 않는다(표식은 이 실행이 새로 받은 폴더에만)
command -v git >/dev/null || fail "git 이 필요합니다 — Ubuntu·Debian: sudo apt install git · Fedora: sudo dnf install git · Windows 는 Imprompt-Setup.cmd(자동 설치). 설치 뒤 같은 한 줄을 다시 실행"
# 새 Mac 의 /usr/bin/git 은 개발 도구(Command Line Tools)를 설치하라는 창만 띄우는 자리표시 프로그램이다 → 원인을 바로 안내
#   → 설치 창을 띄우고 화면 알림으로 무엇을 누를지 알린 뒤, 설치가 끝날 때까지 기다렸다가 이어서 진행한다(다시 붙여넣을 필요 없음, 최대 30분)
#   AI_TOOLS_CLT_POLL(초, 시험용)·AI_TOOLS_CLT_WAIT(최대 대기 초)
if [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ] && [ "$(command -v git)" = /usr/bin/git ] && ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  echo "… macOS 개발 도구(git·python3) 설치 창이 떴습니다 — 창에서 '설치'를 누르세요(5~10분). 끝나면 자동으로 이어서 진행합니다"
  osascript -e 'display notification "방금 뜬 창에서 \"설치\"를 눌러 주세요. 끝나면 자동으로 이어집니다(5~10분)." with title "Imprompt 설치"' >/dev/null 2>&1 || true
  poll=${AI_TOOLS_CLT_POLL:-10}; left=${AI_TOOLS_CLT_WAIT:-1800}
  until xcode-select -p >/dev/null 2>&1; do
    [ "$left" -gt 0 ] || fail "macOS 개발 도구 설치가 30분 안에 끝나지 않음 — 창에서 '설치'를 눌러 끝낸 뒤 같은 한 줄을 다시 실행하세요"
    sleep "$poll"; left=$((left - poll))
  done
  echo "✓ macOS 개발 도구 설치 확인 — 이어서 진행"
fi
case "$REF" in ''|-*|*[!A-Za-z0-9._/-]*) fail "버전(AI_TOOLS_REF) 값이 올바르지 않음: $REF" ;; esac
if [ -n "$COMMIT" ]; then
  case "$COMMIT" in *[!0123456789abcdef]*) fail "IMPROMPT_COMMIT 은 40자 소문자 hex(커밋 SHA)여야 함: $COMMIT" ;; esac
  [ "${#COMMIT}" = 40 ] || fail "IMPROMPT_COMMIT 은 40자 소문자 hex(커밋 SHA)여야 함: $COMMIT"
fi
if [ -n "${AI_TOOLS_REPO:-}" ]; then echo "⚠ 기본값 아닌 주소: AI_TOOLS_REPO=$AI_TOOLS_REPO"; fi
# 기본 위치 ~/.local/share/Imprompt: macOS 는 바탕화면(~/Desktop)이 보호 폴더라 터미널·Hammerspoon 이 읽을 때 '폴더 접근 허용' 창이 뜬다.
#   예전 기본 위치(~/Desktop/Imprompt)에 설치한 사용자는 그 폴더를 그대로 갱신한다 — macOS 는 바탕화면을 들여다보지 않고
#   Hammerspoon 설정(~/.hammerspoon/init.lua)의 Imprompt 블록이 그 경로를 가리킬 때만, Linux 는 그 폴더가 있을 때만
if [ -z "$DIR" ]; then
  DIR=$HOME/.local/share/Imprompt; old=$HOME/Desktop/Imprompt
  if [ ! -d "$DIR/.git" ]; then
    if [ "${AI_TOOLS_UNAME:-$(uname -s)}" = Darwin ]; then
      grep -q -F "$old/hotkey/imprompt.lua" "$HOME/.hammerspoon/init.lua" 2>/dev/null && [ -d "$old/.git" ] && DIR=$old
    elif [ -d "$old/.git" ]; then DIR=$old; fi
  fi
fi
mkdir -p "$(dirname "$DIR")" || fail "설치 위치를 만들지 못함: $(dirname "$DIR")"
echo "설치 위치: $DIR"
if [ -d "$DIR/.git" ]; then
  origin=$(git -C "$DIR" remote get-url origin 2>/dev/null) || fail "$DIR 의 origin 주소를 읽지 못함 — 설치 중단"
  if ! is_official "$origin" && [ "$(norm "$origin")" != "$(norm "$REPO")" ]; then
    fail "$DIR 의 origin 이 공식 주소(https://github.com/seonoh/Imprompt)가 아님: $origin — 설치 중단(폴더를 확인하거나 지우고 다시 실행)"
  fi
else git clone "$REPO" "$DIR" || fail "저장소를 받지 못함: $REPO (인터넷 연결·저장소 공개 여부 확인)"; FRESH=1; fi
if [ -n "$COMMIT" ]; then
  # 커밋 고정: 태그·브랜치 이름을 믿지 않고 그 커밋 SHA 만 checkout 한다(아래에서 HEAD 가 정확히 같은지 다시 확인)
  #   SHA 로 직접 받지 않는다: GitHub 는 포크에만 있는 커밋도 원 저장소 주소로 내주므로, 공식 저장소의 브랜치·태그에서 닿는 커밋만 받는다
  #   판정은 원격을 그대로 비춘 전용 이름 공간(refs/imprompt-official/*, --prune·강제 갱신)에서만 — 폴더에 심어 둔 로컬 태그·원격 추적 참조는 믿지 않는다
  git -C "$DIR" fetch --quiet --prune --no-tags origin '+refs/heads/*:refs/imprompt-official/heads/*' '+refs/tags/*:refs/imprompt-official/tags/*' || fail "git fetch 실패 — 설치 중단"
  git -C "$DIR" fetch --quiet origin || fail "git fetch 실패 — 설치 중단"
  git -C "$DIR" cat-file -e "$COMMIT^{commit}" 2>/dev/null || fail "커밋 $COMMIT 이 공식 저장소의 브랜치·태그에 없음(포크 커밋일 수 있음) — 설치 중단: 공식 안내 페이지·README 의 명령을 쓰세요"
  [ -n "$(git -C "$DIR" for-each-ref --contains "$COMMIT" refs/imprompt-official/heads/ refs/imprompt-official/tags/ 2>/dev/null)" ] || fail "커밋 $COMMIT 이 공식 저장소의 브랜치·태그에 없음(포크 커밋일 수 있음) — 설치 중단: 공식 안내 페이지·README 의 명령을 쓰세요"
  target=$COMMIT
else
  rc=0; git -C "$DIR" ls-remote --exit-code --tags origin "refs/tags/$REF" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then
    # 태그: 원격이 가리키는 커밋(주석 태그는 ^{} 로 벗긴 값)을 먼저 읽고, --force 없이 받는다 → 받아 둔 같은 이름 태그가 다른 커밋이면 git 이 거절
    want=$(git -C "$DIR" ls-remote --tags origin "refs/tags/$REF^{}" | cut -f1)
    [ -n "$want" ] || want=$(git -C "$DIR" ls-remote --tags origin "refs/tags/$REF" | cut -f1)
    git -C "$DIR" fetch --quiet origin "refs/tags/$REF:refs/tags/$REF" || fail "태그 $REF 를 받지 못함 — 이미 받은 같은 이름 태그가 원격과 다르면 변조 가능성이 있어 중단합니다"
    have=$(git -C "$DIR" rev-parse "refs/tags/$REF^{commit}")
    [ "$have" = "$want" ] || fail "태그 $REF 가 받아 둔 커밋($have)과 원격 커밋($want)이 다름 — 설치 중단"
    target=refs/tags/$REF
  elif [ "$rc" = 2 ]; then
    # 태그가 아님(브랜치·커밋) — 개발자용. 브랜치 이름이면 로컬(뒤처질 수 있음) 대신 방금 받은 원격 브랜치로 고정
    echo "⚠ $REF 는 릴리스 태그가 아님(개발자용) — 공식 배포는 태그 $DEFAULT_REF"
    git -C "$DIR" fetch --quiet origin || fail "git fetch 실패 — 설치 중단"
    target=$REF
    git -C "$DIR" rev-parse --verify -q "refs/remotes/origin/$REF" >/dev/null && target=origin/$REF
  else fail "원격 저장소에 연결하지 못함 — 설치 중단"; fi
fi
git -C "$DIR" -c advice.detachedHead=false checkout --quiet "$target" || fail "git checkout $target 실패(로컬 변경이 있으면 정리 후 다시) — 설치 중단"
head=$(git -C "$DIR" rev-parse HEAD) || fail "HEAD 커밋을 읽지 못함 — 설치 중단"
# checkout 은 같은 커밋이면 고친 파일을 그대로 둔다 → 추적 파일이 커밋과 다르면 실행하지 않는다(고정 커밋의 코드만 실행, 고친 내용은 보존)
chg=$(git -C "$DIR" status --porcelain --untracked-files=no) || fail "설치 폴더 상태를 확인하지 못함 — 설치 중단"
[ -z "$chg" ] || fail "$DIR 의 파일이 받은 커밋과 다릅니다(직접 고친 내용은 그대로 둠) — 설치 중단: 고친 내용을 정리하거나 폴더를 지우고 다시 실행"
if [ -n "$COMMIT" ]; then
  [ "$head" = "$COMMIT" ] || fail "checkout 한 커밋($head)이 요청한 커밋($COMMIT)과 다름 — 설치 중단"
  echo "버전 고정: 커밋 $head"
else echo "버전 고정: $REF (커밋 $head)"; fi
# 설치기가 새로 받은 폴더에만 표식(.git/imprompt-installed)을 남긴다 — 완전 제거(remove)는 이 표식이 있는 폴더만 지운다(개발용 저장소 보호)
#   표식에는 받은 커밋을 적는다 — remove 는 HEAD 가 이 커밋 그대로일 때만 지운다(다시 설치·업데이트하면 새 커밋으로 갱신)
if [ "$FRESH" = 1 ] || [ -f "$DIR/.git/imprompt-installed" ]; then printf 'installed-by=bootstrap.sh\ncommit=%s\n' "$head" > "$DIR/.git/imprompt-installed"; fi
# 인자(mcp 등)는 install.sh 로 넘긴다. stdin 은 끊는다: curl | bash 로 돌 때 남은 파이프를 설치 단계가 읽지 않게
exec bash "$DIR/install.sh" "$@" < /dev/null

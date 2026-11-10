#!/usr/bin/env bash
# Imprompt 한 줄 설치(일반 사용자용, macOS·Linux): 터미널에 붙여넣기 — 릴리스 커밋 SHA 로 고정된 주소를 쓴다(main 최신·옮겨질 수 있는 태그 아님)
#   curl -fsSL https://raw.githubusercontent.com/seonoh/Imprompt/<SHA>/get.sh | IMPROMPT_COMMIT=<SHA> bash     (<SHA> = 릴리스 커밋 40자, 안내 페이지의 명령 그대로)
# = 같은 커밋의 bootstrap.sh use: 저장소를 ~/.local/share/Imprompt 로 받아(예전 ~/Desktop/Imprompt 설치는 그 자리) 그 커밋을 checkout(HEAD 가 정확히 같은지 검증) → 필요한 프로그램(Hammerspoon)·엔진 CLI(Claude Code) 설치
#   → MCP 등록 → 전역 단축키(아무 앱에서 블록 → Ctrl+Q) → 메뉴바 → 로그인 안 됐으면 브라우저 승인 창.
# 릴리스 태그는 저장소 VERSION 파일과 같아야 한다(README 하단 "릴리스 절차", 테스트가 일치 확인).
# IMPROMPT_COMMIT 이 없으면(개발·시험) 아래 DEFAULT_REF 태그를 쓰고, 태그가 가리키는 커밋을 출력한다.
# 덮어쓰기(시험·개발용): AI_TOOLS_REF(버전; 개발자용 main 은 AI_TOOLS_REF=main) · AI_TOOLS_DIR(받는 위치) · AI_TOOLS_REPO · IMPROMPT_BOOTSTRAP_URL — 기본값이 아닌 주소는 ⚠ 로 알린다
set -euo pipefail
DEFAULT_REF=v2.0.1
REF=${AI_TOOLS_REF:-$DEFAULT_REF}
COMMIT=${IMPROMPT_COMMIT:-}
if [ -n "$COMMIT" ]; then
  case "$COMMIT" in *[!0123456789abcdef]*) echo "✗ IMPROMPT_COMMIT 은 40자 소문자 hex(커밋 SHA)여야 함: $COMMIT"; exit 1 ;; esac
  [ "${#COMMIT}" = 40 ] || { echo "✗ IMPROMPT_COMMIT 은 40자 소문자 hex(커밋 SHA)여야 함: $COMMIT"; exit 1; }
fi
if [ -n "${IMPROMPT_BOOTSTRAP_URL:-}" ]; then echo "⚠ 기본값 아닌 주소: IMPROMPT_BOOTSTRAP_URL=$IMPROMPT_BOOTSTRAP_URL"; fi
if [ -n "${AI_TOOLS_REPO:-}" ]; then echo "⚠ 기본값 아닌 주소: AI_TOOLS_REPO=$AI_TOOLS_REPO"; fi
if [ -n "$COMMIT" ]; then echo "커밋 고정: $COMMIT"
elif [ "$REF" != "$DEFAULT_REF" ]; then echo "⚠ 기본값 아닌 버전: $REF (공식 배포 태그는 $DEFAULT_REF)"; fi
url=${IMPROMPT_BOOTSTRAP_URL:-https://raw.githubusercontent.com/seonoh/Imprompt/${COMMIT:-$REF}/bootstrap.sh}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp" || { echo "✗ 설치 스크립트를 받지 못함: $url (인터넷 연결·저장소 공개 여부 확인)"; exit 1; }
AI_TOOLS_REF=$REF bash "$tmp" use < /dev/null                     # 같은 태그를 받아 쓰게 넘기고, 설치 결과 코드를 그대로 돌려준다

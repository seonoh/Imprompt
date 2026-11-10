# Imprompt 기능 목록표

바꾼 기능을 실제로 조작해 확인할 때 먼저 읽는 표다. 사용자 동작·진입 경로가 바뀌면 같은 PR에서 갱신한다.
근거: 2026-11-03 코드(`hotkey/`, `menubar/`, `prompt-improver/`, `install.sh`)와 README 확인. 직접 조작해 보지 않은 칸은 "추정"으로 표시했다.

## 1. 전역 단축키 개선 (macOS · Hammerspoon)
- **진입 경로**: 아무 앱에서 문장을 블록으로 선택 → **Ctrl+Q**. 설치 `./install.sh hotkey`(`~/.hammerspoon/init.lua`에 표식 블록). 코드 `hotkey/imprompt.lua`.
- **눌러 볼 것**: 메모 앱에서 짧은 문장 선택 → Ctrl+Q → 진행 패널("Refining prompt...") → 10~30초 뒤 선택 영역이 개선본으로 바뀌는지. 선택 없이 Ctrl+Q → 아무것도 안 바뀌는지. 끝난 뒤 클립보드가 원래 값으로 돌아오는지.
- **자동 완성 모드**: 되물을 수 없는 경로라 `prompt-improver/auto-mode.md` 를 규칙 뒤에 덧붙여 미정 사항을 권장안 `[가정]` 으로 확정하고, 남은 `[확인 필요]` 는 첫 번째 선택지로 바꾼다(`IMPROMPT_AUTO=0` 이면 예전 그대로). MCP 는 `[확인 필요]` 유지.
- **주의점**: 실제 개선은 로그인된 CLI 구독 사용량을 쓴다. 터미널·IDE(Terminal·iTerm2·Ghostty·VS Code·Cursor·JetBrains 등)에서는 Ctrl+Q를 앱에 그대로 넘긴다(아래 2번 개선기 동작). 개선 중 다른 창으로 옮기면 붙여넣지 않고 클립보드에만 둔다. 개선 중 클릭·타이핑 금지. 처음에는 '손쉬운 사용 → Hammerspoon' 허용이 필요하다.
- Windows(`hotkey/imprompt.ahk`, AutoHotkey v2)·Linux(`hotkey/imprompt-linux.sh`, 데스크톱 단축키 연결): 이 Mac에서 확인 못 함.

## 2. 입력창 개선기 (Claude Code·Codex 입력창 Ctrl+Q)
- **진입 경로**: `claude`/`codex` 입력창에 요청 입력 → **Ctrl+Q**(외부 편집기 = `~/bin/pi-edit`). 일반 설치(`use`)는 **macOS·Linux 의 Claude Code 만** 연결한다(`imprompt_mcp.py --editor-keys`: `~/.claude/keybindings.json` 병합 + settings.json `env.VISUAL`). Codex 입력창(`snippets/codex-config.toml`·`snippets/zshrc.sh`)과 Windows(Git Bash 래퍼)는 개발자 수동 설치(README) — Windows 일반 설치에서는 터미널의 Ctrl+Q 가 앱에 그대로 넘어가 아무 일도 하지 않는다.
- **눌러 볼 것**: 새 터미널 탭에서 요청 입력 → Ctrl+Q → 대기 애니메이션 → 입력창이 개선본으로 바뀌는지. 모호한 요청이면 질문 메뉴(↑↓·숫자·Esc 건너뛰기)가 뜨는지. 완료 후 `c`로 클립보드 복사. `*` 접두는 그대로 통과, `!`는 강제 개선. Claude 원복 `Ctrl+_`.
- **주의점**: 구독 사용량을 쓴다. 실패·90초 초과면 원문 유지 + ⚠ 한 줄(`~/.claude/prompt-improver/last-run.log`). 환경변수 `PI_ASK`·`PI_HISTORY`·`PI_CONTEXT`·`PI_ANIM` 등으로 동작이 바뀌므로 확인 전 현재 셸 값을 본다. 이미 열려 있는 세션은 VISUAL 변경을 반영하지 않을 수 있다(추정).

## 3. MCP 도구 `improve_prompt`
- **진입 경로**: `./install.sh mcp`로 claude·codex·gemini에 사용자 범위 등록 → CLI를 새로 열고 "improve_prompt로 개선해줘: …". 코드 `prompt-improver/mcp/imprompt_mcp.py`.
- **눌러 볼 것**: 토큰 0 점검 `imprompt_mcp.py --check`(설치·로그인 상태), `--status-json`, `--version`. 실제 호출 시 개선본 본문만 돌아오고 `[확인 필요]` 줄은 호출한 에이전트가 묻는지.
- **주의점**: 실제 호출은 구독 사용량을 쓴다. 같은 요청은 24시간 캐시(CLI 간 공유), `*` 접두·이미 구조화된 원문은 호출 없이 통과. 실패 시 재시도 없음(로그인 안 된 엔진은 건너뜀), 다른 업체 CLI 폴백은 `IMPROMPT_FALLBACK=1` 일 때만. 기록 `~/.imprompt/mcp.log`(원문 없음). `install.sh mcp`는 기존 `imprompt` 등록을 지우고 다시 등록한다.

## 4. 메뉴바 상태 아이콘 (macOS · Hammerspoon)
- **진입 경로**: `./install.sh menubar` → 메뉴바 연필 아이콘(툴팁 "Imprompt - idle"/"Imprompt - refining (N)"). 코드 `menubar/imprompt_menubar.lua`.
- **눌러 볼 것**: 아이콘 클릭 → 작업 목록(Running/No active jobs, 최근 작업 최대 8개), "Agent in use", Accounts(엔진별 Signed in/out), Refresh Account Status, Open Job History. 개선 중(MCP·전역 단축키)에만 두 별이 번갈아 반짝이는지.
- **주의점**: 작업 목록은 `~/.imprompt/jobs/<id>.json` 기준이라 입력창 Ctrl+Q(pi-edit)는 나오지 않는다. 계정 하위 메뉴의 **Sign Out...**은 그 CLI의 실제 로그인을 지우므로 시험으로 누르지 않는다. Sign In은 브라우저 승인을 연다. 600초 넘게 running이면 '응답 없음'(❔). 작업 목록에 원문 앞부분이 보이므로 스크린샷을 공유할 때 주의.

## 4-1. 사용자 지침 (Custom Rules — 메뉴바·트레이 · CLI)
- **진입 경로**: macOS 메뉴바 아이콘 메뉴 하단 `Custom rules: on (N chars)`/`off` 상태 줄, **Edit Custom Rules...**, **Import From My Agent Rules...**. Windows 는 트레이 메뉴에 같은 항목. **Edit Custom Rules...** 는 편집 창(왼쪽 목록 + 이름·내용 칸, + New rule·Add/Save·Delete·Close)을 연다 — macOS `menubar/rules-editor.html`(Hammerspoon 웹뷰), Windows AutoHotkey 창. 항목은 같은 파일 안의 `## 이름` 제목으로 나뉘고, 첫 제목 앞 예전 글은 `My rules` 로 불러온다. Linux 는 아이콘이 없어 편집 창도 없다(파일 직접 편집). 터미널 `python3 prompt-improver/mcp/imprompt_mcp.py --rules-path|--rules-show|--rules-init|--rules-items [--tsv]|--rule-put --in F|--rule-del --in F|--import-rules [--apply]`. 저장 `~/.imprompt/custom-rules.md`(전역 1벌), 구획 문구 `prompt-improver/custom-rules-wrap.md`.
- **눌러 볼 것**: Edit Custom Rules... → 편집 창이 뜨고 기존 지침이 목록에 불러와지는지 → + New rule → 이름·내용 입력 → Add → 목록에 생기고 `custom-rules.md` 에 `## 이름` 으로 저장·`.bak` 생성 → 빈 이름·같은 이름은 아래 안내 줄에 쉬운 말로 막히는지 → 고르고 고쳐 Save → Delete 는 확인 창(Delete/Cancel) 뒤에만 지워지는지 → 메뉴를 다시 열면 상태 줄이 `on (N chars)`로 바뀌는지 → Ctrl+Q 개선 결과에 선호가 반영되는지. Import From My Agent Rules... → 몇 초~1분 뒤 초안이 편집기에 열리고 적용 여부 대화상자(Apply/Cancel)가 뜨는지 → Apply 후 `--rules-show`에 반영, Cancel이면 `custom-rules.md` 불변. `PI_CUSTOM=0`이면 반영되지 않는지.
- **주의점**: Import 는 CLI 호출 1회(구독 사용량)이고 원본 지침 파일이 기본 엔진 회사로 전송된다. 2,000자 초과분은 잘린다(`--rules-show`에 경고). 2차 개선에만 적용되고 질문 메뉴(1차)에는 영향 없음. 지침이 기본 규칙의 틀·보안 줄과 충돌하면 기본 규칙이 이긴다. 웹 버전(`web/imprompt-web.html`)에는 적용되지 않는다. 메뉴 클릭 동작은 Hammerspoon·AutoHotkey 실기기에서만 확인 가능(이 문서 작성 시점엔 정적 검사만 통과).

## 5. Codex 리뷰 게이트 (Claude Code Stop 훅)
- **진입 경로**: 자동 — 코드를 바꾼 턴이 끝나면 실행. 연결 `review-gate/codex-review-gate.py` → `~/.claude/hooks/`, `snippets/claude-settings-stop-hook.json`.
- **눌러 볼 것**: 코드 변경 턴 종료 시 결과 한 줄(✓/✗/⚠). 판정 기록 `~/.claude/gate-log/review.jsonl`.
- **주의점**: 개발자 수동 설치 전용(한 줄 설치 `use` 는 넣지 않음, Windows 실기기 미검증). 턴마다 1~3분, Codex 구독 사용량을 쓴다. **실패하면 막지 않는다(fail-open)**: Codex 미설치·미로그인·시간 초과·해석 불가면 `⚠ … 막지 않고 통과` 를 띄우고 검토 완료로 기록하지 않아 다음 Stop 에 다시 시도한다. 보내는 것: README '어느 문장이 어느 회사로 가나요'. 끄기 `touch ~/.claude/codex-gate.off`.

## 6. 웹 버전
- **진입 경로**: `web/imprompt-web.html`(claude.ai 아티팩트로 게시 — 보는 사람의 claude.ai 계정으로 모델을 부르는 기능(window.claude 샘플링)이 켜진 아티팩트여야 한다) → 요청 붙여넣기 → **개선하기** → 복사.
- **눌러 볼 것**: 개선 결과가 나오고 복사되는지.
- **주의점**: 보는 사람의 claude.ai 사용량을 쓴다. 규칙은 `instructions.md`와 같은 내용을 내장 — 규칙을 바꾸면 둘 다 갱신. 공개 링크는 두지 않는다(선택 기능 — 직접 아티팩트로 올려 쓴다).

## 7. 설치·점검 도구
- `./install.sh` / `install.sh use`(MCP + 단축키 + 메뉴바 한 번에, Hammerspoon 없으면 공식 GitHub 릴리스를 해시·서명·공증 확인 후 ~/Applications 에 설치, 실패할 때만 Homebrew) / `install.ps1`(Windows). 실행하면 사용자 설정(`~/.hammerspoon/init.lua`, MCP 등록, 링크)을 다시 쓴다 — 기존 파일은 `.bak-시각`으로 보존.

## 4-2. Windows 로그인·엔진 선택 (트레이 Sign in... · Ctrl+Q 실패 안내)
- **진입 경로**: Windows 트레이 아이콘(앱 아이콘) 우클릭 → **Sign in...**(로그인 안 된 엔진의 로그인 명령을 보이는 콘솔 창으로 연다 — `imprompt_mcp.py --sign-in [엔진]`). Ctrl+Q 실패 원인이 로그인이면 툴팁 대신 `Sign in required for <engine>. Open sign-in now?` 대화상자(Yes → 같은 로그인 창).
- **엔진 선택**: 설치 때 `hotkey.ini` 의 `host=` 는 로그인된 엔진 우선(claude → codex → gemini). 실행 중에도 로그인 안 된 엔진은 '시도'로 치지 않고 다음 로그인된 엔진으로 넘어간다(원문이 모델로 간 적 없음). 실제로 호출해 실패한 경우의 다른 업체 폴백은 `IMPROMPT_FALLBACK=1` 일 때만.
- **눌러 볼 것(실제 Windows)**: Ctrl+Q 를 손을 늦게 뗀 채/Ctrl+Alt 조합으로 눌러도 선택 글이 `c` 로 덮어써지지 않는지 · 트레이 메뉴에 표준 항목(Edit Script 등) 없이 항목+Exit 만 있는지 · 로그아웃 상태에서 Ctrl+Q → 대화상자 → Yes → 로그인 창 · 새 터미널에서 `claude` 가 되는지(사용자 PATH 에 `%USERPROFILE%\.local\bin`).

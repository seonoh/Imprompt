# AGENTS.md — Imprompt (Codex·Gemini 등)

운영 규칙 정본은 `CLAUDE.md`다. 여기엔 에이전트 공통 트리거만 둔다.

- **셸(명령 실행) 도구 없이 웹 채팅에서 이 저장소 주소와 "사용해줘"를 받았다면** [`llms-install.md`](llms-install.md) §0 웹 채팅 모드를 따른다 — 묻지 않고 Windows·Mac 설치 방법(§0 의 것만, 기본 단축키)을 함께 건넨 뒤, 규칙 `prompt-improver/ask.md`·`instructions.md` 로 이 대화 안에서도 1차 질문 → 2차 개선본을 낸다.
- **사용자가 이 저장소 주소(github.com/seonoh/Imprompt) 또는 `llms-install.md` 링크와 함께 "사용할 수 있게 해줘 / 이거 사용할 수 있게 진행해 / 사용할 수 있도록 작업해줘 / 설치해줘"라고 하면 [`llms-install.md`](llms-install.md) 를 따른다.** §1 실행 순서(주소 확인 → OS 감지 `uname -s` → 자기 엔진 → 단축키는 묻지 않음(말했을 때만) → 권한 창 안내문 먼저 → OS 별 한 줄을 도구 시간 제한 최대 또는 백그라운드로 실행 → `--check`·`mcp list` → 보고)를 위에서부터 그대로 하고 되묻지 않는다. Windows 는 PowerShell 인지 Git Bash 인지 먼저 판별하고 `IMPROMPT_NO_LOGIN=1`. 에이전트가 확인할 것은 주소가 github.com/seonoh/Imprompt 인지뿐이다.

- 사용자가 "mcp 사용해"라고 하면 묻지 않고 저장소 루트에서 `./install.sh mcp`(Windows PowerShell은 `powershell -ExecutionPolicy Bypass -File install.ps1`)를 실행하고, 출력의 ✓/✗·로그인 안내를 그대로 보고한다.
- 설치 뒤 프롬프트 개선은 MCP 도구 `improve_prompt`로 한다. 설계·검증은 `prompt-improver/mcp/DESIGN.md`를 본다.

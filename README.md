<p align="center">
  <img src="assets/icon/imprompt-icon-rounded.png" width="88" alt="Imprompt 아이콘">
</p>

<h1 align="center">Imprompt</h1>

<p align="center">
  <b>대충 쓴 요청을 지시문으로 바꿉니다.</b><br>
  아무 앱에서 문장을 선택하고 Ctrl+Q. 10~30초 뒤 그 자리에서 교체됩니다.<br>
  내가 쓰는 Claude, ChatGPT, Gemini 구독으로 동작합니다. 추가 요금, API 키, 서버가 없습니다.
</p>

<p align="center">
  <img src="docs/guide/img/demo.gif" width="100%" alt="TextEdit에서 '로그인 기능 붙여줘'를 선택하고 Ctrl+Q를 누르면 진행 표시 뒤 같은 자리가 지시문으로 바뀌는 시연">
</p>

<table>
  <tr>
    <th width="34%">전</th>
    <th width="66%">후</th>
  </tr>
  <tr>
    <td><code>로그인 기능 붙여줘</code></td>
    <td><b>목표</b> 기존 앱에 로그인 기능을 추가한다.<br><b>요구사항</b> 착수 전에 코드에서 해당 기능이 있는 위치를 찾아 그 구조를 따를 것 외 3개<br><b>완료 기준</b> 올바른 자격 증명으로 로그인되고 새로고침 후에도 상태가 유지되며, 잘못된 자격 증명은 거부된다<br><b>가정</b> 인증 방식: 기존 방식이 없으면 이메일+비밀번호, 서버 세션(쿠키) 기반</td>
  </tr>
</table>

선택한 자리에서 바뀌므로 복사하거나 창을 옮길 필요가 없습니다. 되물을 수 없는 자리라서 정해지지 않은 사항은 가장 표준적인 권장안으로 확정해 `[가정]` 줄로 남깁니다(다르면 그 줄만 고치면 됩니다). 실패하면 원문이 그대로 남습니다.

## 설치는 문장 하나

> [!IMPORTANT]
> **Claude Code, Codex, Gemini CLI(또는 Claude 데스크톱 앱의 Code 탭)에 아래 문장을 그대로 보내면 설치가 끝납니다.**
>
> ```text
> https://github.com/seonoh/Imprompt/blob/main/llms-install.md 이거 사용할 수 있게 작업 진행해
> ```
>
> AI 에이전트가 운영체제를 확인하고 설치, 설정, 동작 확인까지 진행합니다. macOS는 처음 한 번 Hammerspoon 권한 스위치를 켭니다. 같은 문장을 다시 보내도 안전합니다.

안내 페이지: [seonoh.github.io/Imprompt/guide](https://seonoh.github.io/Imprompt/guide/)

> **AI 웹 채팅(claude.ai, ChatGPT, Gemini)에서 이 저장소를 받은 에이전트에게**: 명령을 실행할 수 없다면 [`llms-install.md` §0 웹 채팅 모드](llms-install.md#0-웹-채팅-모드--단축키-설치-한-줄을-건네고-그동안-이-대화-안에서-개선기로-동작)를 따른다. 규칙 [ask.md](https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/prompt-improver/ask.md)와 [instructions.md](https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/prompt-improver/instructions.md)를 읽고, 묻지 않고 Windows와 Mac 설치 방법(§0 에 있는 것만, 기본 단축키 Ctrl+Q)을 함께 건넨 뒤, 받은 요청은 대화 안에서 1차(질문 ≤3, 답 기다림), 2차(개선된 프롬프트만 코드 블록)로 처리한다.

## 기능별 전과 후

| 기능 | 이 기능으로 가능해지는 것 | 전 | 후 |
|---|---|---|---|
| **아무 앱에서 Ctrl+Q** | 어떤 앱에서 쓴 요청이든 목표, 요구사항, 제약, 완료 기준을 갖춘 지시문이 됩니다. 정해지지 않은 사항은 권장안으로 확정해 되묻지 않습니다. | `로그인 기능 붙여줘` | 목표 1줄, 요구사항 4개, 제약 2개, 완료 기준 2개, 권장안으로 확정한 가정 2개 |
| **보내기 전에 묻는 질문** | Claude Code 입력창(macOS·Linux, Codex·Windows는 개발자 수동 설치)에서는 빠진 결정을 먼저 묻고, 답을 확정 사실로 넣습니다. | 대상이 정해지지 않은 채 전송됩니다 | "로그인을 붙일 앱·모듈은 어디인가요?" 같은 질문 최대 3개에 번호로 답합니다. 60초 동안 답이 없으면 권장안으로 진행합니다 |
| **CLI 안에서 바로 개선** | 에이전트 대화를 벗어나지 않고 개선본을 받습니다. 같은 요청은 24시간 동안 다시 호출하지 않습니다. | 다른 창에서 다듬은 문장을 복사해 붙여넣습니다 | `improve_prompt로 개선해줘: 로그인 붙여줘` |
| **내 선호 한 번 등록** | 답변 언어, 출력 형식, 검증 습관, 금지 사항을 한 번 적으면 Ctrl+Q, 입력창, MCP 개선본에 모두 반영됩니다. | 요청할 때마다 같은 조건을 덧붙입니다 | Edit Custom Rules에 한 번 저장합니다. 기존 CLAUDE.md, AGENTS.md, GEMINI.md에서 가져올 수도 있습니다 |

## 입력하고 Ctrl+Q. 끝

<img src="docs/guide/img/menubar.jpg" width="340" align="right" alt="메뉴바의 연필 아이콘을 누르면 열리는 Imprompt 메뉴">

나머지는 메뉴바 연필 아이콘(Windows는 작업 표시줄 ^ 안)에 있습니다.

- **단축키 바꾸기**: Hotkey. Ctrl+Q를 쓰는 앱이 있으면 다른 키로 바꿉니다.
- **로그인 상태**: Accounts(Windows는 Sign in...). 엔진별 로그인 상태를 보고 바로 로그인합니다.
- **지우기**: Uninstall Imprompt. Windows는 설정, 앱, 설치된 앱, Imprompt, 제거도 됩니다.

문제가 해결되지 않으면 출력의 ✗ 줄을 [Issues](https://github.com/seonoh/Imprompt/issues)에 남겨 주세요. 보안 문제는 [SECURITY.md](SECURITY.md).

<br clear="right">

## 에이전트가 없다면

- **Windows**: [`Imprompt-Setup.cmd` 받기](https://github.com/seonoh/Imprompt/releases/download/v2.0.0/Imprompt-Setup.cmd), 더블클릭. "Windows의 PC 보호" 창이 뜨면 **추가 정보, 실행**(서명되지 않은 설치 파일에 표시되는 경고, [내용 미리 보기](docs/Imprompt-Setup.cmd)). 관리자 권한은 필요 없습니다. 그 뒤로는 권한 창 '예'와 브라우저 로그인 승인뿐입니다(AI 프로그램이 하나도 없을 때만 맨 처음 구독 번호 하나).
- **Mac**: 터미널에 아래 "한 번에 쓰기"의 macOS 한 줄을 붙여넣습니다. 그 뒤로는 뜨는 창만 누릅니다: 새 Mac이면 개발 도구 '설치'(끝나면 저절로 이어짐), AI 프로그램이 하나도 없을 때만 구독 번호 하나, Hammerspoon 켜기, 브라우저 로그인 승인. Hammerspoon은 Homebrew 없이 공식 릴리스에서 받아 해시, 서명, 공증을 확인한 뒤 설치합니다.
- **웹 채팅만 쓴다면**: claude.ai나 ChatGPT에 `https://github.com/seonoh/Imprompt 사용해줘`를 보내면 Windows 설치 파일 링크와 Mac 설치 명령을 함께 안내하고, 그 대화 안에서 프롬프트를 다듬습니다.

---

## 설치·사용 방식
| | AI 에이전트에게 맡기기 | 한 줄 설치 |
|---|---|---|
| 필요한 것 | Claude Code·Codex·Gemini CLI 또는 Claude 데스크톱 앱(로그인) | 터미널 |
| 설치 | 에이전트에 `https://github.com/seonoh/Imprompt/blob/main/llms-install.md 이거 사용할 수 있게 작업 진행해` | 아래 "한 줄 설치" 명령 붙여넣기 |
| 쓰는 법 | 아무 앱에서 블록 선택 → **Ctrl+Q**, CLI 입력창에서도 **Ctrl+Q** | 같음 |
| 비용 | 본인 구독(CLI 계정) 사용량 | 같음 |
| 사람이 할 일 | 실행 승인 1번 + 뜨는 권한 창 | 붙여넣기 1번 + 뜨는 권한 창·로그인 승인 |

## 한 번에 쓰기
**개발자가 아니어도 — 명령 한 줄**(설치 안내 페이지: https://seonoh.github.io/Imprompt/)
- macOS·Linux 터미널: `curl -fsSL https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/get.sh | IMPROMPT_COMMIT=f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e bash` (Linux 는 끝 요약이 알려 주는 대로 데스크톱 단축키를 한 번 연결)
- Windows PowerShell: `$env:IMPROMPT_COMMIT='f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e'; irm https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/get.ps1 | iex`

명령 속 40자 번호는 릴리스(`v2.0.0`)의 **커밋 SHA**다 — 주소와 `IMPROMPT_COMMIT` 가 같은 번호로 짝을 이루고, 설치기는 그 커밋을 받아 `HEAD` 가 정확히 같을 때만 설치한다. 내용이 번호로 정해지므로 태그가 옮겨져도(계정 탈취·실수) 바뀐 코드를 받지 않고, `main` 의 최신 변경도 받지 않는다. 번호는 안내 페이지·이 문서의 명령 그대로 쓴다(직접 고치지 않는다). 실행 전에 스크립트를 읽어 보고 싶다면 같은 주소를 브라우저로 열어 확인한 뒤 실행해도 된다. 개발자용 최신(`main`)은 `AI_TOOLS_REF=main` 으로만 받는다(공식 배포 아님). 환경변수로 저장소·설치기 주소를 바꾸면 `⚠ 기본값 아닌 주소: …` 가 출력된다. **공식 명령은 이 README·안내 페이지·Releases `v2.0.0` 에 있는 것뿐이다** — 블로그·메신저·포크 등 다른 곳에서 본 다른 번호는 포크 커밋일 수 있다(GitHub 는 포크 커밋도 같은 주소로 내준다). 설치기는 공식 저장소의 브랜치·태그에 없는 커밋이면 설치하지 않는다.

없으면 알아서 설치하는 것: 고른 구독의 엔진 CLI(Claude Code·Codex CLI·Gemini CLI, 공식 설치기)·macOS Hammerspoon·Windows Git·Python·AutoHotkey. 그다음 MCP 등록·전역 단축키(아무 앱에서 블록 → Ctrl+Q)·macOS 메뉴바, 로그인이 없으면 브라우저 승인 창까지(`install.sh use` · `install.ps1 use`). 준비물은 Claude·ChatGPT·Gemini **어느 구독이든 하나**(엔진 CLI 가 하나도 없으면 설치 중에 쓸 구독을 한 번 묻고 그 CLI 를 설치·로그인한다. 에이전트는 `IMPROMPT_ENGINE` 으로 자기 엔진을 넘긴다). 처음 설치는 macOS 5~10분·Windows 2~10분. 끝에 `요약(실제 상태)` 가 나온다(✓ 됨 · ✗ 고칠 것 · ! 사람이 할 한 가지). Windows 는 `%LOCALAPPDATA%\Imprompt` 에 설치(예전 바탕화면 설치본이 있으면 그 폴더를 갱신)하고, **관리자 권한이 아닌 일반 PowerShell** 에서 실행한다. 엔진은 로그인된 것 우선(claude → codex → gemini), 로그인 안 된 엔진은 건너뛴다. 회사 PC 는 보안 정책·프록시로 안 될 수 있다.

**AI CLI 를 쓰고 있다면**: 그 CLI 에 **`https://github.com/seonoh/Imprompt/blob/main/llms-install.md 이거 사용할 수 있게 작업 진행해`** → 에이전트가 [`llms-install.md`](llms-install.md) §1 실행 순서(OS 감지 → 권한 창 안내 → 한 줄 실행 → 동작 확인 → 보고, 질문 없음)대로 같은 설치를 한다.

사람이 할 일은 뜨는 창 누르기뿐: (새 Mac) 개발 도구 '설치', macOS '손쉬운 사용 → Hammerspoon' 켜기, Windows 권한 창 '예', 로그인 창 승인(이미 로그인돼 있으면 없음). 설치 중 단축키는 묻지 않는다(기본 Ctrl+Q, 메뉴바·트레이에서 변경, 미리 정하려면 `IMPROMPT_HOTKEY='Ctrl+Shift+Q'`). macOS·Linux 는 `~/.local/share/Imprompt` 에 설치한다(바탕화면은 macOS 보호 폴더라 '폴더 접근' 창이 떠서 피함, 예전 `~/Desktop/Imprompt` 설치본은 그 자리를 갱신).

## MCP로 쓰기 (claude·codex·gemini 공통, API 키 없음)
**처음 쓰는 사람 — 2단계**
1. 쓰고 있는 AI CLI(Claude Code·Codex·Gemini CLI)에 이 저장소 주소를 붙여넣고 말해요: **`https://github.com/seonoh/Imprompt 이 MCP 연결해줘`** — 에이전트가 [`llms-install.md`](llms-install.md) 절차대로 받고 등록한다.
2. CLI 를 새로 열고: **`improve_prompt로 개선해줘: 로그인 붙여줘`**

직접 설치(한 줄): macOS·Linux·Git Bash `curl -fsSL https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/bootstrap.sh | IMPROMPT_COMMIT=f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e bash -s -- mcp` · Windows PowerShell `$env:IMPROMPT_COMMIT='f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e'; irm https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/bootstrap.ps1 | iex` → macOS·Linux `~/.local/share/Imprompt`, Windows `%LOCALAPPDATA%\Imprompt` 에 받고 등록까지(`IMPROMPT_COMMIT` 없이 쓰면 릴리스 태그 `v2.0.0` 를 받고 그 태그가 가리키는 커밋을 출력한다 — 개발·시험용, 다른 태그는 `AI_TOOLS_REF=<태그>`). 이미 받은 폴더의 origin 이 공식 주소(github.com/seonoh/Imprompt)가 아니면 중단한다.

- 필요한 것: git, Python 3.8+, 그리고 claude·codex·gemini 중 하나에 **구독 계정 로그인**(API 키 없음). gemini 는 Google 이 무료 개인 등급의 CLI 사용을 막아 지원 등급 계정만 동작한다.
- 도구는 `improve_prompt` 하나(`prompt`, 선택 `context`). 개선본 본문만 돌려주고, `[확인 필요]` 줄은 호출한 에이전트가 사용자에게 묻는다.
- 비용: 부른 CLI의 구독 사용량(실측 claude 1회 입력 ~1.7k·출력 ~0.8k 토큰). 실패하면 엔진마다 한 번만 부르고 재시도는 없다(로그인 안 된 엔진은 원문을 보내기 전이라 건너뛰고 다음 로그인된 엔진으로). 다른 업체 CLI 로 넘기는 폴백은 `IMPROMPT_FALLBACK=1` 일 때만, 같은 요청은 24시간 캐시(CLI 간 공유)로 재호출 0회, `*` 접두·이미 틀을 갖춘 원문은 호출 없이 통과.
- 점검: `python3 ~/.local/share/Imprompt/prompt-improver/mcp/imprompt_mcp.py --check`(예전 설치는 `~/Desktop/Imprompt`) (설치·로그인 상태, 토큰 0). 기록 `~/.imprompt/mcp.log`(원문 없음). 설계·검증: `prompt-improver/mcp/DESIGN.md`.
- 이미 받아 둔 폴더 안에서는 에이전트에게 "mcp 사용해"라고만 해도 등록한다(`CLAUDE.md`·`AGENTS.md`).

## 어디서나 단축키 (CLI 안 열고 — 아무 앱에서 블록 → Ctrl+Q)
- 설치: macOS `./install.sh hotkey`(Hammerspoon 필요, 처음 한 번 '손쉬운 사용' 허용) · Windows `install.ps1 hotkey`(AutoHotkey v2) · Linux `hotkey/imprompt-linux.sh` 를 데스크톱 단축키에 연결(권장 Super+Q, 바꾸기·지우기도 데스크톱 설정에서). **Linux 차이**: X11(xclip·xdotool)은 선택 글을 그 자리에서 교체, Wayland(wl-clipboard)는 먼저 Ctrl+C 로 복사한 글을 개선해 **클립보드에만** 넣는다(직접 붙여넣기). 알림은 notify-send 가 있을 때만 보인다. 메뉴바·트레이는 없다.
- 쓰기: 메모·메신저·브라우저 등에서 문장을 블록으로 잡고 **Ctrl+Q** → 10~30초 뒤 그 자리에서 개선본으로 교체. **자동 완성 모드**: 되물을 곳이 없으므로 규칙 뒤에 `prompt-improver/auto-mode.md` 를 덧붙여 질문·`[확인 필요]` 대신 권장안을 `[가정]` 으로 확정하고, 그래도 남은 `[확인 필요]` 줄은 첫 번째(권장) 선택지의 `[가정]` 으로 바꾼다. 끄기 `IMPROMPT_AUTO=0`. MCP 는 호출한 에이전트가 사용자에게 묻도록 `[확인 필요]` 를 그대로 둔다. 터미널에서는 Ctrl+Q 가 그대로 넘어가 입력창 개선기가 동작(일반 설치는 macOS·Linux 의 Claude Code 만 연결 — Windows·Codex 입력창은 아래 개발자 수동 설치).
- 안전장치: 선택 없으면 무변경 · 실패하면 원문 유지 · 개선 중 다른 창으로 옮기면 붙여넣지 않고 클립보드에만 · 끝나면 원래 클립보드 복원. 엔진은 MCP 서버와 같음(`imprompt_mcp.py --improve`, 구독 CLI·캐시 공유, API 키 없음).
- 개선 중에는 다른 곳을 클릭·타이핑하지 않는다(붙여넣기는 그 순간의 커서 자리에 들어간다). 창이 바뀐 것만 알아채므로 **같은 창 안에서 탭·입력칸을 옮기면 그 자리에 붙여넣는다**. 원래 클립보드는 붙여넣고 약 0.6초 뒤 되돌리므로, 붙여넣기가 아주 느린 앱(원격 데스크톱·큰 문서)에서는 결과 대신 원래 클립보드 내용이 들어갈 수 있다 — 그때는 Cmd/Ctrl+Z 뒤 다시 시도.
- 메뉴바 상태 아이콘(macOS): `./install.sh menubar` → 우측 상단 연필 아이콘(앱 아이콘의 단색판)의 두 별이 개선 중(MCP·단축키)에만 번갈아 반짝이고, 누르면 작업 목록(작업별 진행 상태)·사용 중인 agent·계정 로그인/로그아웃(브라우저 승인, 터미널 안 띄움).
- **단축키 바꾸기**: macOS 는 우측 상단 연필 아이콘 → **Hotkey: ⌃Q** → **Change Hotkey...** → 새 조합을 누르면 끝(Esc 취소, 기본값으로 되돌리기 메뉴 있음). Windows 는 작업 표시줄 트레이 아이콘 → **Change Hotkey...** → 입력 칸에 새 조합을 누르고 Save. Cmd·Ctrl·Option(Alt)·Win 중 하나가 들어가야 하고, 복사·붙여넣기 같은 흔한 앱 단축키·OS 단축키·다른 앱이 쓰는 조합은 거절된다(그때는 기존 단축키 유지). 설정은 사용자별(macOS `~/.imprompt/settings.json`, Windows `%APPDATA%\imprompt\hotkey.ini` 의 `hotkey=`)이고 바로 적용된다. 터미널·IDE 안에서는 바꾼 조합도 그대로 앱에 넘긴다.
- **작업 내역**: 같은 아이콘 메뉴 → **Open Job History** → 최근 50건을 요약·표로 정리한 HTML 보고서가 브라우저로 열린다(`~/.imprompt/jobs-report.html`, 요청은 앞 40자 미리보기만). 직접 만들기: `python3 prompt-improver/mcp/imprompt_mcp.py --jobs-html`.

`web/imprompt-web.html` 은 claude.ai 아티팩트용 소스다(선택 — 공개 링크는 두지 않음, 원하면 직접 아티팩트로 올려 쓴다. 규칙은 `instructions.md`와 같은 내용을 내장 — 규칙을 바꾸면 둘 다 갱신).

## 전제 조건 (구독·로그인 필수)
이 도구는 모델을 직접 호출하지 않고 **설치된 CLI를 그대로 빌려 쓴다**. 따라서 각 CLI가 로그인돼 있어야 하고, 사용량은 그 계정의 구독·크레딧에서 차감된다.
| 기능 | 필요한 것 | 비고 |
|---|---|---|
| 프롬프트 개선 (Claude 입력창) | `claude` CLI 로그인 — Claude Pro/Max 구독 또는 API 키 | 1회당 입력 ~2.9k·출력 ~0.85k 토큰(opus 5.5·medium, 1차 질문 포함 실측 평균, API 환산 ≈$0.027) |
| 프롬프트 개선 (Codex 입력창) | `codex` CLI 로그인 — ChatGPT Plus/Pro 구독 또는 OpenAI API 키 | |
| Codex 리뷰 게이트 | `codex` CLI 로그인 | 코드 변경 턴마다 1~3분, 구독 사용량 소모 |
구독이 없는 환경에서는 동작하지 않는다(무료 모드 없음). 다른 에이전트로 바꾸려면 `pi-edit`의 엔진 분기에 해당 CLI 호출을 추가하면 된다.

### 다른 사용자가 설치할 때 — 계정 연결
이 저장소에는 자격증명이 전혀 없다. 각자 **자기 기기에서 자기 계정으로 CLI에 로그인**하면 그 인증을 pi-edit·리뷰 게이트가 그대로 쓴다. 계정·토큰을 남과 공유하지 않는다(개인 구독은 1인용).
| CLI | 로그인 | 확인 |
|---|---|---|
| Claude Code | `claude auth login` (브라우저에서 본인 claude.ai 계정 — Pro/Max 구독) 또는 API 키 `ANTHROPIC_API_KEY` | `claude auth status` → `"loggedIn": true` |
| Codex | `codex login` (브라우저에서 본인 ChatGPT 계정) 또는 `printenv OPENAI_API_KEY \| codex login --with-api-key` | `codex login status` → `Logged in using ChatGPT` |
순서: ① 각 CLI 설치·로그인 ② `bootstrap.sh`(또는 `install.sh`) ③ 새 터미널에서 `claude` → Ctrl+Q 동작 확인. 로그인이 없으면 Ctrl+Q 뒤 `Refinement failed: … Original text kept.` 한 줄이 뜨고 원문이 유지된다(`~/.claude/prompt-improver/last-run.log`에 인증 오류). 조직 단위로 쓰려면 Claude Team/Enterprise·OpenAI 팀 플랜의 좌석을 각자 받거나, 지출 한도를 건 API 키를 1인 1키로 발급한다.

## 어느 문장이 어느 회사로 가나요
Imprompt 자체 서버는 없다 — 문장은 **내 컴퓨터에서 내가 로그인한 엔진 CLI 로만** 간다. 엔진은 Imprompt 가 아니라 아래 업체의 서비스이고, 각 업체의 약관·개인정보 처리 방침이 적용된다.
| 쓰는 방법 | 보내지는 것 | 받는 곳 (내 구독 기준) |
|---|---|---|
| 전역 단축키(Ctrl+Q)·MCP `improve_prompt`, 엔진 `claude` | 블록으로 잡은(또는 도구에 넘긴) **문장 전체** + 호출한 에이전트가 붙인 `context` | Anthropic (Claude Code CLI, 도구·MCP·세션 기록 끔) |
| 같은 방법, 엔진 `codex` | 위와 같음 | OpenAI (Codex CLI, 빈 임시 폴더에서 실행) |
| 같은 방법, 엔진 `gemini` | 위와 같음 | Google (Gemini CLI) |
| 터미널 입력창 Ctrl+Q(`pi-edit`) | 입력창 문장 + **프로젝트 구조 요약**(세션 폴더의 최상위 항목 이름·스택 단서, 약 100~150토큰) + 짧은 후속 요청이면 **직전 대화 두 턴**(각 600자) + 질문 단계의 내 답 | 입력창을 연 쪽: Claude Code → Anthropic, Codex → OpenAI |
| 리뷰 게이트(Stop 훅, 개발자 수동 설치만) | 코드를 바꾼 턴의 **git diff·추적 안 된 새 파일**(파일당 최대 400KB) + git 밖에서 Edit/Write 한 내용 + 에이전트의 마지막 답(최대 4,000자). 비밀은 파일 이름·키 모양 패턴으로 가린다. Codex 는 빈 임시 폴더에서 셸·MCP 를 끄고 실행(저장소 파일을 직접 읽지 않음) | OpenAI (Codex) |
| 웹 버전 | 붙여넣은 요청 + 메모 칸 | Anthropic (claude.ai, 보는 사람 계정) |
| 내 지침(`~/.imprompt/custom-rules.md`, 있을 때만) | 개선(2차) 요청마다 **지침 전체**(최대 2,000자)가 함께 | 그 요청을 받는 엔진(위와 같음) |
| 지침 가져오기(`--import-rules`, 직접 실행할 때만) | `~/.claude/CLAUDE.md`·`AGENTS.md`·`GEMINI.md` **원문**(요약용) | 주 엔진 1곳 |
- **엔진 고르기**: MCP 는 등록한 CLI(`--host`)가 먼저, 단축키는 설치할 때 로그인된 엔진(claude → codex → gemini 순)이 기본이다. `IMPROMPT_ENGINE=claude|codex|gemini` 로 고정할 수 있다.
- **폴백**: 엔진마다 한 번만 부르고 재시도는 없다(로그인 안 된 엔진은 원문을 보내기 전이라 건너뛰고 다음 로그인된 엔진으로). 다른 업체 CLI 로 넘기는 폴백은 `IMPROMPT_FALLBACK=1` 일 때만 켜진다 — 기본값에서는 문장이 내가 고른(로그인한) 업체 밖으로 나가지 않는다.
- 비밀번호·API 키·고객 정보가 든 문장은 개선하지 않는 편이 안전하다. 문장 앞에 `*` 를 붙이면 호출 없이 그대로 통과한다. 리뷰 게이트는 `touch ~/.claude/codex-gate.off` 로 끈다.
- Imprompt 는 API 키·토큰을 저장하지 않는다(각 CLI 의 로그인만 빌려 씀).

## 내 컴퓨터에 남는 것과 지우는 법
macOS·Linux 는 폴더 권한 700, 파일 600 으로 만든다(Windows 는 사용자 프로필 폴더의 기본 권한을 따른다). 클라우드 동기화 폴더(iCloud·Dropbox·OneDrive 등)에는 홈 아래 이 경로들을 두지 않도록 주의한다. macOS 는 Hammerspoon 에 손쉬운 사용 권한을 줘야 하고, Hammerspoon 은 로그인 시 자동 실행된다. 리뷰 게이트를 끄는 `~/.claude/codex-gate.off` 는 보안 경계가 아니라 편의 스위치다.

| 위치 | 내용 | 지우기 |
|---|---|---|
| `~/.imprompt/cache/` | 개선 결과 본문(같은 요청 재사용용, 24시간 지나면 다음 저장 때 삭제·최대 200개, 본인만 읽기) | 폴더 삭제 · `IMPROMPT_CACHE=0` 으로 끔 |
| `~/.claude/prompt-improver/last-original.txt` | 마지막 Ctrl+Q 원문(실패 시 복구용, 권한 600) | 파일 삭제 |
| `~/.imprompt/jobs/`·`jobs-report.html` | 작업 내역(요청은 앞 40자 미리보기, 최근 50건) | 폴더·파일 삭제 |
| `~/.imprompt/mcp.log` | 호출 기록 — 원문 없음(해시 앞 10자·엔진·소요·토큰), 1MB 넘으면 `.1` 하나로 순환 | 파일 삭제 |
| `~/.imprompt/settings.json` | 바꾼 단축키 | 파일 삭제 |
| `~/.imprompt/custom-rules.md`·`custom-rules.draft.md`·`custom-rules.md.bak` | 내 사용자 지침과 가져오기 초안·백업(권한 600) | 파일 삭제 · `PI_CUSTOM=0` 으로 끔 |
| `~/.claude/prompt-improver/invocations.log`·`last-run.log`·`last-ask.log` | 터미널 개선기 호출 기록(원문·답 없음 — 직접 입력한 답은 글자 수만, 1MB 순환)과 마지막 엔진 오류 출력(엔진 응답 본문은 남기지 않음) | 파일 삭제 · 완전 제거 때 삭제 |
| 실행 중 임시 파일(macOS·Linux `$TMPDIR`, Windows `%TEMP%\imprompt-*.txt`) | 보내는 원문·문맥·결과(600) — 끝나면 삭제(신호로 끊겨도 삭제, Windows 는 단축키 프로그램이 강제 종료되면 남을 수 있음) | 임시 폴더 정리 |
| `~/.claude/gate-log/review.jsonl`·`~/.claude/codex-gate/` | 리뷰 게이트 판정 기록(파일 경로·요약 200자, 2MB 순환)·세션별 상태(개발자 수동 설치만) | 파일·폴더 삭제 |
| Windows `%APPDATA%\imprompt\hotkey.ini` | 파이썬·서버 경로, 바꾼 단축키 | 폴더 삭제 |
| `~/.hammerspoon/init.lua` (macOS) | `imprompt-hotkey`·`imprompt-menubar` 표식 블록(바꿀 때마다 `.bak-시각` 백업, Hammerspoon 자동 실행 켬) | `install.sh uninstall`(블록만 — 백업·자동 실행 설정은 남음) |
| `~/.claude/keybindings.json`·`settings.json` `env.VISUAL`, `~/.imprompt/editor-keys.json` (macOS·Linux) | 입력창 Ctrl+Q 연결과 되돌리기 기록 | `install.sh uninstall`(설치기가 바꾼 것만 되돌림) |
| 각 CLI 의 MCP 등록 | `imprompt` 서버 1개 | `install.sh uninstall` |
- **완전 제거(일반 사용자)**: Windows 설정 → 앱 → 설치된 앱 → Imprompt → 제거(또는 트레이 연필 아이콘 → Uninstall Imprompt...), macOS 메뉴바 연필 아이콘 → Uninstall Imprompt... — `install.ps1 remove` / `install.sh remove` 와 같다: 연결 해제 + 설정·기록(`~/.imprompt`, `%APPDATA%\imprompt`)·'설치된 앱' 등록·설치 폴더 삭제(설치기가 받은 그대로일 때만 — 개발용 작업 폴더는 남김). Git·Python·AutoHotkey·Hammerspoon·엔진 CLI 는 남긴다.
- **설치 해제(연결만)**: macOS·Linux `~/.local/share/Imprompt/install.sh uninstall`(예전 설치는 `~/Desktop/Imprompt/install.sh uninstall`), Windows `powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Imprompt\install.ps1" uninstall` — MCP 등록(claude·codex·gemini)을 해제하고 macOS 는 Hammerspoon 블록(백업 보존), Windows 는 시작 프로그램 바로가기·실행 중인 단축키를 정리한다. 폴더(`~/.local/share/Imprompt`, Windows `%LOCALAPPDATA%\Imprompt`)·위 기록 파일·`hotkey.ini`·엔진 CLI 는 자동으로 지우지 않고 안내만 한다.

## 구성
| 파일 | 연결 위치 | 역할 |
|---|---|---|
| `prompt-improver/pi-edit` | `~/bin/pi-edit` (Windows: `~/bin/pi-edit.cmd` 래퍼) | 프롬프트 개선기 본체(bash 3.2+ · perl JSON::PP, macOS·Linux·Git Bash 공통). Claude 입력창→Claude 설정, Codex 입력창→Codex 설정으로 개선 |
| `prompt-improver/instructions.md` | `~/.claude/prompt-improver/instructions.md` | 개선 규칙 — **개선 스타일은 여기서 수정** |
| `prompt-improver/bench/` | 링크 안 함 | 개선기 벤치. `bench.py <라벨>`(샘플 시간·토큰 — 공개본은 샘플 2건), `compare/`(21건 × 개선 전·후 스킬·일반 에이전트 토큰·품질 비교, 결과 `compare/RESULTS.md`). 규칙·모델 바꿀 때 전/후 비교용 |
| `review-gate/codex-review-gate.py` | `~/.claude/hooks/codex-review-gate.py` | Codex 리뷰 게이트 (Stop 훅, 자동). v4(2026-10-28)부터 판정마다 `~/.claude/gate-log/review.jsonl`에 1줄 기록 |
| `assets/icon/` | 링크 안 함 | 앱 아이콘(반짝이는 연필, 2026-11-03 채택): `imprompt-icon-1024.png`(여백 없는 불투명 원본 — macOS 27 규격), `imprompt-icon-128.png`(작은 표시용), `imprompt-icon-rounded.png`(둥근 모서리 투명, README·웹용). 메뉴바 단색판은 `menubar/imprompt_menubar.lua` 가 직접 그린다 |
| `config/keybindings.json` | `~/.claude/keybindings.json` | Claude Code `Ctrl+Q` → 외부편집기(=개선기) |
| `snippets/*` | 직접 병합 | 공유 설정 파일 조각: Claude `settings.json` Stop 훅, Codex `config.toml` 키, `.zshrc`/`.bashrc` VISUAL, Windows `settings.json` env.VISUAL |

로그·상태는 링크 안 함(기기 로컬): `~/.claude/prompt-improver/*.log`, `~/.claude/codex-gate/*.json`, `~/.claude/gate-log/review.jsonl`(리뷰 게이트 판정 기록 — 기록 실패는 무시, 게이트 동작 불변).

## 사용
- 프롬프트 개선: Claude Code 또는 Codex 입력창에 요청 → **Ctrl+Q** (10~30초) → 개선본 확인 후 Enter. 원복 `Ctrl+_`(Claude). 짧은 요청은 짧게(8단어 이하 → 12줄 안팎), 그 밖엔 20줄 이내로 표준 흐름을 펼친다(2026-10-09, 10-07 "짧은 요청도 상세 지침" 결정을 갱신).
  - **프로젝트 인식**: 세션 폴더의 최상위 항목, 항목 6개 이하 하위 폴더의 내용(예: `web/: imprompt-web.html`), 스택 단서(package.json·pyproject 등)를 약 100~150토큰으로 함께 보내 실제 스택·경로를 쓰게 한다(폴더 이름만 보고 스택을 짐작하지 않게). 그 밖의 파일명·수치는 여전히 추측 금지. 끄기 `PI_CONTEXT=0`.
  - **간결 모드**: 원문을 `짧게` 또는 `brief`로 시작하면 1차 질문 없이 바로 핵심만 8줄 이내(요구사항 ≤3·제약 1·완료 기준 1, 질문 ≤1).
  - **자동 폴백**: 기본은 재시도·업체 전환 없음(pi-edit 은 PI_FALLBACK, MCP·단축키는 IMPROMPT_FALLBACK). 다른 업체의 CLI(Claude↔Codex↔Gemini)로 넘기는 폴백은 `IMPROMPT_FALLBACK=1`(입력창은 `PI_FALLBACK=1`) 일 때만 한다 — 문장이 다른 회사로 가므로 기본은 꺼 둔다(아래 "어느 문장이 어느 회사로 가나요"). 타임아웃은 폴백 제외.
  - **0토큰 게이트**(OMC·OMX 차용): 원문 앞에 `*`를 붙이면 개선 없이 그대로 통과, `!`는 강제 개선. 이미 목표·요구사항·완료 기준 구조를 갖춘 원문, 그리고 **입력 전체가** 짧은 답변(네·3번·1 2 1·응 그걸로 해줘…)이고 직전 에이전트 턴이 질문으로 끝났으면 자동 통과해 호출·대기가 없다(`ok 버튼 추가해줘`처럼 답변 어휘로 시작하는 요청은 개선). 2단 폴백 답을 적어 다시 누른 호출과 `!`는 항상 개선(`!`는 폴백 블록에도 유지).
  - **대화 문맥**: 원문이 짧거나 "그것·아까·이어서" 같은 지시어를 담은 후속 요청이면 현재 세션 기록의 마지막 사용자·에이전트 턴(각 600자)을 함께 보내 지시어를 풀어 쓴다. Claude Code 는 `CLAUDE_CODE_SESSION_ID` 가 있으면 그 세션 jsonl 만, 없으면 `~/.claude/projects/<폴더>/` 의 최근 갱신 jsonl(10분 안에 갱신된 세션이 2개 이상이면 오인 대신 생략), Codex 는 `~/.codex/sessions/` 에서 현재 폴더·사용자 스레드의 최근 세션(서브에이전트·리뷰 세션 제외). 끄기 `PI_HISTORY=0`, 글자 수 `PI_HISTORY_CHARS`.
  - **질문 모드(v6, OMC·OMX·MoAI 패턴 차용)**: 요청이 모호하면(경로·식별자·수치·재현 절차 없음) 1차 호출(`ask.md`, 저강도, 5~10초)이 **부족한 점과 질문 최대 3개**를 선택지와 함께 터미널에 띄운다. 질문은 **선택 메뉴**(`prompt-improver/ask-menu.pl`, 대체 화면)로 뜬다: ↑↓ 또는 클릭·휠로 선택지 고르기, 숫자 키로 바로 선택, 질문마다 **Custom answer:** 칸(글자를 치면 바로 직접 입력), Tab/←→ 질문 이동, Enter 다음 질문·마지막이면 확정(Enter 세 번 = 전부 권장), `[ Confirm Enter ]` 클릭, **Esc = 질문 건너뛰고 답 없이 개선**(미정 사항은 `[확인 필요]`로 남음). 하단 `Waiting for answer Ns`는 첫 키 입력 때 멈춘다. 질문은 최대 3개. 화면이 작으면(질문이 다 안 들어가거나 폭 40칸 미만) 한 줄 입력 방식으로 자동 전환(`1 2 1`·자유 서술·Enter 권장·Esc 건너뛰기), `PI_ASK_UI=line`으로 강제. 답은 `<답변>`으로 2차 호출에 합쳐져 `[가정]`·`[확인 필요]` 대신 확정 사실로 들어간다. 터미널 입력이 안 되는 환경이면 입력창에 `<질문>` 블록을 써 주니 `답:` 줄을 채우고 다시 Ctrl+Q(2단 폴백). 끄기 `PI_ASK=0`, 항상 질문 `PI_ASK=always`, 답 대기 `PI_ASK_TIMEOUT`(기본 60초, 무입력 만료=전부 권장, 화면에 `No input for 60s. Using recommended answers.` 안내). 설계·조사: `prompt-improver/QUESTION-MODE-DESIGN.md`.
  - **대기 애니메이션**: 확인 중·개선 중 줄이 연필 애니메이션(✎ 초안 ∿ → 다듬은 줄 ‿⁀ → ✦) + 경과초로 움직인다(`prompt-improver/pi-anim.pl`, perl 내장 모듈만, 80ms 갱신·CPU 약 1%). 터미널이 아니거나(파이프·벤치) `TERM=dumb`·CI·UTF-8 아닌 로케일·Windows·폭 40칸 미만이면 기존 정적 줄 그대로. 끄기 `PI_ANIM=0`, 강제 `PI_ANIM=1`, `NO_COLOR`는 색만 끔.
  - **완료 후 복사**: 개선이 끝나면 `Prompt refined (Ns). c = copy to clipboard…` 줄이 3초 뜬다. **c**(한글 자판이면 ㅊ)를 누르면 개선된 프롬프트가 클립보드에 복사되고(macOS pbcopy · Windows PowerShell · Linux wl-copy/xclip/xsel), 다른 키를 누르거나 3초가 지나면 바로 입력창으로 돌아간다. 대기 시간 `PI_COPY_WAIT`(초, 0=끔).
  - **출력 계약(v6)**: 목표 1줄 → 요구사항 → 제약·주의("범위 밖" 1줄) → 완료 기준(검증 방법) → [가정]/[확인 필요]. 줄 틀은 입력 크기별: 기본 요구 ≤6·제약 ≤3·완료 ≤3 / 8단어 이하 ≤4·2·2 / 짧게 ≤3·1·1. 원본에 없는 기능·정책은 만들지 않고, 원본이 고칠 곳을 지정했으면 다른 파일은 "보고만". 질문은 결정만, `<답변>`이나 경로·식별자·수치가 있으면 0개, 그 밖엔 최대 2개. 서문·맺음말·코드펜스 없이 바로 붙여넣기(모델이 펜스로 감싸면 자동으로 벗김).
  - 제한 시간 90초(`PI_TIMEOUT`) 넘기거나 실패하면 원문 유지 + ⚠ 한 줄. 호출·엔진·소요초·토큰은 `~/.claude/prompt-improver/invocations.log`(본인만 읽기, 600). Codex 엔진은 빈 임시 폴더에서 실행해 프로젝트 파일을 뒤지지 않는다.
- 리뷰 게이트: 코드 바꾼 턴이 끝나면 자동. 결과 한 줄(✓/✗/⚠). 끄기 `touch ~/.claude/codex-gate.off`.
- 모델은 각 도구 설정(`~/.claude/settings.json`, `~/.codex/config.toml`)을 따른다. 추론강도는 Claude 2차(본문) 호출만 **medium 기본**(소유자 결정, 실측: high 대비 wall −27%·출력 −39%·judge 동등), 1차 질문은 low, Codex 는 config 그대로. `PI_EFFORT`로 덮어쓰기.

## 사용자 지침 (내 선호 등록)
기본 규칙(`prompt-improver/instructions.md`) 뒤에 **내 선호**(답변 언어·출력 형식·꼭 넣을 검증 습관·금지 사항)를 덧붙인다. 사용자 전역 1벌 `~/.imprompt/custom-rules.md`(Windows `%USERPROFILE%\.imprompt\`)이며, 프로젝트별 지침은 만들지 않는다(클론한 저장소가 지침을 심는 통로가 되므로).
- **적용 범위**: 2차 개선(본문)에만. 1차 질문 단계(`ask.md`)에는 넣지 않는다(출력 형식을 코드가 읽으므로). Ctrl+Q 입력창(pi-edit)·MCP·전역 단축키 세 경로가 같은 파일을 같은 규칙으로 읽는다.
- **방법 1 — 직접 쓰기**: macOS 메뉴바 아이콘 → **Edit Custom Rules...**, Windows 트레이 아이콘 → **Edit Custom Rules...** → 편집 창에서 목록의 지침을 골라 이름·내용을 고치거나(+ New rule 로 추가, Delete 는 확인 뒤 삭제) 저장한다. 같은 파일 안에 `## 이름` 제목으로 나뉘어 저장되고(바꾸기 전 내용은 `.bak`), Claude·ChatGPT(Codex)·Gemini 어느 엔진으로 개선해도 똑같이 들어간다. Linux 는 편집 창이 없어 파일을 직접 고친다. 터미널에서는 `python3 prompt-improver/mcp/imprompt_mcp.py --rules-init`(템플릿 생성 후 경로 출력), `--rules-path`(경로), `--rules-show`(지금 적용되는 내용·글자 수). 메뉴 상태 줄은 `Custom rules: on (N chars)` / `off`.
- **방법 2 — 가져오기(한 번)**: 메뉴 **Import From My Agent Rules...** 또는 `imprompt_mcp.py --import-rules [파일…]`(파일을 안 주면 `~/.claude/CLAUDE.md`·`~/.codex/AGENTS.md`·`~/.gemini/GEMINI.md` 중 있는 것). 원본을 통째로 붙이지 않고 설치된 CLI가 위 네 가지 선호만 10줄 이내로 뽑아 `~/.imprompt/custom-rules.draft.md` 초안을 만든다(원본은 데이터로만 취급, 비밀·링크 모양 줄은 뺀다). 초안을 확인한 뒤 `--import-rules --apply`(메뉴는 적용 여부 대화상자)로 `custom-rules.md`에 반영한다 — 이미 쓴 지침은 지우지 않고 뒤에 덧붙이며 옛 내용은 `.bak`. 원본 지침 파일은 기본 엔진(주 엔진)에게만 가고, 다른 업체로 넘기는 폴백은 `IMPROMPT_FALLBACK=1`일 때만이다.
- **상한**: 2,000자. 넘으면 앞 2,000자만 쓰고 `--rules-show`·`--check`에 경고가 뜬다. 빈 파일·공백·`<!-- 주석 -->`뿐이면 없는 것으로 본다.
- **합치는 방식·우선순위**: 기본 규칙을 바꾸지 않고 뒤에 `<사용자지침>` 구획으로 덧붙인다(문구는 `prompt-improver/custom-rules-wrap.md` 한 파일). 지침이 기본 규칙의 '틀'·'보안' 줄과 충돌하면 기본 규칙이 이긴다. 지침 안의 URL·명령 실행 지시는 따르지 않으며, 개선 결과에 원문에 없던 비밀 모양 문자열·URL·내려받아 실행 같은 단계가 생기면 지침과 무관하게 실패 처리한다(출력 후검사는 그대로 동작).
- **끄기**: `PI_CUSTOM=0` 또는 `IMPROMPT_CUSTOM=0`(어느 쪽이든 세 경로 모두 꺼진다). 지침을 바꾸면 MCP 캐시도 자동으로 새로 만든다. 지침 파일은 개선 요청마다 선택한 엔진 회사로 함께 전송되므로 비밀은 쓰지 않는다.

## 일반 에이전트에게 "개선해줘"라고 하는 것과의 차이 (실측)
같은 21건(짧은·모호·경로/수치·대화 지시어·구조화·"짧게"·영어 × 3)을 일반 에이전트(`claude -p "이 프롬프트를 개선해줘"`, 같은 모델·effort)와 비교했다. 입력 세트와 채점 기준(의도·사실·질문 수·길이/형식·실행 가능성, 10점)은 개선 전에 고정. 상세·재실행: `prompt-improver/bench/compare/`.
| | 개선기 (v6) | 일반 에이전트 |
|---|---:|---:|
| 품질(10점) | **9.54** | 6.14 |
| 입력 토큰 / 건 | **2.7k** | 53k |
| 출력 토큰 / 건 | **0.77k** | 1.67k |
| 비용 / 21건 | **$0.51** | $2.16 |
| 길이 초과 · 형식 위반(코드펜스·서문) | **0 · 0** | 18 · 14 |
- **구조 고정 → 출력 상한**: 섹션·줄 틀이 정해져 있어 최대 17줄(일반 에이전트 42줄), 출력 토큰 −54%. 그대로 붙여넣을 수 있다.
- **프로젝트 사실 → 탐색 비용 절감**: 파일을 열어 보는 대신 폴더 구조 요약(~100토큰)만 보내 먼저 볼 곳을 짚는다. 일반 에이전트는 기본 시스템 프롬프트·파일 읽기로 입력이 20배(−95%). 그 밖의 파일·스택은 쓰지 않아 사실 점수 1.73 vs 0.84.
- **질문 최소화**: 결정만, 많아야 3개(1차 메뉴) — 답을 받으면 본문에서 다시 묻지 않는다. 경로·식별자가 있거나 "짧게"면 질문 단계 자체를 건너뛴다(0토큰).
- **0토큰 게이트**: 이미 구조화된 요청·짧은 답변은 호출 없이 그대로 통과.

## 개발자 수동 설치 (입력창 개선기·리뷰 게이트 포함)
일반 사용자는 위 "설치는 문장 하나"·"에이전트가 없다면"으로 충분하다. 아래는 저장소를 직접 받아 입력창 개선기·리뷰 게이트까지 링크로 설치하는 개발자 절차다(한 줄 설치 `use` 와 다르다 — `use` 는 리뷰 게이트·snippets 병합을 하지 않는다).

**macOS**
1. CLI 설치·로그인: `claude auth login`(Claude Pro/Max), `codex login`(ChatGPT). 확인 `claude auth status` / `codex login status`.
2. `git clone https://github.com/seonoh/Imprompt.git ~/.local/share/Imprompt && ~/.local/share/Imprompt/install.sh` → 링크 생성 + ✗ 항목 출력(바탕화면에 받으면 macOS 가 '폴더 접근' 권한 창을 띄운다).
3. ✗ 항목 병합: `~/.claude/settings.json`에 `snippets/claude-settings-stop-hook.json`(리뷰 게이트), `~/.codex/config.toml`에 `snippets/codex-config.toml`(Codex Ctrl+Q), `~/.zshrc` 끝에 `snippets/zshrc.sh`(VISUAL).
4. **새 터미널 탭**에서 `claude` → 요청 입력 → **Ctrl+Q** → 10~30초 뒤 입력창이 개선본으로 바뀜 → 확인 후 Enter. 짧게 받으려면 `짧게 …`.

**Windows (Git Bash) — 개발자용 수동 설치, 실기기 미검증**(일반 사용자는 위 `Imprompt-Setup.cmd`)
1. Git for Windows(bash·perl 포함), Python 3.8+(리뷰 게이트용), Claude Code·Codex CLI 설치 후 각각 로그인(위와 동일).
2. Git Bash에서 `git clone https://github.com/seonoh/Imprompt.git ~/Desktop/Imprompt && ~/Desktop/Imprompt/install.sh` → `~/bin/pi-edit.cmd` 등 래퍼 생성(링크 대신), keybindings 복사(기존 파일은 `.bak`).
3. `~/.claude/settings.json`에 `snippets/windows-claude-settings-env.json`(env.VISUAL = `C:\Users\<사용자>\bin\pi-edit.cmd`)과 `snippets/windows-claude-settings-stop-hook.json`(python 명령) 병합, `~/.codex/config.toml`에 `snippets/codex-config.toml`.
4. 새 Claude Code 세션 → Ctrl+Q. 안 되면 `~/.claude/prompt-improver/invocations.log`·`last-run.log` 확인.

공통: 모델은 각 CLI 설정을 따른다(개선기 Claude 2차 effort 만 medium 기본). 끄려면 `.zshrc`의 VISUAL 줄(Windows는 env.VISUAL)과 settings.json의 Stop 훅을 지우면 된다. 리뷰 게이트만 끄기 `touch ~/.claude/codex-gate.off`.

## 새 기기 설치
- 한 줄(공개 저장소, macOS·Linux·Git Bash 공통): `curl -fsSL https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/bootstrap.sh | IMPROMPT_COMMIT=f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e bash` → `~/.local/share/Imprompt`(예전 `~/Desktop/Imprompt` 설치본이 있으면 그 폴더)에 clone(있으면 fetch) 후 그 릴리스 커밋을 checkout(HEAD 일치 검증)하고 `install.sh`(인자 없음 = 개발자 링크 설치) 실행. 위치는 `AI_TOOLS_DIR`, 시험용 저장소 주소는 `AI_TOOLS_REPO`(기본값이 아니면 ⚠ 표시).
- 수동: 1) `git clone` 또는 폴더 복사 → `~/Desktop/Imprompt` 2) `./install.sh` → 출력의 ✗ 항목만 `snippets/`대로 병합(기존 파일은 `.bak-시각`으로 보존) 3) Codex 로그인(ChatGPT 구독) 확인 → 새 터미널 탭에서 `claude`/`codex`

### Windows (Git Bash) — 개발자용, 실기기 미검증
- 전제: Git for Windows(bash·perl 포함), `claude`·`codex` CLI. Claude Code는 Git Bash를 통해 셸을 쓴다(`CLAUDE_CODE_GIT_BASH_PATH`).
- Git Bash에서 `./install.sh` → 심볼릭 링크 대신 래퍼 생성: `~/bin/pi-edit`(bash), `~/bin/pi-edit.cmd`(Claude Code가 Windows에서 `.exe/.cmd/.bat`만 직접 실행하므로 필요), keybindings 복사.
- `~/.claude/settings.json`의 `env.VISUAL`에 `C:\Users\<사용자>\bin\pi-edit.cmd` 추가 (`snippets/windows-claude-settings-env.json`).
- 검증 순서: 새 Claude Code 세션 → "로그인 구현해줘" → Ctrl+Q → 입력창 교체. 안 되면 `~/.claude/prompt-improver/invocations.log`·`last-run.log` 확인. Codex의 Windows 외부편집기 동작은 미조사.

## 라이선스·보안
- 라이선스: [MIT](LICENSE). 설치기가 받아 오는 프로그램(Claude Code·Codex CLI·Gemini CLI·Hammerspoon·AutoHotkey·Git·Python)은 각자의 라이선스를 따른다. Imprompt 는 Anthropic·OpenAI·Google 과 제휴 관계가 없다.
- 보안 문제 신고: [SECURITY.md](SECURITY.md) — 공개 Issue 에 쓰지 말고 비공개 신고로.

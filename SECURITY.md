# 보안 신고 (Security Policy)

## 신고 방법
보안 문제는 **공개 Issue 에 쓰지 마세요.** GitHub 비공개 신고를 써 주세요:
저장소 **Security** 탭 → **Report a vulnerability**
(https://github.com/seonoh/Imprompt/security/advisories/new)

적어 주시면 좋은 것: 영향을 받는 파일·버전(`VERSION`), OS, 재현 절차, 예상 영향.
실제 비밀번호·API 키·개인정보는 첨부하지 마세요.

## 지원 버전
가장 최근 릴리스(`VERSION` 파일의 태그)만 보안 수정을 받습니다. 수정은 새 태그로 냅니다 — 이미 낸 태그·커밋은 옮기지 않습니다.

## 범위
- 설치 스크립트(`get.*`·`bootstrap.*`·`install.*`·`docs/Imprompt-Setup.cmd`), 전역 단축키(`hotkey/`·`menubar/`), MCP 서버·개선기(`prompt-improver/`), 리뷰 게이트(`review-gate/`).
- 범위 밖: Claude Code·Codex CLI·Gemini CLI·Hammerspoon·AutoHotkey 자체의 취약점 — 각 제작사에 신고해 주세요.

## 설계상 전제
- Imprompt 에는 서버·계정·API 키가 없습니다. 문장은 사용자가 로그인한 엔진 CLI 로만 전송됩니다(웹 버전은 보는 사람의 claude.ai 계정 — [docs/DETAILS.md "어느 문장이 어느 회사로 가나요"](docs/DETAILS.md#어느-문장이-어느-회사로-가나요)). 다른 업체로 넘기는 폴백은 기본으로 꺼져 있습니다.
- 설치기가 받는 외부 프로그램: 엔진 CLI 는 각 업체 공식 설치기의 최신본(claude.ai·chatgpt.com·npm `@google/gemini-cli`), macOS Hammerspoon 은 공식 GitHub 릴리스(해시·서명 팀·Apple 공증 확인 후), Windows 는 winget 공식 패키지 ID. 이 업체들을 신뢰하는 구조입니다.
- 한 줄 설치 명령은 릴리스 **커밋 SHA** 에 고정돼 있어, 태그나 `main` 이 바뀌어도 받는 코드는 바뀌지 않습니다.

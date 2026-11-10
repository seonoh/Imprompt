# 웹 채팅 모드 흉내 시험 (llms-install.md §0)

웹 채팅 에이전트는 링크의 페이지를 읽기만 하고 명령은 못 실행한다고 보고, 같은 조건을 CLI 로 흉내 낸다:
에이전트가 읽었을 문서(README·llms-install·ask·instructions)를 "열어 본 페이지"로 넣고, 도구·셸을 끈 엔진에
3턴(`https://github.com/seonoh/Imprompt 사용해줘` → `할일 내보내기 기능 만들어줘` → `권장`)을 대화 기록째 보낸다.

    python3 -I prompt-improver/bench/webchat/sim.py <저장소 경로> claude|codex|gemini <결과.json>

통과 기준: ① 1턴 "Imprompt 준비됐어요…" ② 2턴 질문 ≤3(번호·선택지, 답 기다림) ③ 3턴 개선된 프롬프트 코드 블록 + 붙여넣기 안내.
실제 웹(claude.ai·chatgpt.com·gemini.google.com)에서 링크를 여는 단계는 이 시험이 대신하지 못한다(저장소 공개 뒤 직접 확인).

## 2026-11-04 결과
- claude(Opus 5.5, 도구 없음): ①②③ 통과 — 질문 3개, CSV 개선본.
- codex(gpt-6-astra, 셸 끔): ①②③ 통과 — 질문 2개, CSV 개선본.
- gemini CLI: 실행 불가 — 이 계정 등급은 Google 이 CLI 호출을 막음(IneligibleTier). Gemini 웹은 별도 확인 필요.

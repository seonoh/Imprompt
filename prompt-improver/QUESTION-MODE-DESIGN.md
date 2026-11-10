# 질문 모드 설계안 — OMC·OMX·MoAI 조사 기반 (2026-10-07)

상태: **구현됨(v6, 2026-10-07)** — 관리자 승인 후 §4대로 반영. 검증·성능은 §8. 범위: `prompt-improver/`의 Ctrl+Q 흐름만(web·review-gate·snippets 제외).

## 1. 현재 구조 (v5, 코드 기준)

| 항목 | 값 |
|---|---|
| 호출 | Ctrl+Q 1회 = 모델 호출 1회(`pi-edit` → `claude -p` 또는 `codex exec`, 실패 시 다른 엔진 1회 폴백) |
| 규칙 파일 | `instructions.md` 2,101바이트 ≈ 900토큰 |
| 입력 구성 | 규칙 + Claude Code 자체 프레이밍(~600) + `<원본>` + `<프로젝트>`(60~100) + 후속 요청일 때 `<대화>`(≤2턴×600자) |
| 실측(fable·high, 샘플 3건) | 입력 1,878 / 출력 1,182 토큰, API 21.0초 |
| 0토큰 게이트 | `*` 접두·구조화 원문(섹션 ≥3)·짧은 답변은 호출 없이 통과 |
| `[확인 필요]` 처리 | 2차 출력 끝에 **텍스트로만** 남음(샘플별 1~3개). 답을 받는 경로 없음 → 에이전트가 되묻거나 `[가정]`으로 진행 |

문제: 질문을 써 놓고 멈추는 반쪽 구조. 조사 근거(CLARITI 질문 3개로 완전명세 성능 88% 회복, ClarifyGPT 71→81%)상 답을 받아 반영해야 효과가 난다.

## 2. 세 프로젝트 비교 (실제 연 파일만 인용)

경로 약어: OMC=OMC 5.3.0 패키지, OMX=OMX 패키지, MoAI=GitHub `modu-ai/moai-adk` main(2026-10-07 클론).

| 항목 | OMC 5.3.0 (deep-interview / plan) | OMX 0.21.6 (deep-interview / triage) | MoAI-ADK (plan Phase 3-4 / askuser) |
|---|---|---|---|
| (a) 질문 생성 | 차원 Goal/Constraints/Criteria 가중 점수(.40/.30/.30)를 **LLM(opus)이 채점**해 최약 차원 1문항(`skills/deep-interview/SKILL.md:39-44, 238-244, 271-313`). 라운드 3 조기종료/10 경고/20 하드캡(`:368-370`). plan은 "광범위 요청"만 인터뷰(`skills/plan/SKILL.md:62-67`), 분류표 **Codebase Fact→묻지 말고 explore, Preference→ask**(`:273-278`). 실행 게이트: 정규식 신호(파일경로·식별자·`#123`·번호목록·테스트러너) 없고 유효 단어 ≤15면 인터뷰(`src/hooks/keyword-detector/index.ts:1006-1069`) | 프로파일 quick/standard/deep = 임계 .30/.20/.15, 최대 5/12/20라운드(`skills/deep-interview/SKILL.md:30-32`). 6차원 + 단계 우선순위 Intent→Feasibility→Brownfield(`:161-164`). "facts before judgment" 라벨 `[from-code]`(`:65-70`). 트리아지 훅 11규칙(명령형 6단어↑→HEAVY, 짧고 애매→PASS, `dist/hooks/triage-heuristic.js:170, 202-286`) | **휴리스틱 clarity 1~10점**(기술 키워드 3~4개 +2, 파일/모듈 언급 +1, 범위 경계 +2, `system/feature/thing` −1, `.moai/workflows/plan/context-discovery.md:48-56`) → **점수→라운드**: 1~3 = 넓은 질문 1개, 4~6 = 2라운드, 7~10 = 5라운드(`:58-68`). skip: 기술 키워드 ≥5·`--skip-interview`(`:42-46`). 라운드 주제 고정 Scope→Constraints→Success→Edge→Priority(`plan/clarity-interview.md:20-28`), ≤3·≥8이면 조기 종료(`:40-42`). 4 트리거/5 예외(`askuser-protocol-reference.md:222-244`) |
| (b) 선택지·기본값 | AskUserQuestion, 2~4옵션 + 자유입력(`deep-interview/SKILL.md:257-265`, `agents/planner.md:48`), 1번 `(Recommended)`(`:501`). 한 번에 질문 하나. Enter 기본값 규정 없음 | `omx question` JSON(`options[{label,value,description}]`, `allow_other`, `skills/deep-interview/SKILL.md:196-243`), TUI는 Other가 N+1번, Enter=현재 커서 제출(`dist/question/ui.js:125-130`). 사전 기본값 필드 없음(추정) | ≤4문항/≤4옵션, 1번 `(권장)`, 설명에 즉시 결과·부작용·정량(`askuser-protocol.md:48-69`), Other 자동(`clarity-interview.md:35`), **"Recommended when <전제>"**(`askuser-protocol-reference.md:40-45`), `recommendation_mode: push|pull`(`askuser-protocol.md:99-111`) |
| (c) 답 합치기 | 같은 세션 계속 + `state_write`에 라운드·점수 적재(`:118-145`). 임계 통과 시 opus **2차 호출**로 스펙 생성(`:395`), 템플릿 `## Assumptions Exposed & Resolved | Assumption | Challenge | Resolution |`(`:452-455`). 미결은 `### Open Questions` `- [ ] [Q] — [Why]`(`agents/analyst.md:100-110`) | 같은 세션 + `omx state write`(`:316-317`). 답 `answers[0].answer.value`를 진실로(`:212-213`). 스펙에 **Decision Boundaries(확인 없이 결정 가능한 범위)**·Non-goals 섹션 필수(`:304-311, 347-365`). 후속 답(`yes/the/that…`) 재분류 억제(`dist/hooks/triage-state.js:75-111`) | `interview.md`에 `## Interview Round N: {Topic} / Question: / Answer:` + Clarity Initial/Final(`clarity-interview.md:45-61`), 다음 단계 에이전트가 MUST read(`:65`). 미결은 `[NEEDS CLARIFICATION: topic]`을 plan.md에만(`plan.md:51-72`). 가정 템플릿 Statement/Evidence/Risk-if-wrong(`references/requirement-clarification.md:16-23`) |
| (d) 비용·규모 | 라운드당 LLM 호출 ≥2(질문+채점) + explore. 지시문 802줄/48KB + plan 292줄/25KB. 의존: state MCP, `.omc/state/*.json`, settings 임계값 | 라운드당 ≥2 호출 + 프리플라이트 스냅샷 `.omx/context/`. 지시문 571줄/41KB. 의존: `omx question` TUI(tmux), state, `.omx/context|interviews|specs` | 라운드당 **1 호출**(채점은 휴리스틱). 지시문 231+95+222+300줄(≈55KB 합계). 의존: AskUserQuestion 프리로드, `interview.yaml`, `.moai/specs/` |
| (e) 라이선스 | MIT(`package.json`, LICENSE Yeachan Heo 2025) | MIT(`package.json`, LICENSE 2026) | Apache-2.0(LICENSE) |

셋 다 **패턴만 차용**(코드 복사 없음). MIT·Apache-2.0 모두 패턴 차용에 제약 없음.

## 3. 채택 / 기각

**채택 (효과 뚜렷 + 가벼움)**
1. 0토큰 "충분히 구체함" 게이트 — 경로·식별자·수치·재현 절차가 있으면 질문 생략. 이미 v5 게이트와 같은 원리, 0토큰. (OMC keyword-detector, MoAI skip)
2. 휴리스틱 명료도 → 질문 수 — 앵커 있으면 0~1개, 없고 짧으면 최대 3개. LLM 채점 호출 없이 규칙 1줄로 표현. (MoAI context-discovery)
3. "사실은 묻지 말고 조사" 분류 — 스택·파일 위치·기존 함수는 질문 금지, 결정(방식·범위·기준)만. (OMC plan 분류표, OMX `[from-code]`)
4. 3옵션 + 1번 권장 + 자유 서술 허용 고정 포맷, 번호 입력 — 터미널에서 "답: 1 2 1"로 끝남. (MoAI askuser, OMX question)
5. "권장은 <전제>일 때" 한 줄 — 거절이 쉬워짐. 선택지 설명 10자 내외로 제한해 토큰 유지. (MoAI)
6. 답 합치기 = `<답변>` 블록 한 번 — 2차 호출 입력에 `질문 → 답` 쌍을 붙이고, 규칙에 "답변은 사실로 쓰고 `[가정]`·`[확인 필요]`로 되돌리지 마라". 상태 파일·2차 채점 없음. (MoAI interview.md 템플릿의 최소형)
7. 범위 밖 1줄 필수 유지 + 미답 질문은 `[확인 필요]`로 남기고 진행 — 이미 v5에 있음. (OMX Non-goals, MoAI NEEDS CLARIFICATION)

**기각 (무거움)**
- LLM 채점 2차 호출·가중 차원 수식(OMC/OMX) — 라운드마다 호출 2배, <10초 불가.
- 다중 라운드 인터뷰(5~20라운드)·조기 종료 점수 재계산 — Ctrl+Q 한 번에 끝내는 UX와 충돌.
- ontology 추적·pressure pass·장부 3종(OMC/OMX) — 효과 대비 토큰 과다.
- 상태 파일 체인(`.omc/.omx/.moai` state·specs) — 답은 입력창 텍스트에 다 들어가므로 불필요.
- 선호 메모리 기반 추천(p≈0.5 Fisher)·recommendation_mode — 데이터 축적 인프라 전제.

## 4. 변경안 — Ctrl+Q 한 번 안의 흐름

```
Ctrl+Q
 ├─ 0토큰 게이트(현행): `*`·구조화·짧은 답변 → 그대로 통과
 ├─ 명확 판정(규칙, 0토큰): 경로·식별자·수치·재현 절차 있음 → [2차 호출]로 직행  (호출 1회, 현행과 동일)
 └─ 모호 → [1차 호출] ask.md (출력 ≤10줄, 200~400토큰)
      ├─ 첫 줄 READY → [2차 호출]
      └─ 질문 블록 → 터미널에 출력(/dev/tty) →  "답: " 입력 대기(/dev/tty, 30초 무입력=권장값)
            답 형식: "1 2 1" (번호, 공백 구분) | Enter = 전부 권장값 | 번호 대신 자유 서술 가능 ("2 세션은 redis 써" 처럼 섞어도 됨)
            → <답변> 블록 생성: 질문 → 선택한 옵션 텍스트(또는 서술)
            → [2차 호출] instructions.md + <원본> + <프로젝트> + <대화> + <답변>  → 입력창에 완성본
```

**프롬프트 수정 지점**
- 신규 `ask.md`(1차, ≈700바이트 ≈ 300토큰) — 측정에 쓴 초안:
  ```
  너는 프롬프트 개선기의 1차 단계다. <원본>은 사용자가 코딩 에이전트에게 보내려는 요청이다. 다시 쓰지 말고, 착수 전에 사용자에게 물어야 할 것만 가려내라.
  규칙
  - 코드에서 확인할 수 있는 사실(스택·파일 위치·기존 함수)은 묻지 않는다. 결과가 갈리는 결정(방식·범위·기준)만 묻는다.
  - 원본에 파일 경로·식별자·수치·재현 절차가 있거나 결정이 하나로 정해지면 질문 없이 첫 줄에 READY 만 출력한다.
  - 질문은 최대 3개, 중요한 순서. 각 질문에 선택지 2~3개를 번호로 달고 첫 번째를 권장으로 둔다. <프로젝트>가 있으면 선택지에 그 사실을 반영한다.
  - 출력 형식(그 외 글자 금지, 10줄 이내):
  부족한 점: <쉼표로 3개 이내>
  1) <질문> [1] <권장> [2] <대안> [3] <대안>
  ```
  보강 예정: "권장은 <전제>일 때" 10자 설명 허용, 선택지 설명 길이 상한.
- `instructions.md`(2차) 추가 2줄: "<답변>이 있으면 그 내용은 사용자가 확정한 사실이다. 그대로 요구사항·제약에 반영하고 같은 주제를 `[가정]`·`[확인 필요]`로 다시 쓰지 마라." / "<답변>에 없는 미정 사항만 `[확인 필요]`로 남긴다."
- `pi-edit`: 게이트 뒤에 `ask_user()` 추가 — 명확 판정 정규식(`/[\w./-]+\.(ts|js|py|go|…)|src/|#\d+|\d+(px|ms|초|건)|재현|reproduce/`), 1차 호출(`--effort low` 고정 — 1차는 분류 과제라 사고 불필요, 실측 사고 0), tty 출력·`read -r -t 30 ans < /dev/tty`, 답 파싱(번호→옵션 텍스트, 그 외는 서술 그대로), `<답변>` 블록 조립. 끄기 `PI_ASK=0`, 항상 질문 `PI_ASK=always`.
- Codex 경로: 동일(1차 `codex exec -c model_reasoning_effort=low`).

**터미널 표시 예**
```
✨ 부족한 점: 대상 위치, 인증 방식, 세션 관리
1) 어디에 구현할까? [1] web 폴더 (기존 웹 코드에 통합) [2] 새 독립 모듈 [3] 다른 위치
2) 인증 방식은? [1] 이메일+비밀번호 자체 인증 [2] OAuth 소셜 로그인 [3] 둘 다
3) 로그인 상태 유지는? [1] 서버 세션+쿠키 [2] JWT 토큰 [3] 외부 서비스
(답 예: 1 2 1 · 자유 서술 · 여러 답은 ' / ' 구분)
Enter=전부 권장 · Esc=질문 건너뛰기 · 타이핑하면 시간 제한 멈춤
⏳ 응답 대기 57초 › 
```
- 2026-10-07 재보완(관리자 "1초마다 입력창이 아래로 내려가 불편"): 73칸 상태 줄이 좁은 창에서 접혀 매초 한 줄씩 밀렸음 → 안내는 1회 출력, 매초 갱신은 ≈20칸 `⏳ 응답 대기 N초 ›`만, 타이핑 시작 후엔 다시 그리지 않고 글자만 덧붙임. 40칸 에뮬레이터(pyte)·실제 TUI 50칸에서 대기 중 스크롤 0줄 확인.
- 2026-10-07 보완(관리자 지적 "응답 대기 중임이 보여야 한다, 몇 초인지, 스킵 기능"): 상태 줄 1초 갱신·남은 초 표시, 타이핑 시작 시 시간 제한 정지(10분 상한), Esc=질문 건너뛰기(답 없이 2차, 로그 `answer=<건너뜀>`), 만료 시 `⌛` 안내·로그 `<권장·시간초과>`. bash 3.2 는 `read -t` 시간 초과도 rc=1 이라 0 아닌 rc 를 1초 경과로 처리. 대기 중 `stty -echo` 로 Esc 가 `^[` 로 찍히지 않게 하고 끝나면 복원.

**2단 폴백(터미널 입력이 안 될 때)**: 1차 결과를 입력창에 `<질문> … </질문>` 블록으로 써 주고, 사용자가 각 줄 뒤에 답을 적고 다시 Ctrl+Q → `pi-edit`이 `<질문>` 블록을 감지해 `<답변>`으로 바꿔 2차 호출. 상태 파일 없이 텍스트만으로 동작.

## 5. 전후 비교 (가벼움 유지)

| 항목 | 현행 v5 | 질문 모드 (명확한 요청) | 질문 모드 (모호한 요청) |
|---|---|---|---|
| 모델 호출 | 1 | 1 (정규식 판정으로 직행) | 2 (1차 저강도 + 2차) |
| 규칙 길이 | 2,101B ≈ 900tok | 동일 + 2줄 | + `ask.md` ≈ 700B ≈ 300tok |
| 1차 출력 | — | — | 보이는 출력 220~370tok(실측 4건, fable·high), 저강도 278~306tok·사고 0 |
| 2차 출력 | 1,182tok(평균) | 동일 | 동일하거나 짧아짐(`[가정]`·`[확인 필요]` 감소) |
| 총 토큰 | ≈3,060 | ≈3,060 | ≈3,060 + 1,100(1차 입력) + 300(1차 출력) ≈ +45% |
| 시간 | 21초 | 21초 | +4~11초(1차 저강도 실측) + 사용자 답 입력 |
| 의존성 | 없음 | 없음 | 없음(tty 읽기만) |

1차 호출 실측(초안 ask.md, 샘플): "로그인 구현해줘" 출력 296tok(사고 72)·9.6s, 저강도 278tok·사고 0·10.7s; "썸네일 버그" 저강도 306tok·4.4s. 질문 내용은 위치·인증 방식·세션 유지, 재현 조건·수정 방향·테스트 범위 등 결정 사항만 나왔다.

## 6. 확인 필요 (구현 전)

- **Claude Code가 편집기를 띄운 상태에서 `/dev/tty` 읽기**: 출력은 실측됨(✨ 메시지), 입력 대기는 미실측. vim과 같은 경로라 될 것으로 보나 실제 TUI에서 1회 확인 필요. 안 되면 §4의 2단 폴백.
- 1차 저강도 고정이 "모델·effort는 도구 설정을 따른다" 규칙과 충돌하는지: 1차는 분류 과제이고 2차(본문)는 설정을 따르므로 허용 범위로 판단. 관리자 확인.
- Windows(Git Bash) tty 동작은 미검증.

## 7. 참조

- OMC: `skills/deep-interview/SKILL.md`, `skills/plan/SKILL.md`, `skills/ralplan/SKILL.md`, `agents/analyst.md`, `agents/planner.md`, `src/hooks/keyword-detector/index.ts` (MIT)
- OMX: `skills/deep-interview/SKILL.md`, `dist/hooks/triage-heuristic.js`, `dist/hooks/triage-state.js`, `dist/question/ui.js` (MIT)
- MoAI-ADK: `.moai/workflows/plan/context-discovery.md`, `.moai/workflows/plan/clarity-interview.md`, `.moai/workflows/plan.md`, `.claude/rules/moai/core/askuser-protocol.md`, `askuser-protocol-reference.md`, `plugins/moai/skills/moai-workflow-spec/SKILL.md` (Apache-2.0)
- 논문: CLARITI(질문 3개로 완전명세 88% 회복) https://arxiv.org/html/2604.14624 · ClarifyGPT https://arxiv.org/abs/2310.10996 · Intent-Sim(물을 가치 있을 때만) https://arxiv.org/abs/2311.09469

## 8. 구현 결과 (2026-10-07)

- 반영 파일: `ask.md`(신규, 1차 규칙 ≈700B), `instructions.md`(+<답변> 규칙 1줄), `pi-edit`(`ask_user`·`build_answers`·2단 폴백 복귀·명확 판정 정규식·`PI_ASK*`), `bench.py`(답변 파일 저장), `judge.py`(답변을 사실로 심사).
- 검증: ① 경로 있는 요청 → 질문 없이 2차(1회 호출) ② 터미널 없음 → `<질문>` 블록 폴백 ③ `답: 1 2 1` 재진입 → 답 반영(목표가 "web 폴더·이메일/비밀번호"로 확정) ④ 진짜 pty에서 질문 표시 후 "2 1 2" 입력 → CLI 도구·OAuth·회원가입 포함으로 반영 ⑤ 답 파싱 단위 테스트(번호·Enter·자유 서술·부분 답).
- 성능(fable·high): 1차 2.6~3.5s·174~219tok(저강도, 사고 0). 2차 24.2s(평균)·1,328~1,817tok. 명확한 요청은 현행과 동일(1회). 의존성 추가 0.
- 품질: 답변 포함 심사 v6 vs v5 = 3:0, 의도 5.0·사실 4.67·착수성 4.83·간결 4.5.
- 미확인: Claude Code TUI 안에서 `/dev/tty` 입력 대기(출력은 실측, 입력은 pty 테스트로만 확인). 안 되면 폴백이 자동 적용된다.

## 9. 선택 메뉴 (2026-10-07 저녁, 관리자 지시 "클릭이나 화살표로 선택, 객관식 말고 직접 입력란도")
- `prompt-improver/ask-menu.pl`(perl, 코어 모듈만: POSIX termios·IO::Select·Encode): 대체 화면에 질문·선택지 렌더, ↑↓·숫자·클릭(SGR 1006 마우스)·휠, 질문마다 `✎ 직접 입력`, Tab/←→ 질문 이동, Enter 다음/확정, Esc·Ctrl+C 건너뛰기, `[ 확정 ]` 클릭. 첫 키 전까지 `⏳ 응답 대기 N초`.
- 출력 3줄(결과·`build_answers` 형식 답·요약) → pi-edit 이 기존 `<답변>` 경로로 합친다. 종료코드 4(화면 작음) → 한 줄 입력(`read_answer`)으로 전환, 5(메뉴 중 터미널 닫힘·HUP) → 원문 유지로 즉시 종료.
- 모델이 낸 "직접 입력·기타" 선택지는 숨기고 원래 번호 유지. 질문은 앞 3개만(pi-edit `qlines | head -3` 도 동일 — ask.md 규칙 강제).
- 결함 2건 발견·수정: ① 글자와 Enter 가 한 덩어리로 오면 Enter 를 글자로 먹음(실제 TUI 재현) → 제어 문자 전까지만 디코드 ② 메뉴 중 터미널이 닫히면 남은 출력이 다른 파일로 섞임(테스트 도구 종료 시 1회 관찰) → HUP·EOF 즉시 종료(rc 5).
- 검증: pty+화면 에뮬레이터 14사례(Enter×3·방향키·숫자 자동 이동·한글 직접 입력·Backspace·↑ 순환·Esc·클릭·휠·덩어리 입력·붙여넣기·한글 바이트 분할·시간 초과·작은 화면) 전부 통과·터미널 설정 복원 / 숨김·번호 유지·4번째 질문 무시·터미널 닫힘 3사례 / 실제 Claude Code TUI(expect, 70×40): ↓·직접 입력·Enter → `answer=2 / SSO / 1`, 요약 줄 표시, 개선본 교체, 로그 정상 / 자동 답 bench 1건 정상.
- 미검증: 사람 손의 실제 마우스 클릭(터미널이 SGR 마우스 보고를 보내는지는 터미널 앱 설정에 따름 — iTerm2·VS Code·macOS 터미널 기본 지원).


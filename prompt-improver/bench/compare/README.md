# 비교 벤치 — 스킬(개선 전·후) vs 일반 에이전트

같은 입력 21건(7유형 × 3: 짧은·모호·경로/수치 명시·대화 지시어·이미 구조화·"짧게"·영어)을 세 방식으로 처리해 토큰과 품질을 비교한다.
입력 세트 `cases.jsonl`과 기준 `rubric.md`는 규칙 개선 **전**에 고정했다(2026-10-09). 개선 후에도 같은 세트로 재측정한다.

## 재실행
```bash
cd prompt-improver/bench/compare
python3 run.py a --ref <커밋>   # (a) 개선 전 스킬 = 기준 커밋(필수 인자)의 pi-edit·instructions.md·ask.md
python3 run.py b                 # (b) 개선 후 스킬 = 작업 트리
python3 run.py c                 # (c) 일반 에이전트: claude -p "이 프롬프트를 개선해줘" + 원문
python3 score.py a b c           # 채점(LLM 심사 sonnet + 자동 판정) → bench/out/compare/report-a-b-c.md
```
- `--jobs N` 병렬(기본 4), `--only id,id` 일부만, `--label 이름`으로 결과 폴더 분리. LLM 심사 캐시는 심사 입력(원문·출력·수락한 답·<프로젝트> 블록)·지시문·모델의 해시가 같을 때만 재사용하므로, 같은 라벨로 다시 돌려 출력이 바뀌면 자동으로 다시 심사한다. `score.py --rejudge`는 캐시를 무조건 무시, `--passes N`은 심사 횟수(기본 3, 평균).
- (a)·(b)는 실제 Ctrl+Q 경로(0토큰 게이트·질문 모드)를 그대로 돈다. 질문 답은 Enter=전부 권장. 대화 지시어 케이스는 임시 세션 기록을 `~/.claude/projects/<저장소>/bench-*.jsonl`로 만들어 `CLAUDE_CODE_SESSION_ID`로 고정하고 끝나면 지운다.
- 토큰은 PATH 앞의 `claude` 래퍼가 호출마다 응답 JSON을 남겨 합산한다(1차 질문 + 2차 본문). 입력 토큰은 캐시 포함 합계.
- 결과·로그는 gitignore 대상 `bench/out/compare/`. 결과 요약은 `RESULTS.md`.

## 명령 하나로 — Imprompt vs 일반 에이전트 2종 (2026-10-09~)
```bash
python3 bench_all.py --repeat 2          # 생성(b Imprompt · c 일반 Claude · d 일반 Codex) → 블라인드 채점 → 비교표 → 판정
python3 loop.py --max-iter 5 --budget-usd 5 --c-label <tag>-r1-c --d-label <tag>-r1-d --b0-label <tag>-r1-b   # 자동 수정 루프
```
- **지표**: ① 개선본 토큰(tiktoken o200k_base, 모든 방식 같은 잣대 — Claude 실제 토큰 수와 다름) ② 정확도 = rubric LLM 항목(의도·사실·실행 가능성) 10점 환산 ③ 원문 대비 변화율(토큰·줄). 참고로 rubric 10점 품질·호출 토큰도 표에 둔다.
- **채점 조건**: 루브릭 고정(`rubric.md` 심사 지시문 그대로 + 여러 개선본 출력 형식 안내), 채점 모델 고정 ID(Claude `claude-sonnet-5` · Codex `gpt-6.1-sol` effort low — 구독 CLI), 블라인드(케이스마다 방식들을 익명 A·B·C 로, 시드 20261009 로 순서를 섞고 역순으로 한 번 더), 채점관 2종 × 순서 2 평균. 두 CLI 모두 temperature 를 지정할 수 없어 이 평균으로 대신한다. 결과는 `blind.py`, 캐시는 `bench/out/compare/_blind-cache/`.
- **(d) 일반 Codex**: `codex exec` read-only, 저장소 cwd, (c)와 같은 지시문, config 모델·effort 그대로(생성 모델이 다름을 표에 밝힘).
- **판정**: Imprompt 개선본 토큰 평균이 c·d 보다 적고 정확도 평균이 c·d 이상이면 통과(종료 코드 0, 미달 3). `--repeat 2`는 회차별 정확도·평균 차이·케이스별 표준편차를 넣는다(허용 목표: 평균 차이 ≤ 0.3).
- **세트 분리**: `splits.json` — train 12 / validation 9, 유형별 층화·시드 고정. `bench_all.py --split train|validation`.
- **자동 수정 루프** `loop.py`: train 미달 케이스(정확도가 일반 에이전트 최고보다 0.25 넘게 낮거나 토큰이 일반 에이전트 최소 이상)로 개선용 프롬프트를 만들어(`fix-prompt.md`, validation 은 넣지 않음) `claude -p`가 `instructions.md`·`ask.md`만 고치게 한다(편집 권한도 두 파일로 한정). train·validation 을 다시 재서 둘 다 나빠지지 않을 때(정확도 −0.1·토큰 +3% 이내)만 채택·커밋, 아니면 되돌린다. 최대 회차·3회 연속 개선 0·예산(Claude CLI 보고 비용)에서 멈춘다. 기록 `bench/out/compare/loop/<tag>/LOG.md`·`loop.jsonl`·회차별 `fix-prompt.md`·`diff.patch`·`report.md`.

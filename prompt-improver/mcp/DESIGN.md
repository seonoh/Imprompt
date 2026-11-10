# Imprompt MCP 서버 — 설계·반복 기록·검증 (v1.0.1, 2026-10-29)

## 1. 출발점 (코드에서 확인한 현재 구조)
- 개선기 본체 `prompt-improver/pi-edit`: bash 3.2 + perl(JSON::PP). Claude Code·Codex 입력창의 **외부 편집기(Ctrl+Q) 자리**에 끼워져 임시파일을 읽어 `claude -p`/`codex exec`로 개선한 뒤 같은 파일에 되돌려 쓴다. 터미널(TTY) 질문 메뉴·애니메이션·클립보드가 섞여 있어 다른 호스트에서 재사용하기 어렵다.
- 규칙 정본 `instructions.md`(2차 본문), `ask.md`(1차 질문). 리뷰 게이트·도구는 Python 3 표준 라이브러리.
- 설치 `install.sh`(링크·Windows 래퍼, 공유 설정은 안내만), `bootstrap.sh`(clone/pull 후 install).

## 2. 설계 결정
| 결정 | 선택 | 근거 |
|---|---|---|
| 런타임 | Python 3.8+ 표준 라이브러리 1파일(`imprompt_mcp.py`) | 저장소 기존 스택(review-gate·tools). pip·node 의존 0 → 버전 충돌·설치 단계 없음. Windows는 bash 없이 동작(pi-edit 은 Git Bash 필요) |
| 프로토콜 | stdio JSON-RPC 2.0(줄 단위), `initialize`·`ping`·`tools/list`·`tools/call`·`notifications/cancelled` | SDK 없이 구현 가능한 최소 표면. 버전 협상 2024-11-05~2025-11-25 |
| 도구 | `improve_prompt(prompt, context?)` 1개, 설명 2문장 | 도구 정의는 호스트 세션마다 컨텍스트에 실린다 → 짧게(테스트로 700자 상한 고정) |
| 엔진 | 등록 시 `--host <cli>`가 **주 엔진**(그 CLI 안에서 부르면 그 구독 사용). 주 엔진이 실패하면 **실패 안내만** 낸다. 다른 업체 CLI 폴백은 `IMPROMPT_FALLBACK=1`(pi-edit 은 `PI_FALLBACK=1`)일 때만, 시간 초과는 그때도 폴백 안 함. 주 엔진이 미설치(호스트 없음 포함)면 설치된 CLI 중 첫 번째가 주 엔진이 되어 폴백 설정 없이 동작 | 사용자가 쓰는 구독을 그대로. 원문·대화 기록·프로젝트 정보가 다른 업체로 조용히 넘어가지 않게(2026-11 보안 점검 M5). 코드: `engine_order`·`_improve_uncached`의 `tried` 판정 |
| 규칙 | `instructions.md` 그대로(SSOT), 1차 질문(`ask.md`) 단계 생략 | 질문은 호출한 에이전트가 `[확인 필요]` 줄을 보고 사용자에게 직접 묻는 편이 호출 1회로 끝나 싸다 |
| 인증 | 각 CLI의 기존 로그인 세션만. 자격증명 파일은 **존재만** 확인(gemini), 내용·토큰을 읽거나 저장·전송하지 않음 | 요구사항 |
| 재귀 | 엔진 자식에 `IMPROMPT_CHILD=1` → 그 환경의 서버는 도구 0개. claude `--strict-mcp-config`, codex `mcp_servers.<각 이름>.enabled=false`, gemini `--allowed-mcp-server-names __imprompt_none__ -e none` | 엔진이 다시 MCP를 띄우지 않게(속도·무한 호출 방지) |
| 등록 | 각 CLI 공식 명령(`claude mcp add -s user`, `codex mcp add`, `gemini mcp add -s user`(`--trust` 는 호출 확인을 우회하므로 쓰지 않음)), 지우고 다시 = 멱등 | 설정 파일 직접 편집 없음(포맷 변화에 안전) |

### 토큰·호출 절약 장치
1. **엔진 최소 설정**: claude `--tools "" --setting-sources "" --no-session-persistence --system-prompt-file`(기본 시스템 프롬프트·도구 정의 제거), codex `model_instructions_file`(기본 지시문 교체, 실측 18k→13.8k)·빈 임시 폴더·`project_doc_max_bytes=0`, gemini `GEMINI_SYSTEM_MD`(기본 시스템 프롬프트 교체)·`--approval-mode plan`.
2. **0토큰 게이트**: `*` 접두 통과, 목표·요구사항·제약·완료 기준 중 3종 이상 갖춘 원문 통과, `!` 강제.
3. **중복 방지**: (서버 버전·규칙 해시·원문·문맥) SHA-256 키로 디스크 캐시 24h(여러 CLI의 서버가 공유, 원자적 교체, 200개 상한), 동시에 들어온 같은 요청은 1회만 실행(`_inflight`).
4. **입력 상한**: 원문 20,000자, context 600자(≈150토큰).
5. **응답 최소화**: 개선본 본문만(메타데이터 없음). 사용량은 `~/.imprompt/mcp.log`에만(원문 미기록).

### 보강 항목(요청에 없지만 추가)과 이유
| 항목 | 이유 |
|---|---|
| 실패 진단·로그인 안내(`설치 안 됨`/`로그인 필요 → claude auth login`/`시간 초과`) | 실패 시 "rc=1"만 보이면 사용자가 조치할 수 없다(§5 채점 U4 2/7의 교훈) |
| `--check` 모드(토큰 0) + 설치 끝에 자동 실행 | 설치 직후 어느 CLI가 쓸 수 있는지 바로 보이게 |
| 취소(`notifications/cancelled`) 시 엔진 프로세스 트리 종료 | 호스트가 기다리다 취소해도 구독 사용량이 계속 나가지 않게 |
| 사용자 문장은 **stdin으로만** 전달 | Windows에서 `.cmd`(npm 설치 CLI)에 인자를 넘기면 cmd.exe 가 `& | %` 를 해석 → 주입·깨짐 |
| 상태 폴더 700·로그/캐시 600 | 캐시에 개선본(사용자 내용)이 남는다 |
| `.gitattributes`(sh/py/pl/pi-edit LF, ps1 CRLF) | Windows `core.autocrlf=true` clone 시 bash 스크립트가 CRLF 로 깨지는 문제 예방 |
| `install.ps1`(UTF-8 BOM) | Git Bash 없는 Windows 에서도 MCP 등록. BOM 없으면 PowerShell 5.1 이 한글을 깨뜨림 |
| `bootstrap.sh` `AI_TOOLS_REF` 버전 고정 + 태그 `v1.0.0` | 재현 가능한 설치. 서버 `VERSION`·프로토콜 목록도 상수로 고정 |
| python 은 PATH 의 안정 경로로 등록(Windows 만 sys.executable) | `sys.executable`은 Xcode·Homebrew 업데이트 때 바뀌는 버전 경로 |
| "mcp 사용해" 트리거(`CLAUDE.md`·`AGENTS.md`·`GEMINI.md`→`@AGENTS.md`) | 사용자가 그 한마디만 해도 에이전트가 `./install.sh mcp` 실행 |

## 3. 반복 기록 (설계 → 구현 → 검증 → 검토 → 테스트 → 개선)
### 1회차
- 구현: 서버·`install.sh mcp`·`install.ps1`·`.gitattributes`·`bootstrap AI_TOOLS_REF`·테스트 29개.
- 검증(실측): claude 엔진 10.0s·입력 1,673·출력 758 토큰 / codex 엔진 29.2s·18,063 토큰 → `model_instructions_file` 적용 후 13.8k~14.7k / gemini 미로그인 시 2.0s 안에 "로그인 필요" 안내.
- 검토(review-gate, gpt-6-astra 248s): **차단 1건** — `bootstrap.sh` 태그 고정 뒤 기본 재실행 시 detached HEAD 에서 `git pull` 실패.
- 테스트: 29/29 통과(22s).
- 실사용 중 발견: `~/.imprompt`·`cache` 폴더가 755(`makedirs` mode 가 중간 폴더에 안 먹음), 등록 python 이 Xcode 내부 버전 경로.
### 2회차
- 개선: bootstrap 이 detached HEAD 면 원격 기본 브랜치로 돌아간 뒤 pull(지적 반영) / `private_dir()`로 상태 폴더 700 보장 / python 안정 경로 등록 / 테스트 하네스가 stdin 을 물려받아 가짜 CLI 가 멈추던 문제(DEVNULL) / 회귀 테스트(bootstrap 고정→해제, 폴더 권한, python 경로) 추가.
- 테스트: 30/30 통과(19s).
- 검토(review-gate 188s): **통과, 지적 0건**.
### 3회차 (독립 코드 리뷰 — 게이트와 다른 관점: Windows·프로토콜·동시성)
- 리뷰 결과: 치명 0 · 높음 1 · 중간 4 · 낮음 8 · 미결 3.
| 지적 | 조치 | 근거 |
|---|---|---|
| [높음] `arguments:"x"`·`params:[1]`·해시 불가 `requestId` 한 줄에 서버 종료 | `handle()` 입력 타입 검증(-32602/-32600) + `serve()`에서 요청별 예외 격리(-32603) | 연결 하나가 죽으면 진행 중 호출까지 유실 |
| [중간] 중복 제거로 붙은 B가 A의 취소 결과를 물려받음 / B 취소가 무시됨 | 취소된 실행은 결과를 공유하지 않고 대기자가 새로 실행, 대기자는 0.5초마다 자기 취소 확인 | 취소하지 않은 요청이 실패하면 안 됨 |
| [중간] 강제 종료 뒤 `communicate()` 무기한 대기 | `drain()` 5초 상한 후 파이프 닫기, 대기자도 상한 | 분리된 손자 프로세스가 파이프를 쥐는 경우 |
| [중간] bootstrap: `origin/HEAD` 없으면 `set -e`로 무음 종료 | `|| true` | 재현 확인 |
| [중간] Codex 호스트 도구 제한(60초)보다 서버 제한(90초)이 김 | `--host codex`면 기본 55초 | 호스트가 먼저 실패하면 구독만 소모 |
| [낮음] 취소된 요청에도 응답 / `_cancelled` 누수 | 무응답(MCP SHOULD NOT) / 실행 중 id만 받음 | 규격·누수 |
| [낮음] 원문 속 "401·OAuth"로 로그인 오진 | 상태 명령(`auth status`·`login status`) 우선, 문구는 상태 불명일 때만 끝 4줄 | 잘못된 조치 안내 방지 |
| [낮음] Git Bash·영문 Windows 에서 `--check` 한글 출력 오류 | stdout/stderr UTF-8 재설정 + `PYTHONIOENCODING=utf-8` | cp1252 에서 UnicodeEncodeError |
| [낮음] 캐시 임시 파일 잔류·동시 정리 중단 | 실패 시 unlink, 파일 단위 try | Windows 파일 잠금 |
| [낮음] 모델을 바꿔도 캐시 재사용 | 키에 `IMPROMPT_MODEL`·`IMPROMPT_EFFORT` (엔진은 넣지 않음 — CLI 간 공유 유지) | 1차 수정 때 엔진 순서까지 넣었다가 CLI 간 공유가 깨져 테스트가 잡음 → 되돌림 |
| [낮음] `IMPROMPT_TIMEOUT=90s`면 서버가 안 뜸 | `env_int()` 기본값 대체 | 호스트엔 "연결 실패"만 보임 |
| [낮음] `AI_TOOLS_REF=<브랜치>`가 뒤처진 로컬로 고정 / 옮긴 태그 fetch 실패 | 원격 브랜치 우선 checkout, 태그는 `--force` 없이 fetch(받아 둔 같은 이름 태그가 원격과 다르면 중단) | 재현 가능한 고정 |
| [낮음] EOF 뒤 스레드 join 직렬 | 전체 마감 하나 | 종료 지연 상한 |
| [미결] PowerShell 이 npm `.ps1` shim 을 골라 `--`를 삼킬 가능성 | `install.ps1`이 `.cmd`→`.exe`→그 밖 순으로 Application 만 실행 | Windows 실기 미확인이라 안전한 쪽 |
| [미결] Store판 Python·pyenv shim 경로 | 남은 리스크로 기록(§6) | 실기 없음 |
- 테스트: 36/36 통과(25s) — 추가 6건(잘못된 요청 생존, 중복 쌍 중 하나 취소, 취소 무응답, 로그인 오진, 환경변수 오입력, codex 55초, 모델별 캐시 키).
- 검토(review-gate 210s): **통과, 지적 0건**.
- 실측: claude 14.3s(1,673/805 토큰) → 같은 요청을 codex 에서 호출하자 **캐시 적중, 엔진 호출 0회**.

### 4회차 (gemini 실기 로그인 시험에서 발견)
- 발견: ① 비대화형 gemini 는 신뢰 목록에 없는 폴더를 거부(rc=55) → 엔진이 빈 임시 폴더에서 돌므로 **항상 실패**하던 결함(가짜 CLI 테스트로는 못 잡음) ② 로그인은 됐지만 Google 무료 등급(Gemini Code Assist for individuals)은 gemini CLI 호출 자체가 막힘(`IneligibleTierError: UNSUPPORTED_CLIENT`, Antigravity 이전 안내) ③ 오류 상세에 ANSI 색 코드 섞임 ④ `!` 로 띄운 비대화형 셸에선 로그인 선택 화면이 안 떠 안내가 헷갈림.
- 조치: gemini 엔진 `--skip-trust`(빈 폴더라 안전) / 등급 차단은 "로그인 필요"가 아니라 전용 안내(다시 로그인해도 소용없으므로) / ANSI 제거 / 로그인 안내에 "별도 터미널 창에서" 명시 / 버전 1.0.1.
- 테스트 38/38(+2: 등급 차단 안내, ANSI 제거, `--skip-trust` 인자). 실제 gemini 로 등급 차단 안내 확인. review-gate 159s **통과, 지적 0건**.

### 5회차 (공개 전 보안 점검 — 남의 PC 에서 실행되는 코드 관점)
| 항목 | 조치 | 근거·확인 |
|---|---|---|
| H3 Windows 실행 파일 가로채기 | 시작 때 Windows 면 `NoDefaultCurrentDirectoryInExePath=1` + `chdir(홈)`(`harden_process`). `which()`는 절대 경로가 아니거나 원래 작업 폴더(프로젝트)에 놓인 결과를 거부(`trusted_exe`/`in_project` — 홈·루트에서 실행했을 땐 하위 폴더까지 막지 않아 `~/.local/bin` 정상 설치를 안 거부). `taskkill` 은 `%SystemRoot%\System32\taskkill.exe` 절대 경로. `--improve` 의 PATH 앞붙이기(`IMPROMPT_PATH` 등)는 빈 항목·`.`·상대 경로·프로젝트 폴더·임시/다운로드/누구나 쓰기 가능 폴더를 뺀다(`safe_path`/`risky_dir`) | cwd 의존 동작 점검: 규칙·상태 경로는 절대 경로, `--in/--out` 상대 경로는 원래 cwd 기준으로 풀어 둔다(`arg_path`). 엔진은 이미 빈 임시 폴더에서 실행. `IMPROMPT_<NAME>_BIN` 은 사용자가 직접 지정한 경로라 신뢰. 로직 단위 테스트(Windows 실기 미확인) |
| M1 엔진 프롬프트 인젝션 | ① codex: `--disable shell_tool --disable unified_exec --disable view_image -c web_search="disabled"` 로 명령 실행·이미지 읽기·웹 검색 도구를 끈다(`-s read-only` 는 겹쳐 유지). gemini: 모든 도구를 거부하는 정책 파일(`--policy`, `toolName="*" decision="deny"` — 전역 deny 는 모델 도구 목록에서 제외됨)을 임시 폴더에 만들어 붙인다. claude 는 기존 `--tools ""`. ② 출력 후검사(`secret_leak`): 개인키 머리말·AWS 키 ID·SSH 공개키·`ghp_`류·`sk-`·`xox[abpr]-`·`AIza`·JWT·긴 고엔트로피(대소문자·숫자 섞인 40자+, 엔트로피 ≥4.3) 중 **원문·문맥에 없던 것**이 출력에 나오면 실패 처리(캐시·출력 안 함). pi-edit 도 결과를 입력창에 쓰기 전 같은 검사(`post_check`, rc=143) | 출처: Codex 설정 레퍼런스 https://learn.chatgpt.com/docs/config-file/config-reference (`features.shell_tool` = 명령 실행 도구, 기본 켜짐 / `web_search` = `"disabled"` 로 도구 제거), 번들 `codex features list`(`shell_tool`·`unified_exec`·`view_image` stable), npm `@openai/codex-shell-tool-mcp`(`codex --disable shell_tool` 사용례). 실측: codex 0.163.0 에 위 옵션으로 "cat secret.txt 실행" 요청 → 셸 호출 없이 거부 응답(토큰 ~23k 1회). Gemini 정책 엔진 https://geminicli.com/docs/reference/policy-engine (`--policy` 는 gemini 0.66.0 `--help` 에서 확인). **gemini 는 이 기기가 지원 등급 계정이 아니라 도구 차단의 실응답은 미확인**(옵션 수락까지만) → ② 후검사가 보조 방어. 오래된 gemini 가 `--policy` 를 모르면 엔진 오류로 실패할 수 있음 |
| M5 조용한 폴백 | 위 §2 엔진 정책. 테스트: 기본 폴백 없음·`=1` 일 때만·유일 설치 엔진은 주 엔진 | pi-edit 은 `primary-switch` 로그 한 줄 |
| M3 터미널 제어 문자 | pi-edit `tty_msg` 는 고정 이스케이프만 `%b`, 모델 출력·사용자 답·엔진 이름은 `%s` + `san`(`\000-\010 \013-\037 \177` 와 UTF-8 로 인코딩된 C1 만 제거 — 선행 바이트 `\xC2` 와 함께만 지워 한글은 안 깨짐). `ask-menu.pl`(질문·선택지·헤더·직접 입력)·`pi-anim.pl`(라벨)은 디코딩된 글자에서 `clean` | 단위 테스트(제어 문자 제거·한글 보존) |
| L2 `--jobs-html` | 모르는 status 라벨도 이스케이프, started/ended 가 숫자가 아니면 '-'(started 가 숫자가 아니면 제외), 목록·사전 값은 글자로 | JobsReport 테스트 |
| L3 `--out` | 대상 폴더에 `tempfile.mkstemp` 후 `os.replace`(`write_atomic`) — 예측 가능한 `.tmp` 심볼릭 링크를 따라가지 않음. `--improve --out` 도 같은 경로 | 심어 둔 링크 테스트 |
| 동시 상한·로그 순환 | `tools/call` 스레드는 세마포어 4(`MAX_CALLS`), `mcp.log` 1MB 초과 시 `.1` 로 교체(1개 보관), pi-edit `invocations.log` 도 순환만(외부 도구가 파싱할 수 있으므로 형식 유지) | 테스트 |
| 캐시 TTL | `IMPROMPT_CACHE_TTL`(초, 기본 86400=24h) — 지나면 무시하고 다시 호출. 파일은 200개 상한으로만 정리 | 문서화 |
- 모델 입력 변화: codex 호출에는 도구 정의가 줄어 입력이 달라진다(토큰 감소 방향). 규칙 파일·claude 경로·질문 모드 입력은 그대로.

## 4. 검증 결과 (3회차 기준, 4회차 변경 반영)
| 항목 | 결과 |
|---|---|
| 추가 테스트 `python3 -m unittest prompt-improver/mcp/test_imprompt_mcp.py` | **36/36 통과**(모델 호출 0, 가짜 CLI) |
| review-gate | 1회차 차단 1 → 2회차 통과 → 3회차(독립 리뷰 반영 후) 통과, **지적 0건** |
| 깨끗한 clone(`git clone` → `install.sh` 전체) | 링크·MCP 등록 ✓, clone 경로로 claude 도구 호출 성공(8.3s), codex 도구 호출 성공(27.9s) → 원래 저장소로 재설치 복구 확인 |
| `core.autocrlf=true` clone(Windows 모사) | sh·py·pi-edit CRLF 0줄, ps1 CRLF·BOM 유지 |
| claude 에서 MCP 호출 | 성공 — 엔진 claude 9~14s, 입력 ~1.67k·출력 0.7~0.8k 토큰 |
| codex 에서 MCP 호출 | 성공 — 엔진 codex 28s, 13.8~14.7k 토큰(Codex 자체 도구 정의 포함, 기본 지시문 교체 후) |
| gemini 에서 MCP 호출 | **미실측** — 무료 등급 계정에서는 gemini CLI 자체가 모델 호출 불가(`IneligibleTierError`)라 실응답 미확인. 등록·로그인·엔진 실패 안내까지 확인. 실호출은 지원 등급 계정 환경에서 확인 예정(2026-10-29 결정) |

## 5. OS별 검증 여부
| OS | 상태 | 근거 |
|---|---|---|
| macOS 27 (bash 3.2·python 3.9) | **실측** | 단위 테스트 전부, 실제 claude·codex 등록·도구 호출, gemini 등록·미로그인 안내 |
| Linux | 미실측(정적+경로 테스트) | Docker 없음. 같은 POSIX 코드 경로(bash·python3·`start_new_session`/`killpg`)를 macOS 에서 실행 |
| Windows | 미실측(정적+경로 테스트) | Git Bash 분기를 가짜 `cygpath`·`OSTYPE=msys` 로 실행해 `C:\…\imprompt_mcp.py` 등록 확인, `install.ps1` BOM·등록 인자 정적 검사. `.cmd` 실행·`taskkill`·PowerShell 실행은 실기 미확인 |

## 6. 남은 리스크
1. **gemini 실호출 미확인 + 지원 범위 축소**: Google 이 무료 Gemini Code Assist(개인) 등급의 gemini CLI 사용을 막음(Antigravity 이전 안내, 2026 실측·GitHub google-gemini/gemini-cli#28229 에 Google AI Pro 사용자 보고도 있음). gemini 엔진·호스트는 지원 등급 계정에서만 의미가 있고, 엔진 플래그(`GEMINI_SYSTEM_MD`·`--approval-mode plan`·`--allowed-mcp-server-names`·`-e none`·`--skip-trust`)의 실제 응답은 미확인. 다른 사용자 환경에서 `gemini -p "improve_prompt 도구로 개선: …" < /dev/null` 1회로 확인.
2. **Windows·Linux 실기 미실측**: `.cmd` 실행·`taskkill /T`·PowerShell 5.1 실행·Store판 Python(`WindowsApps` 경로)·pyenv shim. 경로 처리·줄바꿈은 테스트로 확인.
3. **Codex 엔진 토큰**: 1회 ~14k(대부분 Codex 기본 도구 정의). claude 엔진(~2.4k)의 약 6배 — 토큰을 아끼려면 codex 안에서도 `IMPROMPT_ENGINE=claude` 지정 가능(구독 둘 다 있을 때).
4. **Codex `model_instructions_file`**: 문서화된 help 항목이 아니라 실측으로 확인한 설정 키 — Codex 업데이트로 이름이 바뀌면 무시되고(경고만) 토큰이 18k로 돌아간다(동작은 유지).
5. **호스트 도구 제한**: Codex 기본 60초 가정(55초로 맞춤). 각 호스트 버전에 따라 다를 수 있음.
6. **캐시에 개선본 저장**(`~/.imprompt/cache`, 700/600, TTL `IMPROMPT_CACHE_TTL` 기본 24h, 200개) — 공유 PC 라면 `IMPROMPT_CACHE=0`.
7. **보안 점검 잔여(5회차)**: 출력 후검사는 패턴·엔트로피 기반이라 모양이 다른 비밀(짧은 비밀번호·평문 한 줄)은 못 잡는다 — 도구 차단이 1차 방어. gemini 도구 차단은 실응답 미확인. Windows 실행 파일 방어는 로직 테스트뿐(실기 미확인). 프로젝트 하위 폴더에 설치한 CLI(`./node_modules/.bin/claude` 등)는 cwd 가 프로젝트일 때 거부된다 — `IMPROMPT_<NAME>_BIN` 으로 지정. pi-edit 자체의 Windows(Git Bash) 실행 파일 탐색은 범위 밖.

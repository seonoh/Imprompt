#!/usr/bin/env python3
"""다운스트림 실험: 같은 과제를 (raw) 원문 그대로 / (improved) pi-edit 개선본으로 Claude Code 헤드리스에 주고 에이전트 효율을 비교.
사용: run.py <라벨> [--tasks T1,T2,T3] [--conds raw,improved] [--improvers claude,codex] [--reps 1] [--max-turns 25] [--pi PI_EDIT]
  --improvers: improved 조건에서 개선을 맡길 구독 엔진(pi-edit 의 PI_ENGINE). 에이전트(작업자)는 항상 claude -p(설정 모델·effort).
  질문 단계: 사람이 없으므로 PI_ASK_ANSWER=""(질문마다 권장 보기를 고름)로 고정 — '질문 후 보강' 경로가 터미널 없이도 끝까지 돈다.
지표(에이전트 쪽, stream-json 에서 집계):
  turns           num_turns(결과 이벤트)
  explore         탐색 도구 호출 수: Read·Grep·Glob·LS + 읽기용 Bash(ls·find·cat·grep·rg·head·tail·sed -n·tree)
  first_edit      첫 Edit/Write/MultiEdit 가 나온 어시스턴트 메시지 순번(1부터, 없으면 null) = 첫 착수까지 걸린 턴
  asked_back      편집 없이 끝났고 마지막 답이 사용자에게 묻는 형태(물음표·'할까요' 등) = 되묻기
  pass            숨은 채점(checks/check.py)의 모든 항목 참
개선기 쪽: improver.sec·chars·questions(질문 블록 줄 수, invocations.log 의 마지막 ask 줄). 결과 out/<라벨>.json
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser(); ap.add_argument("label"); ap.add_argument("--tasks", default="T1,T2,T3")
ap.add_argument("--conds", default="raw,improved"); ap.add_argument("--improvers", default="claude")
ap.add_argument("--reps", type=int, default=1); ap.add_argument("--max-turns", type=int, default=25)
ap.add_argument("--pi", default=os.path.join(os.path.dirname(os.path.dirname(HERE)), "pi-edit"))
a = ap.parse_args()
env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDECODE")}
env.update(PI_COPY_WAIT="0", PI_ASK_ANSWER="", PI_HISTORY="0")   # 완료 줄 대기 끔 · 질문엔 권장 보기 · 대화 기록 없음(고정 입력)
LOG = os.path.expanduser("~/.claude/prompt-improver/invocations.log")
EXPLORE = {"Read", "Grep", "Glob", "LS"}
EDIT = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
READ_SH = re.compile(r"^\s*(ls|find|cat|grep|rg|head|tail|tree|wc|sed\s+-n)\b")
ASK = re.compile(r"\?\s*$|할까요|하시겠|원하시|알려\s*주|확인해\s*주|어느\s*쪽|선택해", re.M)


def log_tail(n=40):
    try:
        with open(LOG, encoding="utf-8", errors="replace") as fh:
            return fh.readlines()[-n:]
    except OSError:
        return []


def agent_metrics(stream):
    """claude -p --output-format stream-json 줄들 → (결과 이벤트, 지표)."""
    res, explore, first_edit, nmsg, edited = {}, 0, None, 0, False
    for line in stream.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "result":
            res = ev
        if ev.get("type") != "assistant":
            continue
        nmsg += 1
        for blk in (ev.get("message") or {}).get("content") or []:
            if blk.get("type") != "tool_use":
                continue
            name, inp = blk.get("name"), blk.get("input") or {}
            if name in EXPLORE or (name == "Bash" and READ_SH.search(str(inp.get("command", "")))):
                explore += 1
            if name in EDIT:
                edited = True
                if first_edit is None:
                    first_edit = nmsg
    tail = str(res.get("result", ""))[-400:]
    return res, dict(explore=explore, first_edit=first_edit, asked_back=(not edited) and bool(ASK.search(tail)))


os.makedirs(os.path.join(HERE, "out"), exist_ok=True); rows = []
plan = [("raw", None)] if "raw" in a.conds.split(",") else []
if "improved" in a.conds.split(","):
    plan += [("improved", e) for e in a.improvers.split(",")]
for rep in range(1, a.reps + 1):
    for t in a.tasks.split(","):
        raw = open(os.path.join(HERE, "tasks", t + ".txt"), encoding="utf-8").read().strip()
        for cond, eng in plan:
            work = tempfile.mkdtemp(prefix=f"ds-{t}-{cond}-"); shutil.copytree(os.path.join(HERE, "fixture"), work, dirs_exist_ok=True)
            subprocess.run(["git", "init", "-q"], cwd=work); subprocess.run(["git", "add", "-A"], cwd=work)
            subprocess.run(["git", "-c", "user.email=x@x", "-c", "user.name=x", "commit", "-qm", "init"], cwd=work)
            prompt, imp = raw, None
            if cond == "improved":
                # 입력창 임시 파일은 실제처럼 작업 폴더 밖(임시 폴더)에 — 안에 두면 개선기가 프로젝트 파일로 보고 "먼저 읽어라"를 쓴다(2026-11-04 기준값 오염)
                f = os.path.join(tempfile.mkdtemp(prefix="ds-in-"), "claude-prompt-ds.md"); open(f, "w", encoding="utf-8").write(raw + "\n")
                before = len(log_tail(100000))
                t0 = time.perf_counter()
                subprocess.run(["bash", a.pi, f], cwd=work, env=dict(env, PI_ENGINE=eng), stdin=subprocess.DEVNULL, capture_output=True, timeout=400)
                prompt = open(f, encoding="utf-8").read(); os.unlink(f)
                new = log_tail(100000)[before:]
                imp = dict(engine=eng, sec=round(time.perf_counter() - t0, 1), chars=len(prompt),
                           asked=any(" ask " in l or " ask-" in l for l in new),
                           log=[l.strip()[20:] for l in new if " ok " in l or " ask" in l or "FAIL" in l][-3:])
            t0 = time.perf_counter()
            p = subprocess.run(["claude", "-p", prompt, "--permission-mode", "acceptEdits", "--max-turns", str(a.max_turns), "--no-session-persistence",
                                "--output-format", "stream-json", "--verbose"], cwd=work, env=env, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1800)
            wall = round(time.perf_counter() - t0, 1)
            j, m = agent_metrics(p.stdout)
            u = j.get("usage", {}) or {}
            chk = subprocess.run([sys.executable, os.path.join(HERE, "checks", "check.py"), t, work], capture_output=True, text=True)
            try: check = json.loads(chk.stdout)
            except Exception: check = {"check_fail": chk.stdout[-200:] + chk.stderr[-200:]}
            ok = [v for k, v in check.items() if isinstance(v, bool)]
            row = dict(rep=rep, task=t, cond=cond if not eng else f"improved:{eng}", turns=j.get("num_turns"), **m,
                       passed=bool(ok) and all(ok) and "error" not in check and "check_fail" not in check, wall_s=wall,
                       in_tok=(u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0),
                       out_tok=u.get("output_tokens"), cost_usd=round(j.get("total_cost_usd", 0) or 0, 3), is_error=j.get("is_error"),
                       result_tail=str(j.get("result", ""))[-200:], check=check, improver=imp, prompt=prompt, workdir=work)
            rows.append(row); print(json.dumps({k: v for k, v in row.items() if k != "prompt"}, ensure_ascii=False), flush=True)
            json.dump(rows, open(os.path.join(HERE, "out", a.label + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)

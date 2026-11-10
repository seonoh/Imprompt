#!/usr/bin/env python3
"""비교 벤치 실행: cases.jsonl 을 (a) 기준 커밋 스킬 / (b) 작업 트리 스킬 / (c) 일반 에이전트로 처리해 출력·토큰을 남긴다.

사용:
  run.py a --ref <커밋>       # 기준 커밋의 pi-edit·instructions.md·ask.md
  run.py b                   # 작업 트리의 같은 파일
  run.py c                   # claude -p "이 프롬프트를 개선해줘" (기본 시스템 프롬프트·CLAUDE.md·읽기 도구)
  run.py d                   # codex exec 같은 지시문 (read-only, 저장소 cwd, config 모델·effort)
  옵션: --label 이름(기본 = 시스템 문자) --jobs 4 --only id,id --sys-dir 폴더(b 를 작업 트리 대신 그 폴더의 규칙으로)
결과: bench/out/compare/<label>/<id>.txt(출력) · <id>.json(토큰·호출·질문 수·수락한 권장 답)
기준·채점은 rubric.md, 채점은 score.py. (a)·(b)는 실제 Ctrl+Q 경로 그대로(게이트·질문 모드), 답은 Enter=전부 권장.
"""
import argparse, concurrent.futures as cf, json, os, re, shutil, subprocess, sys, tempfile, time, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))           # 저장소 루트 = 개선 대상 프로젝트(<프로젝트> 블록 기준)
PI_DIR = os.path.join(ROOT, "prompt-improver")
SYS_FILES = ("pi-edit", "instructions.md", "ask.md", "ask-menu.pl")
for _st in (sys.stdout, sys.stderr):
    try: _st.reconfigure(encoding="utf-8", errors="replace")
    except Exception: pass

ap = argparse.ArgumentParser()
ap.add_argument("system", choices=("a", "b", "c", "d"))
ap.add_argument("--ref", help="(a) 기준 커밋(필수)")
ap.add_argument("--label"); ap.add_argument("--jobs", type=int, default=4); ap.add_argument("--only")
ap.add_argument("--sys-dir", help="(b) 규칙·스크립트를 이 폴더에서 복사(자동 수정 루프용)")
ap.add_argument("--effort", default="medium", help="(c) effort — (a)·(b) 2차 기본과 맞춤")
x = ap.parse_args()
if x.system == "a" and not x.ref:
    ap.print_usage(sys.stderr); print("a 는 --ref <기준 커밋>이 필요합니다", file=sys.stderr); sys.exit(2)
label = x.label or x.system
out = os.path.join(PI_DIR, "bench", "out", "compare", label); os.makedirs(out, exist_ok=True)
REAL_CLAUDE = shutil.which("claude") or sys.exit("claude CLI 없음")
AGENT_ASK = "이 프롬프트를 개선해줘"                                         # (c)·(d) 공통 지시문

def load_cases():
    cs = [json.loads(l) for l in open(os.path.join(HERE, "cases.jsonl"), encoding="utf-8") if l.strip()]
    for c in cs:
        if "file" in c: c["text"] = open(os.path.join(HERE, c["file"]), encoding="utf-8").read()
    if x.only: cs = [c for c in cs if c["id"] in x.only.split(",")]
    return cs

def clean_env(**kw):
    e = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDECODE", "CLAUDE_CODE_SESSION_ID")}
    e.update(kw); return e

def usage_of(j):
    u = j.get("usage") or {}
    return dict(in_tok=(u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0),
                out_tok=u.get("output_tokens") or 0, cost=j.get("total_cost_usd") or 0, models=list((j.get("modelUsage") or {}).keys()))

# ── (a)·(b): pi-edit 실경로. PATH 앞에 claude 래퍼를 끼워 호출마다 응답 JSON 을 남긴다(병렬 안전: 케이스별 폴더)
def prep_skill():
    sysdir = os.path.join(out, "_sys"); os.makedirs(sysdir, exist_ok=True)
    for f in SYS_FILES:
        dst = os.path.join(sysdir, f)
        if x.system == "a":
            blob = subprocess.run(["git", "show", f"{x.ref}:prompt-improver/{f}"], cwd=ROOT, capture_output=True, check=True).stdout
            open(dst, "wb").write(blob)
        else:
            shutil.copy(os.path.join(x.sys_dir or PI_DIR, f), dst)
    os.chmod(os.path.join(sysdir, "pi-edit"), 0o755)
    shim = os.path.join(out, "_bin"); os.makedirs(shim, exist_ok=True)
    open(os.path.join(shim, "claude"), "w").write(f"""#!/bin/bash
n=$(date +%s)-$$-$RANDOM; printf '%s\\n' "$*" > "$BENCH_CALLS/$n.args"
"{REAL_CLAUDE}" "$@" | tee "$BENCH_CALLS/$n.json"
exit ${{PIPESTATUS[0]}}
""")
    os.chmod(os.path.join(shim, "claude"), 0o755)
    return sysdir, shim

def session_fixture(c):
    """대화 지시어 케이스: 이 저장소 프로젝트 폴더에 임시 세션 jsonl 을 두고 CLAUDE_CODE_SESSION_ID 로 고정 (끝나면 삭제)."""
    if not c.get("history"): return None, None
    pdir = os.path.join(os.path.expanduser("~/.claude/projects"), re.sub(r"[/.]", "-", ROOT)); os.makedirs(pdir, exist_ok=True)
    sid = "bench-" + uuid.uuid4().hex[:12]; path = os.path.join(pdir, sid + ".jsonl")
    with open(path, "w", encoding="utf-8") as f:
        for role, text in c["history"]:
            msg = {"content": text} if role == "user" else {"content": [{"type": "text", "text": text}]}
            f.write(json.dumps({"type": role, "message": msg}, ensure_ascii=False, separators=(",", ":")) + "\n")   # 실제 세션 jsonl 처럼 공백 없이
    return sid, path

def run_skill(c, sysdir, shim):
    calls = tempfile.mkdtemp(prefix="calls-", dir=out)
    tmp = tempfile.NamedTemporaryFile("w", prefix="claude-prompt-bench-", suffix=".md", delete=False, encoding="utf-8")
    tmp.write(c["text"]); tmp.close()
    sid, sfile = session_fixture(c)
    env = clean_env(PATH=shim + os.pathsep + os.environ["PATH"], BENCH_CALLS=calls, PI_ENGINE="claude", PI_COPY_WAIT="0",
                    PI_ASK_ANSWER="", PI_FALLBACK="0", PI_HISTORY="1" if sid else "0")
    if sid: env["CLAUDE_CODE_SESSION_ID"] = sid
    t0 = time.perf_counter()
    try:
        subprocess.run(["bash", os.path.join(sysdir, "pi-edit"), tmp.name], cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                       capture_output=True, timeout=400)
    finally:
        if sfile and os.path.exists(sfile): os.unlink(sfile)
    wall = time.perf_counter() - t0
    result = open(tmp.name, encoding="utf-8").read(); os.unlink(tmp.name)
    meta = dict(id=c["id"], type=c["type"], system=x.system, wall_s=round(wall, 1), calls=[], in_tok=0, out_tok=0, cost=0.0,
                ask_questions=0, answers=[], models=[])
    for fn in sorted(os.listdir(calls)):
        if not fn.endswith(".json"): continue
        args = open(os.path.join(calls, fn[:-5] + ".args"), encoding="utf-8").read()
        try: j = json.loads(open(os.path.join(calls, fn), encoding="utf-8").read())
        except Exception: meta["calls"].append(dict(kind="?", error="응답 JSON 파싱 실패")); continue
        kind = "ask" if "--effort low" in args else "main"; u = usage_of(j)
        meta["calls"].append(dict(kind=kind, **u)); meta["in_tok"] += u["in_tok"]; meta["out_tok"] += u["out_tok"]; meta["cost"] += u["cost"]
        meta["models"] = sorted(set(meta["models"]) | set(u["models"]))
        if kind == "ask":
            res = j.get("result") or ""
            qs = [l for l in res.splitlines() if re.match(r"^[0-9]\)", l)][:3]                 # pi-edit 과 같이 최대 3개
            if not re.search(r"^\s*READY", res, re.M) and qs:
                meta["ask_questions"] = len(qs)
                for q in qs:   # Enter=전부 권장 → [1] 선택지 수락
                    m = re.search(r"\[1\]\s*([^\[]*)", q); qt = re.sub(r"^[0-9]\)\s*|\s*\[1\].*$", "", q)
                    meta["answers"].append(f"{qt.strip()} → {(m.group(1).strip() if m else '선택지 1')}")
    shutil.rmtree(calls, ignore_errors=True)
    meta["skipped"] = not meta["calls"] and result == c["text"]                                 # 0토큰 게이트 통과
    meta["failed"] = not meta["skipped"] and (result == c["text"] or not any(k["kind"] == "main" for k in meta["calls"]))
    meta["cost"] = round(meta["cost"], 4)
    return result, meta

# ── (c): 일반 에이전트
def run_agent(c):
    hist = ""
    if c.get("history"):
        hist = "이전 대화:\n" + "\n".join(("사용자: " if r == "user" else "에이전트: ") + t for r, t in c["history"]) + "\n\n"
    prompt = f"{hist}{AGENT_ASK}:\n\n{c['text']}"
    t0 = time.perf_counter()
    p = subprocess.run([REAL_CLAUDE, "-p", "--effort", x.effort, "--setting-sources", "project", "--strict-mcp-config",
                        "--allowedTools", "Read", "Glob", "Grep", "--no-session-persistence", "--output-format", "json"],
                       input=prompt, cwd=ROOT, env=clean_env(), capture_output=True, text=True, encoding="utf-8", timeout=400)
    wall = time.perf_counter() - t0
    meta = dict(id=c["id"], type=c["type"], system="c", wall_s=round(wall, 1), ask_questions=0, answers=[], skipped=False)
    try:
        j = json.loads(p.stdout); u = usage_of(j)
        meta.update(in_tok=u["in_tok"], out_tok=u["out_tok"], cost=round(u["cost"], 4), models=u["models"],
                    turns=j.get("num_turns"), failed=bool(j.get("is_error")))
        return (j.get("result") or "").strip() + "\n", meta
    except Exception as e:
        meta.update(failed=True, error=(p.stderr or str(e))[-300:]); return "", meta

# ── (d): 일반 에이전트(Codex) — (c)와 같은 지시문, read-only 샌드박스, 저장소 cwd, config 모델·effort
def codex_model():
    cfg = os.path.expanduser("~/.codex/config.toml"); m = e = "?"
    if os.path.exists(cfg):
        for l in open(cfg, encoding="utf-8"):
            mm = re.match(r'\s*model\s*=\s*"([^"]+)"', l); ee = re.match(r'\s*model_reasoning_effort\s*=\s*"([^"]+)"', l)
            if mm and m == "?": m = mm.group(1)
            if ee and e == "?": e = ee.group(1)
    return m, e

def run_codex_agent(c):
    hist = ""
    if c.get("history"):
        hist = "이전 대화:\n" + "\n".join(("사용자: " if r == "user" else "에이전트: ") + t for r, t in c["history"]) + "\n\n"
    t0 = time.perf_counter()
    p = subprocess.run(["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-C", ROOT, "--ephemeral", "--json", "-"],
                       input=f"{hist}{AGENT_ASK}:\n\n{c['text']}", cwd=ROOT, env=clean_env(), capture_output=True, text=True, encoding="utf-8", timeout=600)
    wall = time.perf_counter() - t0; m, e = codex_model()
    meta = dict(id=c["id"], type=c["type"], system="d", wall_s=round(wall, 1), ask_questions=0, answers=[], skipped=False,
                models=[f"{m} (effort {e})"], cost=0.0, in_tok=0, out_tok=0)
    text = ""; done = False; err = []
    for line in p.stdout.splitlines():
        try: ev = json.loads(line)
        except Exception: continue
        if ev.get("type") in ("turn.failed", "error"): err.append(json.dumps(ev, ensure_ascii=False)[:200])   # 최상위 실패 이벤트(훅 경고 item.error 는 제외)
        if ev.get("type") == "item.completed" and (ev.get("item") or {}).get("type") == "agent_message": text = ev["item"].get("text", "")
        if ev.get("type") == "turn.completed":
            done = True
            u = ev.get("usage") or {}
            meta["in_tok"] += u.get("input_tokens") or 0                                  # cached 포함 합계
            meta["out_tok"] += (u.get("output_tokens") or 0) + (u.get("reasoning_output_tokens") or 0)
    meta["failed"] = p.returncode != 0 or bool(err) or not done or not text.strip()   # 중간 안내 메시지만 남고 실패한 경우도 실패
    if meta["failed"]: meta["error"] = (" | ".join(err) or f"rc={p.returncode} turn.completed={done}") + " " + (p.stderr or "")[-200:]
    return text.strip() + "\n", meta

def one(c, sk):
    res, meta = run_agent(c) if x.system == "c" else (run_codex_agent(c) if x.system == "d" else run_skill(c, *sk))
    open(os.path.join(out, c["id"] + ".txt"), "w", encoding="utf-8").write(res)
    json.dump(meta, open(os.path.join(out, c["id"] + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    flag = "SKIP" if meta.get("skipped") else ("FAIL" if meta.get("failed") else "ok")
    print(f"{c['id']:<11} {flag:<4} in={meta.get('in_tok', 0):>6} out={meta.get('out_tok', 0):>5} q={meta['ask_questions']} wall={meta['wall_s']}s", flush=True)
    return meta

sk = prep_skill() if x.system in ("a", "b") else None
with cf.ThreadPoolExecutor(max_workers=x.jobs) as ex:
    metas = list(ex.map(lambda c: one(c, sk), load_cases()))
bad = [m["id"] for m in metas if m.get("failed")]
print(f"[{label}] {len(metas)}건 · 실패 {len(bad)}" + (f": {', '.join(bad)}" if bad else ""))
sys.exit(1 if bad else 0)

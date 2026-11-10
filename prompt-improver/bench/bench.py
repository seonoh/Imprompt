#!/usr/bin/env python3
"""프롬프트 개선기 벤치: samples/*.txt 를 실제 pi-edit 경로로 돌려(프로젝트 인식·폴백 포함) 소요시간·토큰을 잰다.

사용: bench.py <라벨> [--samples DIR] [--cwd 프로젝트폴더] [--engine claude|codex] [--model M] [--effort E]
  결과: out/<라벨>/<샘플>.txt (개선본) + out/<라벨>/_summary.json. 수치는 pi-edit 이 invocations.log 에 남긴 결과 줄에서 읽는다.
  모델·effort 기본값은 pi-edit 과 같이 각 도구 설정. --cwd 는 <프로젝트> 블록의 기준 폴더(기본: 이 저장소).
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
for _st in (sys.stdout, sys.stderr):  # 콘솔이 ASCII/CP949 여도 한글 출력에서 죽지 않게
    try: _st.reconfigure(encoding="utf-8", errors="replace")
    except Exception: pass
ap = argparse.ArgumentParser()
ap.add_argument("label")
ap.add_argument("--samples", default=os.path.join(HERE, "samples"))
ap.add_argument("--cwd", default=os.path.abspath(os.path.join(HERE, "..", "..")))
ap.add_argument("--engine", default="claude"); ap.add_argument("--model"); ap.add_argument("--effort")
ap.add_argument("--pi", help="다른 pi-edit(옆의 instructions.md 사용) — 규칙 초안 비교용")
a = ap.parse_args()

PI = a.pi or os.path.join(HERE, "..", "pi-edit")
LOG = os.path.expanduser("~/.claude/prompt-improver/invocations.log")
out_dir = os.path.join(HERE, "out", a.label); os.makedirs(out_dir, exist_ok=True)
env = dict(os.environ, PI_ENGINE=a.engine, PI_COPY_WAIT="0", PI_KEEP_ANSWERS="1")  # 답 블록을 last-answers.txt 로 남겨 심사에 쓴다(평소엔 남기지 않음)  # 완료 줄(c=복사) 대기 끔
env.setdefault("PI_HISTORY", "0")  # 측정 오염 방지: 실행 중인 세션의 대화 문맥을 섞지 않음(필요하면 PI_HISTORY=1)
if a.model: env["PI_MODEL"] = a.model
if a.effort: env["PI_EFFORT"] = a.effort
rows, failures, skips = [], [], []
for sf in sorted(glob.glob(os.path.join(a.samples, "*.txt"))):
    name = os.path.basename(sf)
    # Claude 입력창 임시파일처럼 보이는 이름이어야 pi-edit 이 개선 대상으로 본다
    tmp = tempfile.NamedTemporaryFile("w", prefix="claude-prompt-bench-", suffix=".md", delete=False, encoding="utf-8")
    tmp.write(open(sf, encoding="utf-8").read()); tmp.close()
    before = os.path.getsize(LOG) if os.path.exists(LOG) else 0   # 바이트 오프셋 (아래서 바이트로 읽어 자른다)
    t0 = time.perf_counter()
    subprocess.run(["bash", PI, tmp.name], cwd=a.cwd, env=env, stdin=subprocess.DEVNULL,
                   capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=400)
    wall = time.perf_counter() - t0
    tail = open(LOG, "rb").read()[before:].decode("utf-8", "replace") if os.path.exists(LOG) else ""
    m = re.search(r" ok engine=(\S+) wall_s=(\S+) (.*?) ctx=(\d+)(?: \w+=\S*)* chars=(\d+)->(\d+)", tail)  # ctx 와 chars 사이 필드(sess·sid…)는 건너뜀
    result = open(tmp.name, encoding="utf-8").read(); os.unlink(tmp.name)
    sk = re.search(r" skip (.*?) chars=\d+", tail)
    if sk:  # 0토큰 게이트 통과 — 결과는 원문 그대로, 비용 0 (평균에는 포함하지 않고 별도 표시)
        row = dict(sample=name, skipped=True, reason=sk.group(1), wall_s=round(wall, 1))
        skips.append(row); print(json.dumps(row, ensure_ascii=False), flush=True); continue
    if not m:
        fail = dict(sample=name, failed=True, log=tail.strip()[-300:])
        failures.append(fail); print(json.dumps(fail, ensure_ascii=False), flush=True); continue
    open(os.path.join(out_dir, name), "w", encoding="utf-8").write(result)
    ansf = os.path.expanduser("~/.claude/prompt-improver/last-answers.txt")
    ans = open(ansf, encoding="utf-8").read() if os.path.exists(ansf) else ""
    if ans.strip(): open(os.path.join(out_dir, name + ".answers.txt"), "w", encoding="utf-8").write(ans)
    kv = dict(x.split("=", 1) for x in m.group(3).split())
    row = dict(sample=name, engine=m.group(1), model=kv.get("model"), effort=kv.get("effort"),
               wall_s=round(wall, 1), api_s=float(kv.get("api_s", 0) or 0), in_tok=int(kv.get("in", 0) or 0),
               out_tok=int(kv.get("out", 0) or 0), think_tok=kv.get("think"), ctx_chars=int(m.group(4)),
               chars=int(m.group(6)), cost_usd=float(kv.get("cost", 0) or 0))
    rows.append(row); print(json.dumps(row, ensure_ascii=False), flush=True)
json.dump(rows + skips + failures, open(os.path.join(out_dir, "_summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
if rows:
    n = len(rows)
    print(f"avg wall_s={sum(r['wall_s'] for r in rows)/n:.1f} api_s={sum(r['api_s'] for r in rows)/n:.1f} in={sum(r['in_tok'] for r in rows)//n} out={sum(r['out_tok'] for r in rows)//n} (성공 {n}건 기준)")
if skips:
    print("게이트 통과(0토큰): " + ", ".join(f"{r['sample']}({r['reason']})" for r in skips))
if failures:
    print(f"실패 {len(failures)}건 — 평균에서 제외: " + ", ".join(f['sample'] for f in failures), file=sys.stderr); sys.exit(1)

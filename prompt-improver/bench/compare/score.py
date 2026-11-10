#!/usr/bin/env python3
"""비교 벤치 채점·결과표: rubric.md 기준(5항목 × 0~2점)으로 run.py 결과를 채점하고 유형별 표를 낸다.

사용: score.py a b c [--judge-model sonnet] [--jobs 4] [--rejudge]
  LLM 심사(의도·사실·실행 가능성)는 bench/out/compare/<label>/<id>.score.json 에 캐시(--rejudge 로 다시).
  자동 판정(질문 수·길이·형식·지어낸 경로)은 매번 계산. 결과표: bench/out/compare/report-<labels>.md
"""
import argparse, concurrent.futures as cf, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "prompt-improver", "bench", "out", "compare")
for _st in (sys.stdout, sys.stderr):
    try: _st.reconfigure(encoding="utf-8", errors="replace")
    except Exception: pass
def parse_args(argv=None):
    ap = argparse.ArgumentParser(); ap.add_argument("labels", nargs="+")
    ap.add_argument("--judge-model", default="sonnet"); ap.add_argument("--jobs", type=int, default=4); ap.add_argument("--rejudge", action="store_true")
    ap.add_argument("--passes", type=int, default=3, help="LLM 심사 반복 횟수(평균) — 심사관 편차 완화, 세 방식에 동일 적용")
    return ap.parse_args(argv)
x = None                                                                   # main() 에서 설정 — 다른 스크립트는 auto()·fabricated_paths() 등만 import

rub = open(os.path.join(HERE, "rubric.md"), encoding="utf-8").read()
JUDGE = rub.split("<!-- JUDGE_PROMPT_START -->")[1].split("<!-- JUDGE_PROMPT_END -->")[0].strip()
cases = [json.loads(l) for l in open(os.path.join(HERE, "cases.jsonl"), encoding="utf-8") if l.strip()]
for c in cases:
    if "file" in c: c["text"] = open(os.path.join(HERE, c["file"]), encoding="utf-8").read()
FILES = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
BASES = {os.path.basename(f) for f in FILES}
TOPS = {f.split("/")[0] for f in FILES if "/" in f}
DOCS = "".join(open(os.path.join(ROOT, f), encoding="utf-8").read() for f in ("README.md", "CLAUDE.md"))   # 런타임 경로(~/.claude/…)는 문서에 있으면 사실
fn = re.search(r"^project_ctx\(\) \{.*?^\}", open(os.path.join(ROOT, "prompt-improver", "pi-edit"), encoding="utf-8").read(), re.S | re.M).group(0)
PROJECT = subprocess.run(["bash", "-c", fn + "\nproject_ctx"], cwd=ROOT, capture_output=True, text=True).stdout.strip()

# ── 자동 판정 (rubric.md "자동 판정 세부")
def limit_of(c):
    t = c["text"].strip()
    if c["type"] == "brief": return 10
    if c["type"] == "structured": return len([l for l in t.splitlines() if l.strip()]) + 6
    if c["type"] == "short" or len(t.split()) <= 8: return 14
    return 22
PREFACE = re.compile(r"^(다음은|아래는|개선된 프롬프트|개선한 프롬프트|개선본|here is|here's|improved prompt|revised prompt)", re.I)
CLOSING = re.compile(r"(필요하면|필요하시면|도움이 되|원하시면|말씀해|let me know|hope this|feel free)", re.I)
PATH = re.compile(r"(?<![\w/~.-])(~?/?[\w.-]+(?:/[\w.-]*)+|[\w-]+\.(?:py|sh|md|json|jsonl|pl|toml|js|ts|tsx|html|css|yml|yaml|txt|log|cmd))(?![\w/])")
OKMARK = re.compile(r"가정|확인|예:|예\)|e\.g\.|예를 들|새로|신규|만들|생성|추가할|없으면|create|new |if ")

def fabricated_paths(text, c):
    known = c["text"] + "".join(t for _, t in c.get("history", []))
    bad = []
    for line in text.splitlines():
        if OKMARK.search(line): continue
        for tok in PATH.findall(line):
            t = tok.strip("`'\".,:;()").rstrip("/")
            if not t or "://" in line or re.search(r"[<>*{}]", t) or t in ("/", "~") or re.fullmatch(r"[\d./-]+", t): continue
            has_ext = re.search(r"\.(py|sh|md|json|jsonl|pl|toml|js|ts|tsx|html|css|yml|yaml|txt|log|cmd)$", t)
            if not (has_ext or t.startswith(("~/", "./", "/")) or t.split("/")[0] in TOPS): continue   # "bcrypt/argon2" 같은 병기 낱말 제외
            if t in known or t in DOCS or os.path.basename(t) in BASES or any(f == t or f.startswith(t + "/") or f.endswith("/" + t) for f in FILES): continue
            if re.fullmatch(r"(and|or|및|또는|이나)/.*|.*/(s|es)", t, re.I): continue   # "읽기/쓰기" 류 낱말
            if re.search(r"[가-힣]", t): continue                                       # 한글이 섞인 "설정/코드" 류
            bad.append(t)
    return sorted(set(bad))

def auto(c, text, meta):
    lines = [l for l in text.splitlines() if l.strip()]
    lim = limit_of(c); n = len(lines)
    fmt = []
    if "```" in text: fmt.append("코드펜스")
    if lines and PREFACE.search(lines[0].strip("#* ")): fmt.append("서문")
    if lines and CLOSING.search(lines[-1]): fmt.append("맺음말")
    if lines and (lines[0].strip() == "---" or lines[-1].strip() == "---"): fmt.append("구분선")
    length = 2 if n <= lim else (1 if n <= lim * 1.5 else 0)
    length = max(0, length - (1 if fmt else 0))
    qc = meta.get("ask_questions", 0) + text.count("[확인 필요") + sum(1 for l in lines if "[확인 필요" not in l and re.search(r"\?\)?\s*$", l))
    lo, hi = c["q"]; d = 0 if lo <= qc <= hi else min(abs(qc - lo), abs(qc - hi))
    qs = 2 if d == 0 else (1 if d == 1 else 0)
    fab = fabricated_paths(text, c)
    return dict(lines=n, limit=lim, fmt=fmt, length=length, qcount=qc, questions=qs, fabricated=fab, fact_cap=2 if not fab else (1 if len(fab) == 1 else 0))

# ── LLM 심사 (절대 평가, 방식 비공개)
env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDECODE")}
def judge_input(c, text, meta):
    parts = [f"<원문>\n{c['text'].strip()}\n</원문>", PROJECT, "<저장소 파일>\n" + "\n".join(FILES) + "\n</저장소 파일>"]
    if c.get("history"): parts.append("<대화>\n" + "\n".join(("사용자: " if r == "user" else "에이전트: ") + t for r, t in c["history"]) + "\n</대화>")
    if meta.get("answers"): parts.append("<수락된 권장 답>\n" + "\n".join("- " + a for a in meta["answers"]) + "\n</수락된 권장 답>")
    parts.append(f"<개선본>\n{text.strip()}\n</개선본>")
    return "\n\n".join(parts)

def judge(inp):
    for _ in range(2):
        p = subprocess.run(["claude", "-p", "--model", x.judge_model, "--effort", "low", "--system-prompt", JUDGE, "--tools", "",
                            "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands", "--output-format", "json"],
                           input=inp, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=300)
        try:
            res = json.loads(p.stdout).get("result", ""); j = json.loads(res[res.index("{"): res.rindex("}") + 1])
            return {k: int(j[k]) for k in ("intent", "facts", "actionable")} | {"why": j.get("why", "")}
        except Exception: continue
    return None

def score_one(label, c):
    d = os.path.join(OUT, label); tp, mp = os.path.join(d, c["id"] + ".txt"), os.path.join(d, c["id"] + ".json")
    if not (os.path.exists(tp) and os.path.exists(mp)): return None
    text = open(tp, encoding="utf-8").read(); meta = json.load(open(mp, encoding="utf-8"))
    a = auto(c, text, meta)
    if meta.get("failed") or not text.strip():
        j = dict(intent=0, facts=0, actionable=0, why="실행 실패")
    else:
        sp = os.path.join(d, c["id"] + ".score.json")
        inp = judge_input(c, text, meta)
        key = hashlib.sha256((x.judge_model + "\0" + JUDGE + "\0" + inp).encode()).hexdigest()   # 출력·답·프로젝트 블록·지시문·모델이 같을 때만 캐시 재사용
        cache = {} if x.rejudge or not os.path.exists(sp) else json.load(open(sp, encoding="utf-8"))
        ps = cache.get("passes", []) if cache.get("key") == key else []
        while len(ps) < x.passes:
            ps.append(judge(inp) or dict(intent=0, facts=0, actionable=0, why="심사 파싱 실패"))
        ps = ps[:x.passes]; json.dump({"key": key, "passes": ps}, open(sp, "w", encoding="utf-8"), ensure_ascii=False)
        j = {k: round(sum(p[k] for p in ps) / len(ps), 2) for k in ("intent", "facts", "actionable")}
        j["why"] = " | ".join(dict.fromkeys(p["why"] for p in ps if p.get("why")))
    facts = min(j["facts"], a["fact_cap"])
    total = round(j["intent"] + facts + a["questions"] + a["length"] + j["actionable"], 2)
    return dict(label=label, id=c["id"], type=c["type"], meta=meta, auto=a, judge=j,
                items=dict(intent=j["intent"], facts=facts, questions=a["questions"], length=a["length"], actionable=j["actionable"]), total=total)

def main():
  global x
  x = parse_args()
  jobs = [(l, c) for l in x.labels for c in cases]
  with cf.ThreadPoolExecutor(max_workers=x.jobs) as ex:
      rows = [r for r in ex.map(lambda lc: score_one(*lc), jobs) if r]

  TYPES = ["short", "vague", "explicit", "deictic", "structured", "brief", "english"]
  def avg(rs, f): return sum(f(r) for r in rs) / len(rs) if rs else 0
  md = ["# 비교 벤치 결과", "", f"방식: {', '.join(x.labels)} · 심사 {x.judge_model} · 기준 rubric.md (5항목 × 0~2 = 10점)", "",
        "## 유형별 (평균: 입력 토큰 / 출력 토큰 / 품질 10점)", "",
        "| 유형 | " + " | ".join(f"{l} 입력 | {l} 출력 | {l} 품질" for l in x.labels) + " |",
        "|---|" + "---:|" * (3 * len(x.labels))]
  for t in TYPES + ["전체"]:
      cells = []
      for l in x.labels:
          rs = [r for r in rows if r["label"] == l and (t == "전체" or r["type"] == t)]
          cells += [f"{avg(rs, lambda r: r['meta'].get('in_tok', 0)):,.0f}", f"{avg(rs, lambda r: r['meta'].get('out_tok', 0)):,.0f}", f"{avg(rs, lambda r: r['total']):.2f}"]
      md.append(f"| {'**전체**' if t == '전체' else t} | " + " | ".join(cells) + " |")
  md += ["", "## 항목별 평균 (0~2) · 비용·소요", "", "| 방식 | 의도 | 사실 | 질문 수 | 길이·형식 | 실행 가능성 | 품질 | 비용 합 $ | 평균 소요 s |", "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
  for l in x.labels:
      rs = [r for r in rows if r["label"] == l]
      it = [f"{avg(rs, lambda r, k=k: r['items'][k]):.2f}" for k in ("intent", "facts", "questions", "length", "actionable")]
      md.append(f"| {l} | " + " | ".join(it) + f" | {avg(rs, lambda r: r['total']):.2f} | {sum(r['meta'].get('cost', 0) for r in rs):.3f} | {avg(rs, lambda r: r['meta'].get('wall_s', 0)):.1f} |")
  md += ["", "## 감점 사례 (항목 < 2)", ""]
  for r in sorted(rows, key=lambda r: (r["label"], r["id"])):
      lost = [k for k, v in r["items"].items() if v < 2]
      if not lost: continue
      a = r["auto"]; why = []
      if "questions" in lost: why.append(f"질문 {a['qcount']}개(기대 {dict((c['id'], c['q']) for c in cases)[r['id']]})")
      if "length" in lost: why.append(f"{a['lines']}줄/상한 {a['limit']}" + (f" 형식:{'+'.join(a['fmt'])}" if a["fmt"] else ""))
      if a["fabricated"]: why.append("지어낸 경로 " + ", ".join(a["fabricated"][:4]))
      if r["judge"].get("why"): why.append("심사: " + r["judge"]["why"])
      md.append(f"- `{r['label']}` {r['id']} ({r['total']}/10, {'·'.join(lost)}): " + " / ".join(why))
  open(os.path.join(OUT, f"report-{'-'.join(x.labels)}.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
  json.dump(rows, open(os.path.join(OUT, f"scores-{'-'.join(x.labels)}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
  print("\n".join(md))

if __name__ == "__main__":
    main()

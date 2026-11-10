#!/usr/bin/env python3
"""자동 수정·재측정 루프: Imprompt(b)가 두 일반 에이전트(c Claude · d Codex)보다 "개선본 토큰은 적고 정확도는 같거나 높게"를
train 세트에서 못 맞추면, 미달 케이스로 개선용 프롬프트를 만들어 규칙(instructions.md·ask.md)만 고치게 하고 train·validation 을 다시 잰다.

사용: loop.py [--max-iter 5] [--budget-usd 5] [--tag loop] [--c-label L] [--d-label L] [--b0-label L] [--jobs 4]
  --c-label/--d-label/--b0-label : 이미 만든 결과 라벨 재사용(예: bench_all 1회차). 없으면 새로 생성.
채택: train·validation 둘 다 "나빠지지 않음"(정확도 −0.1 이내, 개선본 토큰 +3% 이내)일 때만. 아니면 규칙 파일을 직전 채택본으로 되돌린다.
개선: 채택이면서 train 정확도 +0.1 이상 또는 train 토큰 −3% 이상. 3회 연속 개선 0 이면 중단.
비용: Claude CLI 가 보고하는 비용(b 생성 + Claude 채점 + 수정 호출)만 합산 — c·d 기준 생성은 제외, Codex 는 $ 미보고(구독).
기록: bench/out/compare/loop/<tag>/LOG.md · loop.jsonl · i<회차>/{fix-prompt.md, fixer.txt, diff.patch, report.md}
validation 케이스는 수정 프롬프트에 절대 넣지 않는다(splits.json).
"""
import argparse, datetime, json, os, shutil, statistics, subprocess, sys, time

import blind as B
import bench_all as BA

HERE = B.HERE; OUT = B.OUT; ROOT = B.S.ROOT
RULES = ["prompt-improver/instructions.md", "prompt-improver/ask.md"]
EPS_ACC, EPS_TOK, IMP_ACC, IMP_TOK = 0.1, 0.03, 0.1, 0.03

ap = argparse.ArgumentParser()
ap.add_argument("--max-iter", type=int, default=5); ap.add_argument("--budget-usd", type=float, default=5.0)
ap.add_argument("--tag", default="loop-" + datetime.date.today().isoformat()); ap.add_argument("--jobs", type=int, default=4)
ap.add_argument("--c-label"); ap.add_argument("--d-label"); ap.add_argument("--b0-label")
ap.add_argument("--no-commit", action="store_true", help="채택해도 git 커밋하지 않음")
x = ap.parse_args()

SP = json.load(open(os.path.join(HERE, "splits.json"), encoding="utf-8")); TRAIN, VAL = set(SP["train"]), set(SP["validation"])
LD = os.path.join(OUT, "loop", x.tag); os.makedirs(LD, exist_ok=True)
LOG, JL = os.path.join(LD, "LOG.md"), os.path.join(LD, "loop.jsonl")
BEST = os.path.join(LD, "best"); os.makedirs(BEST, exist_ok=True)

def log(s):
    print(s, flush=True); open(LOG, "a", encoding="utf-8").write(s + "\n")

def snapshot(dst):
    for f in RULES: shutil.copy(os.path.join(ROOT, f), os.path.join(dst, os.path.basename(f)))

def restore(src):
    for f in RULES: shutil.copy(os.path.join(src, os.path.basename(f)), os.path.join(ROOT, f))

def subset(rows, ids): return [r for r in rows if r["id"] in ids]

def stats(rows, ev=None):
    sm = B.summarize(rows, ["b", "c", "d"])
    return dict(summary=sm, verdict=B.verdict(sm, evs=[ev] if ev else ()))

def line(tag, st):
    s = st["summary"]
    return " · ".join(f"{k} 정확도 {s[k]['acc']:.2f} 토큰 {s[k]['out_tokens']:.0f} 변화율 {s[k]['change'] * 100:+.0f}%" for k in ("b", "c", "d") if k in s) + f" → {'통과' if st['verdict']['passed'] else '미달'}"

def measure(blabel, clabel, dlabel):
    """채점만 — 반환 비용은 신규 채점 호출 비용(생성 비용은 gen_cost 로 따로)."""
    ev = B.evaluate({"b": blabel, "c": clabel, "d": dlabel}, jobs=x.jobs + 2)
    return ev, ev["judge_cost"]

def gen_cost(label):
    """생성 결과 메타의 비용 합 — 일부 케이스만 끝나고 실패한 경우도 그만큼 센다."""
    d = os.path.join(OUT, label)
    if not os.path.isdir(d): return 0.0
    tot = 0.0
    for f in os.listdir(d):
        if f.endswith(".json") and not f.endswith(".score.json"):
            try: tot += json.load(open(os.path.join(d, f), encoding="utf-8")).get("cost", 0) or 0
            except Exception: pass
    return tot

def fix_prompt(rows, tr):
    lows = B.shortfalls(rows, ids=TRAIN)
    by = {(r["id"], r["system"]): r for r in rows}
    if not lows:                                                            # 전체 미달인데 케이스 미달이 없으면 토큰이 큰 train 케이스 상위 4개
        cand = sorted([r for r in rows if r["system"] == "b" and r["id"] in TRAIN and not r["skipped"]], key=lambda r: -r["out_tokens"])[:4]
        lows = [dict(id=r["id"], reasons=[f"토큰 {r['out_tokens']}"], row=r) for r in cand]
    cases = {c["id"]: c for c in B.S.cases}
    s = tr["summary"]
    parts = [
        "너는 프롬프트 개선기 Imprompt 의 규칙 파일을 고치는 엔지니어다. 아래 벤치 결과를 보고 규칙을 고쳐라.",
        "",
        "## 목표 (관리자 기준)",
        f"Imprompt 의 개선본이 두 일반 에이전트(일반 Claude·일반 Codex)보다 토큰은 적고(o200k 기준) 정확도(의도·사실·실행 가능성, 10점)는 같거나 높아야 한다.",
        f"train 평균 지금: Imprompt 정확도 {s['b']['acc']:.2f}·토큰 {s['b']['out_tokens']:.0f} / 일반 Claude {s['c']['acc']:.2f}·{s['c']['out_tokens']:.0f} / 일반 Codex {s['d']['acc']:.2f}·{s['d']['out_tokens']:.0f}. "
        + ("미달: " + "; ".join(tr["verdict"]["reasons"]) if not tr["verdict"]["passed"] else "평균은 통과, 아래 케이스 단위 미달만 줄인다."),
        "",
        "## 할 일",
        "- prompt-improver/instructions.md(2차 본문 규칙)와 prompt-improver/ask.md(1차 질문 규칙)만 고친다. 다른 파일·루브릭·케이스·채점기는 건드리지 않는다.",
        "- 한 번에 가설 하나만 세우고 그 가설에 필요한 최소 문구만 바꾼다. 규칙 파일은 지금보다 길어지지 않게 한다(중복은 합친다).",
        "- ask.md 출력 형식(READY 한 줄, 또는 '부족한 점: …' + '1) 질문 [1] … [2] …' 줄)은 pi-edit 이 파싱하므로 그대로 둔다.",
        "- 차별점(구조 고정·프로젝트 사실 기반·질문 최소화)은 유지한다. 지어낸 파일·스택을 쓰게 만드는 변경은 하지 않는다.",
        "- 다 고친 뒤 마지막 줄에 `가설: <한 문장>` 을 출력한다.",
        "",
        "## 루브릭 LLM 항목 (고정)",
        B.S.JUDGE.split("다음 3항목을")[1].split("출력은")[0].strip() if "다음 3항목을" in B.S.JUDGE else B.S.JUDGE,
        "",
        "## train 미달 케이스",
    ]
    for lw in lows:
        c = cases[lw["id"]]; r = lw["row"]
        rivals = " / ".join(f"{'일반 Claude' if o == 'c' else '일반 Codex'} 정확도 {by[(lw['id'], o)]['acc']:.2f}·토큰 {by[(lw['id'], o)]['out_tokens']}" for o in ("c", "d") if (lw["id"], o) in by)
        parts += [f"### {lw['id']} ({c['type']}) — " + "; ".join(lw["reasons"]), f"원문:\n{c['text'].strip()}"]
        if c.get("history"): parts.append("대화:\n" + "\n".join(f"{rr}: {t}" for rr, t in c["history"]))
        parts += [f"Imprompt 개선본(정확도 {r['acc']:.2f}, 항목 {r['items']}, 토큰 {r['out_tokens']}):\n{open(os.path.join(OUT, r['label'], lw['id'] + '.txt'), encoding='utf-8').read().strip()}",
                  f"채점 근거: {r['why'] or '(없음)'}", f"비교: {rivals}", ""]
    parts += ["## 지금 규칙", "### prompt-improver/instructions.md", open(os.path.join(ROOT, RULES[0]), encoding="utf-8").read(),
              "### prompt-improver/ask.md", open(os.path.join(ROOT, RULES[1]), encoding="utf-8").read()]
    return "\n".join(parts), [lw["id"] for lw in lows]

def run_fixer(prompt, d):
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDECODE", "CLAUDE_CODE_SESSION_ID")}
    p = subprocess.run(["claude", "-p", "--effort", "medium", "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
                        "--allowedTools", "Read", f"Edit({RULES[0]})", f"Edit({RULES[1]})", "--output-format", "json"],
                       input=prompt, cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8", timeout=900)
    try: j = json.loads(p.stdout); res, cost = j.get("result", ""), j.get("total_cost_usd") or 0
    except Exception: res, cost = (p.stdout + p.stderr)[-2000:], 0
    open(os.path.join(d, "fixer.txt"), "w", encoding="utf-8").write(res)
    hyp = next((l.split(":", 1)[1].strip() for l in reversed(res.splitlines()) if l.strip().startswith("가설")), res.strip().splitlines()[-1][:200] if res.strip() else "(응답 없음)")
    return hyp, cost

def not_worse(new, old):
    return new["acc"] >= old["acc"] - EPS_ACC and new["out_tokens"] <= old["out_tokens"] * (1 + EPS_TOK)

def improved(new, old):
    return new["acc"] >= old["acc"] + IMP_ACC or new["out_tokens"] <= old["out_tokens"] * (1 - IMP_TOK)

# ── 기준 측정(회차 0)
t_start = time.time(); spent = 0.0
log(f"\n# 자동 수정 루프 {x.tag} — 시작 {datetime.datetime.now():%Y-%m-%d %H:%M}")
log(f"- 세트: train {len(TRAIN)} / validation {len(VAL)} (splits.json seed {SP['seed']}) · 최대 {x.max_iter}회 · 예산 ${x.budget_usd} · 채택 기준 정확도 −{EPS_ACC}·토큰 +{EPS_TOK:.0%} 이내(둘 다)")
clabel = x.c_label or f"{x.tag}-c"; dlabel = x.d_label or f"{x.tag}-d"
b0 = x.b0_label or f"{x.tag}-i0-b"
for sysname, lab, given in (("c", clabel, x.c_label), ("d", dlabel, x.d_label), ("b", b0, x.b0_label)):
    if given: continue
    rc = BA.generate(sysname, lab, jobs=x.jobs)
    if sysname == "b": spent += gen_cost(lab)                                # 기준 b 생성 비용(c·d 기준 생성은 예산 밖)
    if rc != 0: log(f"\n## 중단 — 기준 생성 실패: {sysname} → {lab}"); sys.exit(2)
ev, cost = measure(b0, clabel, dlabel); spent += cost
tr, va = stats(subset(ev["rows"], TRAIN), ev), stats(subset(ev["rows"], VAL), ev)
if not ev["complete"]:
    log(f"\n## 중단 — 기준 측정 불완전: {'; '.join(ev['problems'])}"); sys.exit(2)
log(f"\n## 회차 0 (기준) — b={b0}, c={clabel}, d={dlabel}\n- train: {line('train', tr)}\n- validation: {line('validation', va)}\n- 비용 누계 ${spent:.2f}")
snapshot(BEST)
best = dict(rows=ev["rows"], tr=tr, va=va, label=b0)
open(JL, "a", encoding="utf-8").write(json.dumps(dict(iter=0, b=b0, train=tr, validation=va, spent=spent), ensure_ascii=False) + "\n")
no_imp = 0; stop = None
for it in range(1, x.max_iter + 1):
    lows_now = B.shortfalls(best["rows"], ids=TRAIN)
    if best["tr"]["verdict"]["passed"] and not lows_now: stop = "통과(train 평균·케이스 단위 미달 없음)"; break
    if spent >= x.budget_usd: stop = f"예산 초과(${spent:.2f} ≥ ${x.budget_usd})"; break
    d = os.path.join(LD, f"i{it}"); os.makedirs(d, exist_ok=True); t0 = time.time(); spent0 = spent
    prompt, targets = fix_prompt(best["rows"], best["tr"])
    open(os.path.join(d, "fix-prompt.md"), "w", encoding="utf-8").write(prompt)
    try: hyp, fcost = run_fixer(prompt, d)
    except Exception as e: restore(BEST); hyp, fcost = f"(수정 호출 오류 {type(e).__name__}: {str(e)[:120]})", 0.0
    spent += fcost
    diff = subprocess.run(["git", "diff", "--", *RULES], cwd=ROOT, capture_output=True, text=True).stdout
    open(os.path.join(d, "diff.patch"), "w", encoding="utf-8").write(diff)
    stat = subprocess.run(["git", "diff", "--stat", "--", *RULES], cwd=ROOT, capture_output=True, text=True).stdout.strip().splitlines()
    log(f"\n## 회차 {it}\n- 대상(train 미달): {', '.join(targets)}\n- 가설: {hyp}\n- 변경: {stat[-1] if stat else '없음'}  (diff: i{it}/diff.patch)")
    if not diff.strip():
        no_imp += 1; log(f"- 결과: 변경 없음 → 기각 · 연속 개선 0: {no_imp}")
        open(JL, "a", encoding="utf-8").write(json.dumps(dict(iter=it, hypothesis=hyp, adopted=False, reason="변경 없음", spent=spent), ensure_ascii=False) + "\n")
        if no_imp >= 3: stop = "3회 연속 개선 0"; break
        continue
    bl = f"{x.tag}-i{it}-b"
    if spent >= x.budget_usd:                                               # 수정 호출 뒤 예산 소진 → 검증 못 한 변경은 되돌리고 중단(유료 생성·채점 안 함)
        restore(BEST); log(f"- 판정: **기각 — 예산 소진(${spent:.2f} ≥ ${x.budget_usd}), 생성·채점 전 중단 → 규칙 되돌림**")
        open(JL, "a", encoding="utf-8").write(json.dumps(dict(iter=it, hypothesis=hyp, adopted=False, decision="예산 소진", spent=spent), ensure_ascii=False) + "\n")
        stop = f"예산 초과(${spent:.2f} ≥ ${x.budget_usd})"; break
    try:
        rc = BA.generate("b", bl, jobs=x.jobs)
        spent += gen_cost(bl)                                               # 실패해도 이미 쓴 생성 비용부터 합산
        if rc != 0: raise RuntimeError("b 생성 실패(run.py 종료 코드 ≠ 0)")    # 측정하지 않고 기각
        if spent >= x.budget_usd: raise RuntimeError(f"예산 소진(${spent:.2f} ≥ ${x.budget_usd}) — 채점 전 중단")
        ev, cost = measure(bl, clabel, dlabel); spent += cost
    except Exception as e:                                                  # 측정 중 어떤 오류든 규칙은 직전 채택본으로 되돌린다
        restore(BEST); no_imp += 1
        log(f"- 판정: **기각 — 측정 오류 {type(e).__name__}: {str(e)[:160]} → 규칙 되돌림** · 연속 개선 0: {no_imp}")
        open(JL, "a", encoding="utf-8").write(json.dumps(dict(iter=it, hypothesis=hyp, adopted=False, decision="측정 오류", error=str(e)[:300], spent=spent), ensure_ascii=False) + "\n")
        if no_imp >= 3: stop = "3회 연속 개선 0"; break
        if spent >= x.budget_usd: stop = f"예산 초과(${spent:.2f} ≥ ${x.budget_usd})"; break
        continue
    tr, va = stats(subset(ev["rows"], TRAIN), ev), stats(subset(ev["rows"], VAL), ev)
    have = all("b" in s["summary"] for s in (tr, va))
    if not ev["complete"] or not have:                                      # 결과 누락·생성/채점 실패 → 요약을 보기 전에 기각·복원
        restore(BEST); no_imp += 1
        probs = ev.get("problems") or ["b 결과 없음"]
        log(f"- 판정: **기각 — 측정 불완전({'; '.join(probs)}) → 규칙 되돌림** · 연속 개선 0: {no_imp} · 누계 ${spent:.2f}")
        open(JL, "a", encoding="utf-8").write(json.dumps(dict(iter=it, hypothesis=hyp, adopted=False, decision="측정 불완전", problems=probs, spent=spent), ensure_ascii=False) + "\n")
        if no_imp >= 3: stop = "3회 연속 개선 0"; break
        if spent >= x.budget_usd: stop = f"예산 초과(${spent:.2f} ≥ ${x.budget_usd})"; break
        continue
    nb, ob = tr["summary"]["b"], best["tr"]["summary"]["b"]; nvb, ovb = va["summary"]["b"], best["va"]["summary"]["b"]
    ok = not_worse(nb, ob) and not_worse(nvb, ovb); imp = ok and improved(nb, ob)
    if not ok:
        why = ("train 악화" if not not_worse(nb, ob) else "") + (" · " if not not_worse(nb, ob) and not not_worse(nvb, ovb) else "") + \
              ("validation 악화(과적합 의심)" if not_worse(nb, ob) and not not_worse(nvb, ovb) else ("validation 악화" if not not_worse(nvb, ovb) else ""))
        restore(BEST); decision = f"기각 — {why} → 규칙 되돌림"
    else:
        snapshot(BEST); best = dict(rows=ev["rows"], tr=tr, va=va, label=bl); decision = "채택" + (" (개선)" if imp else " (개선 폭 미달)")
        if not x.no_commit:
            subprocess.run(["git", "commit", "-q", "--only", "-m", f"feat(improver): 자동 수정 루프 {x.tag} 회차 {it} 채택 — {hyp[:80]}\n\ntrain 정확도 {ob['acc']:.2f}→{nb['acc']:.2f} 토큰 {ob['out_tokens']:.0f}→{nb['out_tokens']:.0f} / validation 정확도 {ovb['acc']:.2f}→{nvb['acc']:.2f} 토큰 {ovb['out_tokens']:.0f}→{nvb['out_tokens']:.0f}\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>", "--", *RULES], cwd=ROOT)   # 규칙 두 파일만(미리 스테이징된 다른 변경은 커밋하지 않음)
    no_imp = 0 if imp else no_imp + 1
    BA.report(f"{x.tag}-i{it}", [ev], ["b", "c", "d"], "all", extra_note=f"- 자동 수정 루프 회차 {it}: {decision}")
    shutil.copy(os.path.join(OUT, f"report-{x.tag}-i{it}.md"), os.path.join(d, "report.md"))
    log(f"- train: {line('train', tr)}\n- validation: {line('validation', va)}\n- 전후(b): train 정확도 {ob['acc']:.2f}→{nb['acc']:.2f}, 토큰 {ob['out_tokens']:.0f}→{nb['out_tokens']:.0f} / validation 정확도 {ovb['acc']:.2f}→{nvb['acc']:.2f}, 토큰 {ovb['out_tokens']:.0f}→{nvb['out_tokens']:.0f}"
        f"\n- 판정: **{decision}** · 연속 개선 0: {no_imp} · 회차 비용 ${spent - spent0:.2f} · 누계 ${spent:.2f} · {time.time() - t0:.0f}s")
    open(JL, "a", encoding="utf-8").write(json.dumps(dict(iter=it, hypothesis=hyp, targets=targets, adopted=ok, improved=imp, decision=decision, b=bl,
                                                         train=tr, validation=va, spent=spent, secs=round(time.time() - t0)), ensure_ascii=False) + "\n")
    if no_imp >= 3: stop = "3회 연속 개선 0"; break
else:
    stop = stop or f"최대 회차({x.max_iter}) 도달"
log(f"\n## 종료 — {stop}\n- 최종 채택 b: {best['label']}\n- train: {line('train', best['tr'])}\n- validation: {line('validation', best['va'])}\n- 비용 누계 ${spent:.2f} · 소요 {(time.time() - t_start) / 60:.0f}분")

#!/usr/bin/env python3
"""블라인드 비교 채점 + 지표: 케이스마다 여러 방식의 개선본을 익명 A·B·C 로 섞어(시드 고정·기록) 한 번에 보여주고
채점관 2종(Claude·Codex 구독 CLI) × 제시 순서 2가지로 rubric.md 의 LLM 항목(의도·사실·실행 가능성)을 매겨 평균한다.

지표(케이스 × 방식)
- 정확도 = (intent + facts + actionable) / 6 × 10 — facts 는 rubric 자동 상한(지어낸 경로) 적용
- 개선본 토큰 = tiktoken o200k_base 로 개선본 텍스트를 센 값(모든 방식 같은 잣대. Claude 실제 토큰 수와는 다르다)
- 변화율 = (개선본 토큰 − 원문 토큰) / 원문 토큰, 줄 변화율도 같이
- 참고: rubric 10점 품질(질문 수·길이·형식 자동 항목 포함), 호출 입력·출력 토큰

채점 조건: 루브릭 고정(rubric.md 의 심사 지시문 그대로 + 여러 개선본용 출력 형식 안내), 채점 모델 고정 ID
(claude-sonnet-5 · codex gpt-6.1-sol effort low). 두 CLI 모두 temperature 를 지정할 수 없어 "순서 2 × 채점관 2" 평균으로 대신한다.
캐시: out/compare/_blind-cache/<sha256(채점관·프롬프트)>.json — 같은 입력이면 다시 부르지 않는다.
"""
import concurrent.futures as cf, hashlib, json, os, random, re, statistics, subprocess, tempfile

import score as S                                                          # rubric 자동 판정·<프로젝트> 블록·저장소 파일 목록 재사용

HERE = S.HERE; OUT = S.OUT
CACHE = os.path.join(OUT, "_blind-cache"); os.makedirs(CACHE, exist_ok=True)
SEED = 20261009
JUDGES = {
    "claude": dict(model="claude-sonnet-5"),
    "codex": dict(model="gpt-6.1-sol", effort="low"),
}
LETTERS = "ABCDEFG"
_enc = None

def tok(text):
    global _enc
    if _enc is None:
        import tiktoken
        _enc = tiktoken.get_encoding("o200k_base")
    return len(_enc.encode(text or ""))

def lines(text): return len([l for l in (text or "").splitlines() if l.strip()])

def sys_prompt(n):
    keys = ", ".join(f'"{LETTERS[i]}":{{"intent":n,"facts":n,"actionable":n,"why":"…"}}' for i in range(n))
    return (S.JUDGE + "\n\n[여러 개선본 채점 형식] 이번에는 같은 <원문>에 대한 개선본 " + ", ".join(LETTERS[:n]) +
            " 를 함께 준다. 서로 비교하지 말고 위 기준을 각 개선본에 따로 적용해 채점하라. 순서·글자는 무작위다.\n"
            "출력은 JSON 하나만: {" + keys + "}")

def case_input(c, outs):
    """outs: [(글자, 개선본, 수락된 답 목록)]"""
    parts = [f"<원문>\n{c['text'].strip()}\n</원문>", S.PROJECT, "<저장소 파일>\n" + "\n".join(S.FILES) + "\n</저장소 파일>"]
    if c.get("history"): parts.append("<대화>\n" + "\n".join(("사용자: " if r == "user" else "에이전트: ") + t for r, t in c["history"]) + "\n</대화>")
    for L, text, ans in outs:
        if ans: parts.append(f"<{L}의 수락된 권장 답>\n" + "\n".join("- " + a for a in ans) + f"\n</{L}의 수락된 권장 답>")
        parts.append(f"<개선본 {L}>\n{text.strip()}\n</개선본 {L}>")
    return "\n\n".join(parts)

def parse_json(res, n):
    j = json.loads(res[res.index("{"): res.rindex("}") + 1])
    return {L: {k: max(0, min(2, int(round(float(j[L][k]))))) for k in ("intent", "facts", "actionable")} | {"why": str(j[L].get("why", ""))}
            for L in LETTERS[:n]}

def call_judge(name, system, prompt, n):
    key = hashlib.sha256(json.dumps([name, JUDGES[name], system, prompt], ensure_ascii=False).encode()).hexdigest()
    cp = os.path.join(CACHE, key + ".json")
    if os.path.exists(cp): return dict(json.load(open(cp, encoding="utf-8")), cached=True)   # 캐시 적중: 신규 지출 아님
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDECODE", "CLAUDE_CODE_SESSION_ID")}
    total = 0.0                                                             # 실패한 시도까지 포함한 누적 비용
    for _ in range(3):
        cost = 0.0
        try:
            if name == "claude":
                p = subprocess.run(["claude", "-p", "--model", JUDGES[name]["model"], "--effort", "low", "--system-prompt", system, "--tools", "",
                                    "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands", "--output-format", "json"],
                                   input=prompt, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=400)
                j = json.loads(p.stdout); res = j.get("result", ""); cost = j.get("total_cost_usd") or 0
            else:
                with tempfile.TemporaryDirectory() as empty:                   # 빈 폴더: 채점관이 저장소를 뒤지지 않게
                    p = subprocess.run(["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-C", empty, "--ephemeral", "--json",
                                        "-m", JUDGES[name]["model"], "-c", f'model_reasoning_effort="{JUDGES[name]["effort"]}"', "-c", "project_doc_max_bytes=0", "-"],
                                       input=system + "\n\n" + prompt, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=600)
                res = ""; done = False; bad = p.returncode != 0
                for line in p.stdout.splitlines():
                    try: ev = json.loads(line)
                    except Exception: continue
                    if ev.get("type") in ("turn.failed", "error"): bad = True
                    if ev.get("type") == "turn.completed": done = True
                    if ev.get("type") == "item.completed" and (ev.get("item") or {}).get("type") == "agent_message": res = ev["item"].get("text", "")
                if bad or not done: continue                                   # 실패한 채점은 재시도(3회 모두 실패면 None → 측정 불완전)
            total += cost; cost = 0.0                                       # 비용은 응답을 받은 시점에 누적(파싱 실패해도 센다)
            r = dict(scores=parse_json(res, n), cost=total)
            json.dump(r, open(cp, "w", encoding="utf-8"), ensure_ascii=False); return r
        except Exception:
            total += cost                                                   # 응답 JSON 은 받았지만 채점 파싱이 실패한 경우
            continue
    return dict(scores=None, cost=total, failed=True)                       # 3회 모두 실패: 판정은 불완전, 비용은 지출로

def load(label, c):
    d = os.path.join(OUT, label); tp, mp = os.path.join(d, c["id"] + ".txt"), os.path.join(d, c["id"] + ".json")
    if not (os.path.exists(tp) and os.path.exists(mp)): return None
    return open(tp, encoding="utf-8").read(), json.load(open(mp, encoding="utf-8"))

def evaluate(labels, cases=None, jobs=6, seed=SEED):
    """labels: {방식 이름: 결과 라벨}. 반환: {"rows": [케이스×방식 행], "judge_cost": $, "orders": {케이스: [순서1, 순서2]}}"""
    cases = cases or S.cases
    names = list(labels)
    data, missing = {}, []
    for c in cases:
        got = {s: load(labels[s], c) for s in names}
        if all(got.values()): data[c["id"]] = (c, got)
        else: missing.append(f"{c['id']}:" + "/".join(s for s in names if not got[s]))   # 결과 파일 누락 — 판정에서 실패로 센다
    tasks, orders = [], {}
    for cid, (c, got) in data.items():
        perm = names[:]; random.Random(f"{seed}:{cid}").shuffle(perm)
        orders[cid] = [perm, perm[::-1]]
        for oi, order in enumerate(orders[cid]):
            outs = [(LETTERS[i], got[s][0], got[s][1].get("answers") or []) for i, s in enumerate(order)]
            prompt = case_input(c, outs); system = sys_prompt(len(order))
            for jn in JUDGES: tasks.append((cid, oi, jn, order, system, prompt))
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        res = list(ex.map(lambda t: (t, call_judge(t[2], t[4], t[5], len(t[3]))), tasks))
    marks = {}                                                              # (케이스, 방식) → [채점 1회분 …]
    cost = 0.0; fails = 0
    for (cid, oi, jn, order, _, _), r in res:
        if r and not r.get("cached"): cost += r.get("cost") or 0          # 신규 호출 비용만(캐시 재사용분 제외), 실패한 채점 비용 포함
        if not r or r.get("failed") or not r.get("scores"): fails += 1; continue
        for i, s in enumerate(order):
            sc = r["scores"].get(LETTERS[i])
            if sc: marks.setdefault((cid, s), []).append(dict(sc, judge=jn, order=oi))
    rows = []
    for cid, (c, got) in data.items():
        for s in names:
            text, meta = got[s]; ms = marks.get((cid, s), [])
            a = S.auto(c, text, meta)
            if meta.get("failed") or not text.strip() or not ms:
                it = dict(intent=0, facts=0, actionable=0)
            else:
                it = {k: statistics.mean(m[k] for m in ms) for k in ("intent", "facts", "actionable")}
                it["facts"] = min(it["facts"], a["fact_cap"])
            acc = (it["intent"] + it["facts"] + it["actionable"]) / 6 * 10
            ot, ol = tok(text), lines(text); it0, il = tok(c["text"]), lines(c["text"])
            by_judge = {jn: round(statistics.mean((m["intent"] + min(m["facts"], a["fact_cap"]) + m["actionable"]) / 6 * 10 for m in ms if m["judge"] == jn), 2)
                        for jn in JUDGES if any(m["judge"] == jn for m in ms)}
            rows.append(dict(id=cid, type=c["type"], system=s, label=labels[s], acc=round(acc, 2), items={k: round(v, 2) for k, v in it.items()},
                             acc_by_judge=by_judge, n_marks=len(ms), out_tokens=ot, orig_tokens=it0, change=round((ot - it0) / it0, 2) if it0 else 0,
                             lines=ol, orig_lines=il, line_change=round((ol - il) / il, 2) if il else 0,
                             quality10=round(it["intent"] + it["facts"] + a["questions"] + a["length"] + it["actionable"], 2),
                             call_in=meta.get("in_tok", 0), call_out=meta.get("out_tok", 0), cost=meta.get("cost", 0), skipped=bool(meta.get("skipped")),
                             failed=bool(meta.get("failed")), why=" | ".join(dict.fromkeys(m["why"] for m in ms if m.get("why")))[:300]))
    expected = 2 * len(JUDGES)                                              # 순서 2 × 채점관 수
    short = [f"{r['id']}:{r['system']}({r['n_marks']}/{expected})" for r in rows if r["n_marks"] < expected]
    gen_failed = [f"{r['id']}:{r['system']}" for r in rows if r["failed"]]
    problems = ([f"결과 누락 {len(missing)}건: {', '.join(missing[:5])}"] if missing else []) + \
               ([f"생성 실패 {len(gen_failed)}건: {', '.join(gen_failed[:5])}"] if gen_failed else []) + \
               ([f"채점 실패 호출 {fails}건"] if fails else []) + ([f"채점 부족 {len(short)}건: {', '.join(short[:5])}"] if short else [])
    return dict(rows=rows, judge_cost=round(cost, 4), judge_fail=fails, orders=orders, seed=seed,
                complete=not problems, problems=problems, missing=missing)

def summarize(rows, names):
    out = {}
    for s in names:
        rs = [r for r in rows if r["system"] == s]
        if not rs: continue
        m = lambda k: statistics.mean(r[k] for r in rs)
        out[s] = dict(n=len(rs), acc=round(m("acc"), 2), out_tokens=round(m("out_tokens"), 1), change=round(m("change"), 2), line_change=round(m("line_change"), 2),
                      quality10=round(m("quality10"), 2), call_in=round(m("call_in")), call_out=round(m("call_out")), cost=round(sum(r["cost"] for r in rs), 3),
                      acc_by_judge={jn: round(statistics.mean(r["acc_by_judge"][jn] for r in rs if jn in r["acc_by_judge"]), 2)
                                    for jn in JUDGES if any(jn in r["acc_by_judge"] for r in rs)})
    return out

def verdict(summary, me="b", others=("c", "d"), evs=()):
    """통과 = 개선본 토큰이 두 일반 에이전트보다 적고, 정확도는 같거나 높다 (관리자 기준).
    evs(evaluate 결과들) 중 하나라도 불완전(결과 누락·생성 실패·채점 실패/부족)이면 미달."""
    if me not in summary: return dict(passed=False, reasons=["결과 없음"])
    reasons = [f"측정 불완전 — {p}" for ev in evs for p in ev.get("problems", [])]
    if any(o not in summary for o in others): reasons.append("비교 대상 결과 없음: " + ",".join(o for o in others if o not in summary))
    for o in others:
        if o not in summary: continue
        if not summary[me]["out_tokens"] < summary[o]["out_tokens"]: reasons.append(f"토큰 {summary[me]['out_tokens']} ≥ {o} {summary[o]['out_tokens']}")
        if not summary[me]["acc"] >= summary[o]["acc"]: reasons.append(f"정확도 {summary[me]['acc']} < {o} {summary[o]['acc']}")
    return dict(passed=not reasons, reasons=reasons)

def shortfalls(rows, me="b", others=("c", "d"), ids=None, acc_tol=0.25):
    """케이스 단위 미달: 정확도가 일반 에이전트 최고보다 acc_tol 넘게 낮거나, 개선본 토큰이 일반 에이전트 최소 이상."""
    by = {(r["id"], r["system"]): r for r in rows}; out = []
    for (cid, s), r in by.items():
        if s != me or (ids and cid not in ids): continue
        rivals = [by[(cid, o)] for o in others if (cid, o) in by]
        if not rivals: continue
        best = max(x["acc"] for x in rivals); least = min(x["out_tokens"] for x in rivals)
        why = []
        if r["acc"] < best - acc_tol: why.append(f"정확도 {r['acc']} < 일반 최고 {best}")
        if r["out_tokens"] >= least and not r["skipped"]: why.append(f"토큰 {r['out_tokens']} ≥ 일반 최소 {least}")
        if why: out.append(dict(id=cid, reasons=why, row=r))
    return sorted(out, key=lambda x: x["id"])

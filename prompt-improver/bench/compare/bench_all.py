#!/usr/bin/env python3
"""명령 하나로 비교 벤치: 생성(b 스킬 · c 일반 Claude · d 일반 Codex) → 블라인드 채점 → 케이스별·평균 비교표 → 판정.

사용: bench_all.py [--repeat 2] [--tag 이름] [--split all|train|validation] [--systems b,c,d] [--reuse] [--jobs 4]
  --repeat N : 같은 입력으로 생성·채점 전체를 N회 → 회차별 정확도와 차이·케이스별 표준편차를 표에 넣는다.
  --reuse    : 같은 라벨 결과가 이미 있으면 생성을 건너뛴다(채점은 입력 해시 캐시).
결과: bench/out/compare/report-<tag>.md · report-<tag>.json  (라벨: <tag>-r<회차>-<방식>)
판정(관리자 기준): b 의 개선본 토큰 평균이 c·d 보다 적고 정확도 평균이 c·d 이상이면 통과.
"""
import argparse, datetime, json, os, statistics, subprocess, sys, time

import blind as B

HERE = B.HERE; OUT = B.OUT
SYS_NAME = {"a": "개선 전 스킬", "b": "Imprompt", "c": "일반 Claude", "d": "일반 Codex"}

def split_ids(split):
    if split == "all": return None
    sp = json.load(open(os.path.join(HERE, "splits.json"), encoding="utf-8"))
    return sp[split]

def generate(system, label, ids=None, jobs=4, reuse=False, extra=()):
    d = os.path.join(OUT, label)
    want = ids or [c["id"] for c in B.S.cases]
    if reuse and all(os.path.exists(os.path.join(d, i + ".json")) for i in want): return 0
    for i in want:                                                          # 이전 결과가 남아 실패한 생성이 옛 결과로 측정되지 않게 비운다
        for ext in (".txt", ".json"):
            fp = os.path.join(d, i + ext)
            if os.path.exists(fp): os.remove(fp)
    cmd = [sys.executable, os.path.join(HERE, "run.py"), system, "--label", label, "--jobs", str(jobs)] + list(extra)
    if ids: cmd += ["--only", ",".join(ids)]
    t0 = time.time(); p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    print(f"  생성 {system} → {label}: {p.stdout.strip().splitlines()[-1] if p.stdout.strip() else p.stderr[-200:]} ({time.time() - t0:.0f}s)"
          + ("" if p.returncode == 0 else f" ⚠ 종료 코드 {p.returncode} — 실패 케이스는 판정에서 미달로 센다"), flush=True)
    return p.returncode

def fmt_pct(x): return f"{x * 100:+,.0f}%"

def report(tag, runs, names, split, extra_note=""):
    """runs: [evaluate() 결과, …] (회차별). 케이스별 표는 회차 평균."""
    cases = [c for c in B.S.cases if any(r["id"] == c["id"] for r in runs[0]["rows"])]
    per = {}                                                                # (id, system) → [회차별 행]
    for run in runs:
        for r in run["rows"]: per.setdefault((r["id"], r["system"]), []).append(r)
    sums = [B.summarize(run["rows"], names) for run in runs]
    avg = {s: {k: round(statistics.mean(sm[s][k] for sm in sums), 2) for k in ("acc", "out_tokens", "change", "line_change", "quality10", "call_in", "call_out")}
           for s in names if all(s in sm for sm in sums)}
    for s in avg:
        avg[s]["acc_by_judge"] = {jn: round(statistics.mean(sm[s]["acc_by_judge"].get(jn, 0) for sm in sums), 2) for jn in B.JUDGES}
        avg[s]["cost"] = round(sum(sm[s]["cost"] for sm in sums), 3)
    v = B.verdict(avg, evs=runs)
    judges_txt = ", ".join(k + "(" + str(j.get("model")) + ")" for k, j in B.JUDGES.items())
    md = [f"# 비교 벤치 — {tag}", "",
          f"- 생성: {', '.join(f'{s}={SYS_NAME.get(s, s)}' for s in names)} · 세트 `{split}` {len(cases)}건 · 회차 {len(runs)}",
          f"- 채점: 블라인드(케이스마다 익명 A·B·C, 시드 {B.SEED} 로 순서 섞음 + 역순) × 채점관 {judges_txt} → 평균. 기준 `rubric.md` LLM 항목(의도·사실·실행 가능성)을 10점으로 환산한 것이 정확도. temperature 는 두 CLI 모두 지정 불가.",
          "- 토큰: 개선본 텍스트를 tiktoken o200k_base 로 센 값(모든 방식 같은 잣대, Claude 실제 토큰 수와 다름). 변화율 = (개선본 − 원문) / 원문.",
          f"- 판정(관리자 기준: Imprompt 가 두 일반 에이전트보다 토큰 적고 정확도 같거나 높음): **{'통과' if v['passed'] else '미달'}**" + ("" if v["passed"] else " — " + "; ".join(v["reasons"])),
          extra_note, "",
          "## 평균", "", "| 방식 | 정확도 | 개선본 토큰 | 변화율(토큰) | 변화율(줄) | 품질10 | 정확도(Claude 채점) | 정확도(Codex 채점) | 호출 입력 | 호출 출력 |",
          "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for s in names:
        if s not in avg: continue
        a = avg[s]
        md.append(f"| {SYS_NAME.get(s, s)} ({s}) | {a['acc']:.2f} | {a['out_tokens']:,.0f} | {fmt_pct(a['change'])} | {fmt_pct(a['line_change'])} | {a['quality10']:.2f} | "
                  f"{a['acc_by_judge'].get('claude', 0):.2f} | {a['acc_by_judge'].get('codex', 0):.2f} | {a['call_in']:,.0f} | {a['call_out']:,.0f} |")
    if len(runs) > 1:
        md += ["", "## 회차 간 편차 (같은 입력 재실행)", "", "| 방식 | " + " | ".join(f"{i + 1}회차 정확도" for i in range(len(runs))) + " | 평균 차이 | 케이스별 표준편차 평균 | 토큰 1·2회차 |",
               "|---|" + "---:|" * (len(runs) + 3)]
        for s in names:
            if s not in avg: continue
            accs = [sm[s]["acc"] for sm in sums]
            sds = [statistics.pstdev([r["acc"] for r in per[(c["id"], s)]]) for c in cases if len(per.get((c["id"], s), [])) > 1]
            md.append(f"| {SYS_NAME.get(s, s)} ({s}) | " + " | ".join(f"{x:.2f}" for x in accs) + f" | {max(accs) - min(accs):.2f} | {statistics.mean(sds) if sds else 0:.2f} | "
                      + " / ".join(f"{sm[s]['out_tokens']:,.0f}" for sm in sums) + " |")
    md += ["", "## 케이스별 (회차 평균: 정확도 / 개선본 토큰 / 변화율)", "",
           "| 케이스 | 유형 | 원문 토큰 | " + " | ".join(f"{SYS_NAME.get(s, s)} 정확도 | 토큰 | 변화율" for s in names) + " |",
           "|---|---|---:|" + "---:|" * (3 * len(names))]
    for c in cases:
        cells = []
        for s in names:
            rs = per.get((c["id"], s), [])
            if not rs: cells += ["-", "-", "-"]; continue
            cells += [f"{statistics.mean(r['acc'] for r in rs):.2f}", f"{statistics.mean(r['out_tokens'] for r in rs):,.0f}", fmt_pct(statistics.mean(r["change"] for r in rs))]
        md.append(f"| {c['id']} | {c['type']} | {B.tok(c['text'])} | " + " | ".join(cells) + " |")
    md.append(f"| **평균** | | | " + " | ".join(f"**{avg[s]['acc']:.2f}** | **{avg[s]['out_tokens']:,.0f}** | **{fmt_pct(avg[s]['change'])}**" for s in names if s in avg) + " |")
    lows = B.shortfalls([r for run in runs for r in run["rows"]] if len(runs) == 1 else runs[-1]["rows"])
    if lows:
        md += ["", "## Imprompt 케이스 단위 미달 (마지막 회차)", ""] + [f"- {x['id']}: " + "; ".join(x["reasons"]) + (f" — 채점 근거: {x['row']['why'][:160]}" if x['row']['why'] else "") for x in lows]
    md += ["", f"채점 비용(Claude 채점관 CLI 보고값) ${sum(r['judge_cost'] for r in runs):.3f} · 채점 실패 {sum(r['judge_fail'] for r in runs)}건 · Codex 사용량은 $ 미보고(구독)"]
    data = dict(tag=tag, split=split, names=names, summary=avg, per_run=sums, verdict=v, runs=runs, shortfalls=[dict(id=x["id"], reasons=x["reasons"]) for x in lows])
    open(os.path.join(OUT, f"report-{tag}.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")
    json.dump(data, open(os.path.join(OUT, f"report-{tag}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return data, "\n".join(md)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repeat", type=int, default=1); ap.add_argument("--tag", default=datetime.date.today().isoformat())
    ap.add_argument("--split", default="all", choices=("all", "train", "validation")); ap.add_argument("--systems", default="b,c,d")
    ap.add_argument("--reuse", action="store_true"); ap.add_argument("--jobs", type=int, default=4)
    x = ap.parse_args()
    names = x.systems.split(","); ids = split_ids(x.split)
    cases = [c for c in B.S.cases if not ids or c["id"] in ids]
    runs = []
    for r in range(1, x.repeat + 1):
        print(f"[{x.tag}] {r}회차 생성", flush=True)
        labels = {s: f"{x.tag}-r{r}-{s}" for s in names}
        for s in names: generate(s, labels[s], ids, x.jobs, x.reuse)
        print(f"[{x.tag}] {r}회차 채점", flush=True)
        runs.append(B.evaluate(labels, cases, jobs=x.jobs + 2))
    data, md = report(x.tag, runs, names, x.split)
    print(md)
    sys.exit(0 if data["verdict"]["passed"] else 3)

if __name__ == "__main__":
    main()

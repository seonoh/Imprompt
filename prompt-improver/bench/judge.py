#!/usr/bin/env python3
"""개선본 품질 심사(LLM-as-judge): 두 라벨의 out/<라벨>/<샘플>.txt 를 원본과 함께 보여주고 항목별 1~5점 + 선호를 JSON 으로 받는다.

사용: judge.py <라벨A> <라벨B> [--judge-model sonnet] [--samples DIR]
  항목: intent(의도·범위 보존) facts(사실 비왜곡: 추측·지어낸 파일명/스택 없음) actionable(착수 가능성) concise(불필요한 반복·장황 없음)
  심사 모델은 개선에 쓴 모델과 다른 것을 권장. 결과 out/judge-<A>-vs-<B>.json
"""
import argparse, glob, json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser(); ap.add_argument("a"); ap.add_argument("b")
ap.add_argument("--judge-model", default="sonnet"); ap.add_argument("--samples", default=os.path.join(HERE, "samples"))
ap.add_argument("--ctx", help="개선 때 함께 보낸 <프로젝트> 블록 파일(사실 판정 기준에 포함)"); ap.add_argument("--swap", action="store_true", help="A/B 자리를 바꿔 한 번 더 심사(위치 편향 상쇄)")
x = ap.parse_args()
RUBRIC = """너는 프롬프트 개선 결과를 채점하는 심사관이다. <원본>은 사용자의 요청, <A>와 <B>는 서로 다른 개선기가 쓴 개선본이다.
<프로젝트>와 <사용자 답변>이 있으면 그 내용은 사실로 인정한다(답변에 따른 구체화는 의도 이탈이 아니다). 각 개선본을 다음 4항목 1~5점으로 채점하고, 전체적으로 어느 쪽이 코딩 에이전트에 보내기에 더 좋은지 고르라.
- intent: 원본의 의도·범위·명시된 제약(금지사항·수치·이름)을 그대로 보존했는가 (덧붙인 별개 기능이 있으면 감점)
- facts: 원본·<프로젝트>에 없는 파일명·스택·구조·수치를 사실처럼 지어내지 않았는가 (모르는 것을 "확인할 것/질문할 것"으로 처리하면 만점)
- actionable: 에이전트가 되묻지 않고 바로 착수할 수 있을 만큼 구체적인가 (표준 흐름·검증 기준 포함)
- concise: 같은 내용의 반복·장황함이 없는가
출력은 JSON 하나만: {"A":{"intent":n,"facts":n,"actionable":n,"concise":n},"B":{...},"prefer":"A"|"B"|"tie","reason":"한 문장"}"""
env = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_CODE_CHILD_SESSION", "CLAUDECODE")}
rows = []
for sf in sorted(glob.glob(os.path.join(x.samples, "*.txt"))):
    name = os.path.basename(sf)
    pa, pb = os.path.join(HERE, "out", x.a, name), os.path.join(HERE, "out", x.b, name)
    if not (os.path.exists(pa) and os.path.exists(pb)): continue
    orig = open(sf, encoding="utf-8").read(); A = open(pa, encoding="utf-8").read(); B = open(pb, encoding="utf-8").read()
    ctxblk = ("\n" + open(x.ctx, encoding="utf-8").read().strip() + "\n") if x.ctx else ""
    for side, lab in (("A", x.a), ("B", x.b)):   # 질문 모드 답변(사용자 확정 사실)이 있으면 심사 기준에 포함
        af = os.path.join(HERE, "out", lab, name + ".answers.txt")
        if os.path.exists(af): ctxblk += f"\n<{side}의 사용자 답변 — 사용자가 확정한 사실로 인정>\n" + open(af, encoding="utf-8").read().strip() + f"\n</{side}의 사용자 답변>\n"
    def ask(A, B):
        prompt = f"<원본>\n{orig}\n</원본>\n{ctxblk}\n<A>\n{A}\n</A>\n\n<B>\n{B}\n</B>"
        p = subprocess.run(["claude", "-p", "--model", x.judge_model, "--effort", "low", "--system-prompt", RUBRIC, "--tools", "",
                        "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands", "--output-format", "json"],
                       input=prompt, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=300)
        res = json.loads(p.stdout).get("result", "")
        return json.loads(res[res.index("{"): res.rindex("}") + 1])
    try:
        j = ask(A, B)
        if x.swap:  # 자리 바꿔 재심사 → 점수 평균, 선호는 두 번 일치할 때만 인정
            k = ask(B, A); kk = {"A": k["B"], "B": k["A"], "prefer": {"A": "B", "B": "A"}.get(k["prefer"], "tie")}
            for side in ("A", "B"):
                for m in ("intent", "facts", "actionable", "concise"): j[side][m] = (j[side][m] + kk[side][m]) / 2
            j["prefer"] = j["prefer"] if j["prefer"] == kk["prefer"] else "tie"
            j["reason"] += " | 스왑: " + k.get("reason", "")
    except Exception as e:
        print("PARSE FAIL", name, str(e)[:100], file=sys.stderr); continue
    j["sample"] = name; rows.append(j); print(json.dumps(j, ensure_ascii=False), flush=True)
out = os.path.join(HERE, "out", f"judge-{x.a}-vs-{x.b}.json"); json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
if rows:
    for side in ("A", "B"):
        avg = {k: round(sum(r[side][k] for r in rows) / len(rows), 2) for k in ("intent", "facts", "actionable", "concise")}
        print(side, "=", (x.a if side == "A" else x.b), avg)
    print("prefer:", {s: sum(1 for r in rows if r["prefer"] == s) for s in ("A", "B", "tie")})

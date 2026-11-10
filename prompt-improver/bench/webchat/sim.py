"""웹 채팅 흉내: 에이전트가 링크로 읽었을 문서(README·llms-install·ask·instructions)를 '열어 본 페이지'로 주고,
3턴(링크+사용해줘 → 요청 → '권장')을 대화 기록째 다시 보내 각 엔진(도구·셸 없음)의 답을 기록한다."""
import json, os, subprocess, sys, tempfile
REPO = sys.argv[1]; eng = sys.argv[2]; out = sys.argv[3]
def rd(p): return open(os.path.join(REPO, p), encoding="utf-8").read()
pages = "\n\n".join("[열어 본 페이지: https://github.com/seonoh/Imprompt/blob/main/%s]\n%s" % (p, rd(p)) for p in
                    ("README.md", "llms-install.md", "prompt-improver/ask.md", "prompt-improver/instructions.md"))
turns = ["https://github.com/seonoh/Imprompt 사용해줘", "할일 내보내기 기능 만들어줘", "권장"]
hist, log = [], []
empty = tempfile.mkdtemp()
for u in turns:
    hist.append("사용자: " + u)
    prompt = ("너는 웹 채팅 AI 다. 명령 실행·파일 쓰기 도구는 없고, 사용자가 준 링크의 페이지는 읽을 수 있다(아래에 이미 열어 둔 내용).\n\n"
              + pages + "\n\n[대화]\n" + "\n\n".join(hist) + "\n\n위 대화의 마지막 사용자 메시지에 대한 너의 답만 출력하라.")
    if eng == "claude":
        cmd = ["claude", "-p", "--tools", "", "--strict-mcp-config", "--setting-sources", ""]
    elif eng == "codex":
        cmd = ["codex", "exec", "--skip-git-repo-check", "--disable", "shell_tool", "--disable", "unified_exec", "-c", 'web_search="disabled"', "-"]
    else:
        cmd = ["gemini", "-p", "아래 입력을 따르라.", "--approval-mode", "plan", "--skip-trust"]
    env = dict(os.environ, IMPROMPT_CHILD="1")
    p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=empty, timeout=300, env=env)
    ans = p.stdout.strip() or ("[stderr] " + p.stderr.strip()[-400:])
    hist.append("AI: " + ans)
    log.append({"user": u, "ai": ans, "rc": p.returncode})
json.dump(log, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
for x in log: print("== 사용자:", x["user"], "(rc %s)\n%s\n" % (x["rc"], x["ai"][:1500]))

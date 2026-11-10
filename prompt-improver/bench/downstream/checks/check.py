import json, os, subprocess, sys, tempfile
task, d = sys.argv[1], sys.argv[2]
sys.path.insert(0, d); os.chdir(d)
res = {"tests": subprocess.run([sys.executable, "-m", "unittest", "-q"], capture_output=True, text=True).returncode == 0}
try:
    from todo import TodoStore
    p = os.path.join(tempfile.mkdtemp(), "t.json"); s = TodoStore(p)
    if task == "T1":
        s.add("우유 사기"); 
        try: s.add("우유 사기")
        except Exception: pass
        try: s.add("  우유 사기 ")
        except Exception: pass
        n = len(TodoStore(p).list()); res["exact_dup_blocked"] = n <= 2; res["ws_dup_blocked"] = n == 1
    elif task == "T2":
        it = s.add("우유 사기"); done = None
        for name in ("done", "complete", "mark_done", "toggle", "finish"):
            if hasattr(s, name):
                getattr(s, name)(it["id"]); done = TodoStore(p).list()[0]["done"]; res["method"] = name; break
        res["done_works"] = done is True; res["cli_done"] = "done" in open("todo/cli.py", encoding="utf-8").read()
    elif task == "T3":
        s.add("우유 사기"); out = None
        for name in ("export", "export_json", "export_csv", "to_csv", "to_json", "dump"):
            if hasattr(s, name):
                try: out = getattr(s, name)(); res["method"] = name
                except TypeError:
                    o = os.path.join(tempfile.mkdtemp(), "x"); getattr(s, name)(o); out = open(o, encoding="utf-8").read() if os.path.exists(o) else None; res["method"] = name + "(path)"
                break
        res["export_works"] = bool(out) and "우유 사기" in str(out); res["cli_export"] = "export" in open("todo/cli.py", encoding="utf-8").read()
except Exception as e:
    res["error"] = str(e)[:120]
print(json.dumps(res, ensure_ascii=False))

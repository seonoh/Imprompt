; Imprompt global hotkey (Windows, AutoHotkey v2): select text in any app, press Ctrl+Q -> replaced with the improved prompt.
; Engine = MCP server standalone mode (imprompt_mcp.py --improve): same rules, cache and fallback, no API key.
; Terminals get Ctrl+Q unchanged so the in-CLI improver (pi-edit) keeps working there.
; Install: powershell -ExecutionPolicy Bypass -File install.ps1 hotkey  (writes %APPDATA%\imprompt\hotkey.ini, adds a Startup shortcut)
; Safety: nothing selected -> no change; failure -> original text and clipboard kept; focus moved -> result only on clipboard;
;         clipboard restored afterwards; a second press while running is ignored.
#Requires AutoHotkey v2.0
#SingleInstance Force

Ini := A_AppData "\imprompt\hotkey.ini"
Python := IniRead(Ini, "imprompt", "python", "python")
Server := IniRead(Ini, "imprompt", "server", A_ScriptDir "\..\prompt-improver\mcp\imprompt_mcp.py")
Host := IniRead(Ini, "imprompt", "host", "claude")
if !RegExMatch(Host, "^(claude|codex|gemini)$")   ; allow-list: the value goes into a command line, so anything else falls back to claude
    Host := "claude"
; Terminals and IDEs with an integrated terminal (Ctrl+C there would interrupt a running command): pass Ctrl+Q through
Terminals := Map("WindowsTerminal.exe", 1, "cmd.exe", 1, "powershell.exe", 1, "pwsh.exe", 1, "mintty.exe", 1,
                 "conhost.exe", 1, "wezterm-gui.exe", 1, "alacritty.exe", 1, "Hyper.exe", 1,
                 "Code.exe", 1, "Code - Insiders.exe", 1, "Cursor.exe", 1, "Windsurf.exe", 1, "idea64.exe", 1,
                 "pycharm64.exe", 1, "webstorm64.exe", 1, "rider64.exe", 1, "goland64.exe", 1, "clion64.exe", 1,
                 "Tabby.exe", 1, "Termius.exe", 1, "Zed.exe", 1, "MobaXterm.exe", 1, "Wave.exe", 1, "ghostty.exe", 1,
                 "wt.exe", 1, "putty.exe", 1, "kitty.exe", 1, "ConEmu64.exe", 1, "ConEmu.exe", 1)
; Not in the list but the process name contains term/shell/console: treat as a terminal too (Ctrl+C there may interrupt a running command)
IsTerminalExe(exe) => Terminals.Has(exe) || InStr(exe, "term") || InStr(exe, "shell") || InStr(exe, "console")
Busy := false
; User-facing messages (identical across platforms: imprompt.lua, imprompt-linux.sh). ASCII only for console/ahk encodings.
MSG := Map(
    "progress",    "Refining prompt... (10-30s, keep this window focused)",
    "done",        "Prompt refined.",
    "failed",      "Refinement failed: {1}. Original text kept.",
    "cancelled",   "Paste cancelled: window changed. Refined prompt is on the clipboard (Ctrl+V).",
    "busy",        "Refinement already in progress.",
    "noSelection", "Select the text to refine first.",
    "unknown",     "unknown error",
    "badPath",     "unsafe character in a path setting",
    "keyMenu",     "Hotkey: {1}",
    "keyChange",   "Change Hotkey...",
    "keyReset",    "Reset to {1}",
    "keySet",      "Hotkey set to {1}.",
    "keyKept",     "Hotkey unchanged ({1}): {2}",
    "ready",       "Imprompt is ready. Select text in any app and press {1}. Menu: the pencil icon in the taskbar (under ^) - right-click.",
    "keyNeedMod",  "add Ctrl, Alt or Win",
    "keyReserved", "{1} is a common app shortcut",
    "keyTaken",    "{1} could not be registered (used by Windows or another app)",
    "keySaveFail", "could not save the setting",
    "keyTitle",    "Imprompt hotkey",
    "keyHint",     "Click the box, press the new shortcut, then Save.",
    "keySave",     "Save",
    "keyCancel",   "Cancel",
    "jobs",        "Open Job History",
    "jobsFail",    "Could not build the job history report",
    "rulesOn",     "Custom rules: on ({1} chars)",
    "rulesOff",    "Custom rules: off",
    "rulesEdit",   "Edit Custom Rules...",
    "rulesImport", "Import From My Agent Rules...",
    "rulesFail",   "Could not open the custom rules file",
    "importWait",  "Reading your agent rules... (up to a minute)",
    "importBusy",  "Import already in progress.",
    "applyTitle",  "Imprompt custom rules",
    "applyBody",   "Review the draft that just opened in Notepad. Apply it to your custom rules? Existing rules are kept.",
    "applied",     "Custom rules updated.",
    "signMenu",    "Sign in...",
    "signTitle",   "Imprompt sign-in",
    "signAsk",     "Sign in required for {1}. Open sign-in now?",
    "signFail",    "Could not open the sign-in window",
    "edTitle",     "Imprompt - Custom Rules",
    "edList",      "Your rules",
    "edNew",       "+ New rule",
    "edName",      "Name - a short title, e.g. Tone or Tests",
    "edBody",      "Rule - what the AI should keep in mind when it rewrites your prompt",
    "edAdd",       "Add",
    "edSave",      "Save",
    "edDelete",    "Delete",
    "edClose",     "Close",
    "edCount",     "Using {1} of {2} characters",
    "edPick",      "Pick a rule on the left, or click + New rule.",
    "edNewHint",   "Type a name and the rule, then press Add.",
    "edEditHint",  "Edit the rule, then press Save.",
    "edNoName",    "Please enter a name.",
    "edNoBody",    "Please write what the rule should say.",
    "edDup",       "A rule named `"{1}`" already exists. Please choose a different name.",
    "edDelAsk",    "Delete the rule `"{1}`"?`n`nThis removes it from your custom rules. You cannot undo this here.",
    "edDiscard",   "You have unsaved changes. Leave them?",
    "edFail",      "Something went wrong. Please try again.",
    "remove",      "Uninstall Imprompt...",
    "removeAsk",   "Remove Imprompt from this PC?`n`nThis turns off the hotkey and deletes Imprompt, its settings, your custom rules and history.`nGit, Python, AutoHotkey and your AI app stay (remove them in Settings > Apps if you want).",
    "removeFail",  "Could not start the uninstaller",
    "exit",        "Exit")

; One-phrase failure reason: first stderr line "Refinement failed: <reason>. ..." -> <reason>; otherwise the first line as is
Reason(err) {
    if Trim(err) = ""                     ; no stderr at all: do not index an empty split
        return MSG["unknown"]
    line := ""
    for part in StrSplit(err, "`n", "`r")  ; first non-empty line
        if (line := Trim(part)) != ""
            break
    line := RegExReplace(line, "^Refinement failed:\s*")
    line := RegExReplace(line, "\.?\s*Original text kept\.?$")
    line := RegExReplace(line, "\.$")
    return line != "" ? line : MSG["unknown"]
}

; Progress animation (ASCII, same story as the mac panel and pi-anim.pl): the pencil writes a draft "~~~", comes back
; polishing it into "---", then sparkles "*". Redrawn every 120 ms while RunWait blocks (timers keep running).
BuildFrames() {
    W := 10, E := 12, frames := []
    loop 2 * E + 4 {
        f := A_Index - 1, c := []
        loop W
            c.Push(" ")
        if f < E {                                   ; write: left -> right, draft behind the pencil
            p := Round((W - 1) * (1 - Cos(3.14159265 * f / (E - 1))) / 2)
            loop p
                c[A_Index] := "~"
            c[p + 1] := ">"
        } else if f < 2 * E {                        ; polish: right -> left, neat line behind the pencil
            p := (W - 1) - Round((W - 1) * (1 - Cos(3.14159265 * (f - E) / (E - 1))) / 2)
            loop p
                c[A_Index] := "~"
            loop W - 1 - p
                c[p + 1 + A_Index] := "-"
            c[p + 1] := "<"
            if f <= E + 1
                c[W] := "*"
        } else {                                     ; done: neat line, sparkle at the pencil
            loop W - 1
                c[A_Index + 1] := "-"
            c[1] := Mod(f - 2 * E, 2) ? "<" : "*"
        }
        s := ""
        for ch in c
            s .= ch
        frames.Push("[" s "]")
    }
    return frames
}
Frames := BuildFrames()
AnimI := 0, AnimT0 := 0
AnimTick() {
    global AnimI
    AnimI += 1
    ToolTip "Imprompt: " Frames[Mod(AnimI, Frames.Length) + 1] " " MSG["progress"] "  " (A_TickCount - AnimT0) // 1000 "s"
}
StartAnim() {
    global AnimI := 0, AnimT0 := A_TickCount
    AnimTick()
    SetTimer AnimTick, 120
}
StopAnim() {
    SetTimer AnimTick, 0
    ToolTip
}

; Windows clipboard history / cloud sync / clipboard monitors honour these registered formats (documented by Microsoft):
; ExcludeClipboardContentFromMonitorProcessing = skip monitoring, CanIncludeInClipboardHistory=0, CanUploadToCloudClipboard=0.
; Called right after the text was put on the clipboard: formats are ADDED (the clipboard is never cleared here), so the text stays. Best effort.
MarkClipboardPrivate() {
    try {
        if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
            return
        for name, val in Map("ExcludeClipboardContentFromMonitorProcessing", 1, "CanIncludeInClipboardHistory", 0, "CanUploadToCloudClipboard", 0) {
            fmt := DllCall("RegisterClipboardFormat", "Str", name, "UInt")
            h := DllCall("GlobalAlloc", "UInt", 2, "UPtr", 4, "Ptr")      ; GMEM_MOVEABLE, one DWORD
            if !fmt || !h
                continue
            NumPut("UInt", val, DllCall("GlobalLock", "Ptr", h, "Ptr"))
            DllCall("GlobalUnlock", "Ptr", h)
            if !DllCall("SetClipboardData", "UInt", fmt, "Ptr", h, "Ptr")  ; on success the system owns the memory
                DllCall("GlobalFree", "Ptr", h)
        }
        DllCall("CloseClipboard")
    }
}

; cmd.exe is kept only because stderr must be captured (RunWait cannot redirect). Everything in the line is quoted; inside
; double quotes cmd treats & | < > ^ literally, but %VAR% is still expanded and a " would end the quoting -> refuse such paths.
CmdSafe(paths*) {
    for p in paths
        if InStr(p, "%") || InStr(p, '"')
            return false
    return true
}

Tip(msg, ms := 2500) {
    ToolTip msg
    if ms > 0
        SetTimer () => ToolTip(), -ms
}

; The hotkey is still physically down when Improve() starts (slow release, or a Ctrl+Alt combination): a synthetic Ctrl+C sent now would reach the
; app as a bare "c" and overwrite the selection. Wait (<= 1 s each) until the modifiers and the hotkey's own key are released.
WaitHotkeyRelease() {
    RegExMatch(HotkeyKey, "^([\^!+#]*)(.*)$", &m)
    for name in ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
        KeyWait name, "T1"
    if m[2] != ""
        try KeyWait m[2], "T1"
}

Improve(*) {
    global Busy
    try exe := WinGetProcessName("A")
    catch
        exe := ""
    if IsTerminalExe(exe) {                ; pass the current hotkey through ($ prefix: our own Send does not re-trigger it)
        RegExMatch(HotkeyKey, "^([\^!+#]*)(.*)$", &m)   ; modifiers + {key}: ^{F2}, ^{q} -- a bare ^F2 would be typed as text
        Send m[1] "{" m[2] "}"
        return
    }
    if Busy {
        Tip "Imprompt: " MSG["busy"]
        return
    }
    WaitHotkeyRelease()
    hwnd := WinExist("A")                 ; remember the window BEFORE copying (a switch during the copy wait must not count)
    Busy := true                          ; lock before touching the clipboard
    saved := ClipboardAll()
    A_Clipboard := ""
    SendInput "{Ctrl down}c{Ctrl up}"     ; explicit Ctrl down/up: never a bare "c" typed over the selection
    if !ClipWait(0.75) || Trim(A_Clipboard) = "" {
        A_Clipboard := saved
        Busy := false
        Tip "Imprompt: " MSG["noSelection"]
        return
    }
    text := A_Clipboard
    ; unique names per run (the selected text is written to inF); every return path below deletes all three in the finally block
    tag := A_TickCount "-" Random(100000, 999999)
    inF := A_Temp "\imprompt-in-" tag ".txt", outF := A_Temp "\imprompt-out-" tag ".txt", errF := A_Temp "\imprompt-err-" tag ".txt"
    try {
        if !CmdSafe(Python, Server, inF, outF, errF) {
            A_Clipboard := saved
            Tip "Imprompt: " Format(MSG["failed"], MSG["badPath"]), 6000
            return
        }
        FileAppend text, inF, "UTF-8"
        StartAnim()
        cmd := '"' Python '" "' Server '" --improve --host ' Host ' --in "' inF '" --out "' outF '"'
        code := RunWait(A_ComSpec ' /c "' cmd ' 2> "' errF '""', , "Hide")
        StopAnim()
        if code != 0 || !FileExist(outF) {
            A_Clipboard := saved
            err := FileExist(errF) ? FileRead(errF, "UTF-8") : ""
            why := Reason(err)
            if RegExMatch(why, "(claude|codex|gemini): login required", &lm) {   ; sign-in problem: offer the sign-in window instead of a tooltip
                if MsgBox(Format(MSG["signAsk"], lm[1]), MSG["signTitle"], "YesNo Iconi 0x40000") = "Yes"
                    SignIn(lm[1])
                return
            }
            Tip "Imprompt: " Format(MSG["failed"], why), 6000
            return
        }
        result := FileRead(outF, "UTF-8")
        if WinExist("A") != hwnd {
            A_Clipboard := result
            MarkClipboardPrivate()
            Tip "Imprompt: " MSG["cancelled"], 5000
            return
        }
        A_Clipboard := result
        MarkClipboardPrivate()
        if !ClipWait(1)
            return
        SendInput "{Ctrl down}v{Ctrl up}"
        Sleep 600                             ; let the paste read the clipboard before restoring it
        A_Clipboard := saved
        MarkClipboardPrivate()
        Tip "Imprompt: " MSG["done"], 1500
    } finally {
        SetTimer AnimTick, 0              ; only stops the animation timer (StopAnim would also erase the tooltip shown above)
        Busy := false
        for f in [inF, outF, errF]
            try FileDelete f
    }
}

; ---------- Hotkey setting (tray menu) ----------
; Stored per user in %APPDATA%\imprompt\hotkey.ini [imprompt] hotkey=<AutoHotkey key name, e.g. ^q>.
; (config/keybindings.json is Claude Code's own Ctrl+Q file, not used here.)
; Change = validate (needs Ctrl/Alt/Win, not a common app shortcut) -> register the new key -> save -> drop the old key.
; Any failure keeps the old key and the old setting.
DefaultKey := "^q"
Reserved := Map("^c", 1, "^v", 1, "^x", 1, "^a", 1, "^z", 1, "^y", 1, "^s", 1, "^f", 1, "^p", 1, "^n", 1, "^o", 1,
                "^w", 1, "^t", 1, "!F4", 1, "!Tab", 1, "#l", 1, "#d", 1, "#e", 1, "#r", 1, "^Esc", 1)
HotkeyKey := IniRead(Ini, "imprompt", "hotkey", DefaultKey)

KeyLabel(k) {
    mods := "", rest := k
    while (rest != "" && InStr("^!+#", SubStr(rest, 1, 1))) {
        c := SubStr(rest, 1, 1), rest := SubStr(rest, 2)
        mods .= (c = "^" ? "Ctrl+" : c = "!" ? "Alt+" : c = "+" ? "Shift+" : "Win+")
    }
    return mods (StrLen(rest) = 1 ? StrUpper(rest) : rest)
}
InvalidReason(k) {
    RegExMatch(k, "^([\^!+#]*)(.*)$", &m)       ; m[1] = modifiers, m[2] = key
    if !RegExMatch(m[1], "[\^!#]") || m[2] = ""  ; needs Ctrl/Alt/Win (Shift alone is not enough) and a real key
        return MSG["keyNeedMod"]
    if Reserved.Has(StrLower(k)) || Reserved.Has(k)
        return Format(MSG["keyReserved"], KeyLabel(k))
    return ""
}
; SetHotkey(new) -> "" on success, otherwise the reason (old key and setting kept)
SetHotkey(new, persist := true) {
    global HotkeyKey
    if (bad := InvalidReason(new)) != ""
        return bad
    if (new = HotkeyKey)
        return ""
    try Hotkey("$" new, Improve, "On")
    catch
        return Format(MSG["keyTaken"], KeyLabel(new))
    if persist {
        try IniWrite(new, Ini, "imprompt", "hotkey")
        catch {
            try Hotkey("$" new, "Off")
            return MSG["keySaveFail"]
        }
    }
    try Hotkey("$" HotkeyKey, "Off")
    HotkeyKey := new
    BuildTray()
    return ""
}
ChangeHotkey(*) {
    g := Gui("+AlwaysOnTop -MinimizeBox", MSG["keyTitle"])
    g.SetFont("s10")
    g.Add("Text", , MSG["keyHint"])
    box := g.Add("Hotkey", "w220", HotkeyKey)
    ok := g.Add("Button", "Default w100", MSG["keySave"])
    cancel := g.Add("Button", "x+10 w100", MSG["keyCancel"])
    ok.OnEvent("Click", SaveClicked)
    SaveClicked(*) {
        r := SetHotkey(box.Value)
        if (r = "") {
            g.Destroy()
            Tip("Imprompt: " Format(MSG["keySet"], KeyLabel(HotkeyKey)), 2500)
        } else
            Tip("Imprompt: " Format(MSG["keyKept"], KeyLabel(HotkeyKey), r), 4000)   ; dialog stays open to try again
    }
    cancel.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()
}
ResetHotkey(*) {
    r := SetHotkey(DefaultKey)
    Tip("Imprompt: " (r = "" ? Format(MSG["keySet"], KeyLabel(HotkeyKey)) : Format(MSG["keyKept"], KeyLabel(HotkeyKey), r)), 3000)
}
; Open the engine's sign-in command in a visible console window (imprompt_mcp.py --sign-in: path checks and the window live in Python)
SignIn(engine := "") {
    if (engine != "" && !RegExMatch(engine, "^(claude|codex|gemini)$"))
        engine := ""
    tag := A_TickCount "-" Random(100000, 999999)
    outF := A_Temp "\imprompt-sign-" tag ".txt", errF := A_Temp "\imprompt-sign-err-" tag ".txt"
    try {
        if !CmdSafe(Python, Server, outF, errF) {
            Tip("Imprompt: " MSG["badPath"], 4000)
            return
        }
        suffix := (engine != "") ? " " engine : ""
        cmd := '"' Python '" "' Server '" --sign-in' suffix
        code := RunWait(A_ComSpec ' /c "' cmd ' > "' outF '" 2> "' errF '""', , "Hide")
        if code != 0
            Tip("Imprompt: " MSG["signFail"] ": " Reason(FileExist(errF) ? FileRead(errF, "UTF-8") : ""), 6000)
    } finally {
        for f in [outF, errF]
            try FileDelete f
    }
}

; Job history report: imprompt_mcp.py --jobs-html writes one self-contained HTML page, opened in the default browser
OpenJobs(*) {
    out := A_AppData "\imprompt\jobs-report.html"
    if !CmdSafe(Python, Server, out) {
        Tip("Imprompt: " MSG["jobsFail"], 3000)
        return
    }
    cmd := '"' Python '" "' Server '" --jobs-html --out "' out '"'
    if RunWait(A_ComSpec ' /c "' cmd '"', , "Hide") = 0 && FileExist(out)
        Run(out)
    else
        Tip("Imprompt: " MSG["jobsFail"], 3000)
}
; ---------- Custom rules (tray menu) ----------
; ~/.imprompt/custom-rules.md is read by imprompt_mcp.py (all rules logic lives there). Every call goes through CmdSafe-checked paths;
; the file is opened in Notepad only if the path ends in custom-rules[.draft].md and exists.
RulesCmd(args, outF, errF) {
    cmd := '"' Python '" "' Server '" ' args
    return RunWait(A_ComSpec ' /c "' cmd ' > "' outF '" 2> "' errF '""', , "Hide")
}
RulesLabel() {
    tag := A_TickCount "-" Random(100000, 999999)
    outF := A_Temp "\imprompt-rstat-" tag ".txt", errF := A_Temp "\imprompt-rstat-err-" tag ".txt"
    label := MSG["rulesOff"]
    try {
        if CmdSafe(Python, Server, outF, errF) && RulesCmd("--rules-status", outF, errF) = 0 && FileExist(outF) {
            j := FileRead(outF, "UTF-8")
            if RegExMatch(j, '"on":\s*true') && RegExMatch(j, '"chars":\s*(\d+)', &m)
                label := Format(MSG["rulesOn"], m[1])
        }
    }
    for f in [outF, errF]
        try FileDelete f
    return label
}
OpenRulesFile(path) {
    if InStr(path, '"') || !RegExMatch(StrLower(path), "\\custom-rules(\.draft)?\.md$") || !FileExist(path) {
        Tip("Imprompt: " MSG["rulesFail"], 3000)
        return false
    }
    Run('notepad.exe "' path '"')
    return true
}
; Runs one rules command; returns the first stdout line ("" on failure, after showing the first stderr line)
RulesRun(args) {
    tag := A_TickCount "-" Random(100000, 999999)
    outF := A_Temp "\imprompt-rules-" tag ".txt", errF := A_Temp "\imprompt-rules-err-" tag ".txt"
    line := ""
    try {
        if !CmdSafe(Python, Server, outF, errF) {
            Tip("Imprompt: " MSG["badPath"], 4000)
            return ""
        }
        code := RulesCmd(args, outF, errF)
        ToolTip
        if code = 0 {
            out := FileExist(outF) ? FileRead(outF, "UTF-8") : ""
            for part in StrSplit(out, "`n", "`r")
                if (line := Trim(part)) != ""
                    break
            if line = ""
                line := " "
        } else
            Tip("Imprompt: " Reason(FileExist(errF) ? FileRead(errF, "UTF-8") : ""), 6000)
    } finally {
        for f in [outF, errF]
            try FileDelete f
    }
    return line
}
; ---------- Custom rules window (tray -> Edit Custom Rules...) ----------
; A list + Name/Rule form (AutoHotkey Gui). No text editor. imprompt_mcp.py does every read/write and check:
;   --rules-items --tsv (list), --rule-put --in F (line 1 name, line 2 old name, rest = rule), --rule-del --in F (line 1 name).
; Names and text go through a temp file, never the command line. A copy of the old file is kept as custom-rules.md.bak.
RulesRunFull(args, &out, &err) {
    tag := A_TickCount "-" Random(100000, 999999)
    outF := A_Temp "\imprompt-ed-" tag ".txt", errF := A_Temp "\imprompt-ed-err-" tag ".txt"
    out := "", err := "", code := -1
    try {
        if !CmdSafe(Python, Server, outF, errF)
            return (err := MSG["badPath"], -1)
        code := RulesCmd(args, outF, errF)
        out := FileExist(outF) ? FileRead(outF, "UTF-8") : ""
        err := FileExist(errF) ? FileRead(errF, "UTF-8") : ""
    } finally {
        for f in [outF, errF]
            try FileDelete f
    }
    return code
}
TsvUnesc(s) {
    r := "", i := 1, n := StrLen(s)
    while i <= n {
        c := SubStr(s, i, 1)
        if (c = "\" && i < n) {
            d := SubStr(s, i + 1, 1), i += 2
            r .= (d = "n") ? "`n" : (d = "t") ? "`t" : d
            continue
        }
        r .= c, i += 1
    }
    return r
}
EdFirst(s) {
    for part in StrSplit(s, "`n", "`r")
        if Trim(part) != ""
            return Trim(part)
    return MSG["edFail"]
}
EditorGui := 0
EditRules(*) {
    global EditorGui
    if EditorGui {
        try {
            EditorGui.Show()
            return
        }
    }
    items := [], chars := 0, limit := 2000, cur := 0, dirty := false
    g := Gui("+Resize -MinimizeBox +MinSize560x360", MSG["edTitle"])
    EditorGui := g
    g.SetFont("s10", "Segoe UI")
    g.Add("Text", "xm ym w200", MSG["edList"])
    lb := g.Add("ListBox", "xm y+4 w200 h300")
    newB := g.Add("Button", "xm y+8 w200", MSG["edNew"])
    g.Add("Text", "x230 ym w420", MSG["edName"])
    nameE := g.Add("Edit", "x230 y+4 w420 Limit60")
    g.Add("Text", "x230 y+10 w420", MSG["edBody"])
    bodyE := g.Add("Edit", "x230 y+4 w420 h196 Multi WantReturn VScroll")
    saveB := g.Add("Button", "x230 y+8 w90 Default", MSG["edAdd"])
    delB := g.Add("Button", "x+8 w90", MSG["edDelete"])
    cnt := g.Add("Text", "x+12 yp+5 w220 Right")
    status := g.Add("Text", "xm y+18 w540", MSG["edPick"])
    closeB := g.Add("Button", "x+10 yp-5 w90", MSG["edClose"])

    Size(n, b) => StrLen("## " n "`n" b) + 1
    Count() {
        n := chars
        if cur
            n -= Size(items[cur]["name"], items[cur]["body"])
        nm := Trim(nameE.Value), bd := Trim(bodyE.Value, " `t`r`n")
        if (nm != "" || bd != "")
            n += Size(nm, StrReplace(bd, "`r`n", "`n"))
        cnt.Value := Format(MSG["edCount"], Max(0, n), limit)
    }
    Render() {
        lb.Delete()
        names := []
        for it in items
            names.Push(it["name"])
        if names.Length
            lb.Add(names)
        if cur
            lb.Choose(cur)
        delB.Enabled := cur != 0
        saveB.Text := cur ? MSG["edSave"] : MSG["edAdd"]
        Count()
    }
    Fill(i) {
        cur := i, dirty := false
        nameE.Value := i ? items[i]["name"] : ""
        bodyE.Value := i ? StrReplace(items[i]["body"], "`n", "`r`n") : ""
        Render()
    }
    Load(selectName := "", keep := false) {
        old := cur
        code := RulesRunFull("--rules-items --tsv", &out, &err)
        items := [], chars := 0
        if code != 0 {
            status.Value := Reason(err)
            Fill(0)
            return
        }
        first := true
        for line in StrSplit(out, "`n", "`r") {
            if line = ""
                continue
            f := StrSplit(line, "`t")
            if first {                     ; only the first line is the "#<TAB>chars<TAB>limit" summary (a rule may be named "#")
                first := false
                if (f.Length >= 3 && f[1] = "#" && IsInteger(f[2]) && IsInteger(f[3]))
                    chars := Integer(f[2]), limit := Integer(f[3])
                continue
            }
            if f.Length >= 2
                items.Push(Map("name", TsvUnesc(f[1]), "body", TsvUnesc(f[2])))
        }
        sel := 0
        for i, it in items
            if (selectName != "" && it["name"] = selectName)
                sel := i
        if (!sel && keep && old && old <= items.Length)
            sel := old
        Fill(sel)
        UpdateRulesLabel()
    }
    LeaveOk() => !dirty || MsgBox(MSG["edDiscard"], MSG["edTitle"], "YesNo Icon? Default2 0x40000") = "Yes"
    Lock(on) {                         ; while a save/delete runs: no typing or clicks, so reloading cannot overwrite newer edits
        for c in [lb, newB, nameE, bodyE, saveB, delB, closeB]
            c.Enabled := !on
        if !on
            delB.Enabled := cur != 0
    }
    EdSend(flag, lines) {
        f := A_Temp "\imprompt-ed-in-" A_TickCount "-" Random(100000, 999999) ".txt"
        if !CmdSafe(f)
            return (status.Value := MSG["badPath"], false)
        try {
            body := ""
            for i, l in lines
                body .= (i > 1 ? "`n" : "") l
            FileAppend(body, f, "UTF-8")
            code := RulesRunFull(flag ' --in "' f '"', &out, &err)
        } finally
            try FileDelete f
        if code != 0 {
            status.Value := EdFirst(err)
            return false
        }
        status.Value := EdFirst(out)
        return true
    }
    lb.OnEvent("Change", ListChanged)
    ListChanged(*) {
        i := lb.Value
        if (i = cur)
            return
        if !LeaveOk() {
            lb.Choose(cur ? cur : 0)
            return
        }
        Fill(i)
        status.Value := MSG["edEditHint"]
    }
    newB.OnEvent("Click", NewClicked)
    NewClicked(*) {
        if !LeaveOk()
            return
        Fill(0)
        status.Value := MSG["edNewHint"]
        nameE.Focus()
    }
    nameE.OnEvent("Change", Edited)
    bodyE.OnEvent("Change", Edited)
    Edited(*) {
        dirty := true
        Count()
    }
    saveB.OnEvent("Click", SaveClicked)
    SaveClicked(*) {
        nm := Trim(nameE.Value), bd := Trim(StrReplace(bodyE.Value, "`r`n", "`n"), " `t`n")
        if (nm = "")
            return (status.Value := MSG["edNoName"], nameE.Focus())
        if (bd = "")
            return (status.Value := MSG["edNoBody"], bodyE.Focus())
        for i, it in items
            if (i != cur && StrLower(it["name"]) = StrLower(nm))
                return (status.Value := Format(MSG["edDup"], nm), nameE.Focus())
        Lock(true)
        try {
            if EdSend("--rule-put", [nm, cur ? items[cur]["name"] : "", bd]) {
                msg := status.Value
                Load(nm)
                status.Value := msg
            }
        } finally
            Lock(false)
    }
    delB.OnEvent("Click", DeleteClicked)
    DeleteClicked(*) {
        if !cur
            return
        nm := items[cur]["name"]
        if MsgBox(Format(MSG["edDelAsk"], nm), MSG["edTitle"], "YesNo Icon! Default2 0x40000") != "Yes"
            return
        Lock(true)
        try {
            if EdSend("--rule-del", [nm]) {
                msg := status.Value
                Load()
                status.Value := msg
            }
        } finally
            Lock(false)
    }
    CloseEditor(*) {
        global EditorGui
        if !LeaveOk()
            return true
        EditorGui := 0
        g.Destroy()
    }
    closeB.OnEvent("Click", CloseEditor)
    g.OnEvent("Close", CloseEditor)
    g.OnEvent("Escape", CloseEditor)
    Load()
    g.Show()
}
ImportBusy := false
ImportRules(*) {
    global ImportBusy
    if ImportBusy {
        Tip "Imprompt: " MSG["importBusy"]
        return
    }
    ImportBusy := true
    try {
        Tip "Imprompt: " MSG["importWait"], 0
        path := RulesRun("--import-rules --host " Host)
        if Trim(path) = "" || !OpenRulesFile(path)
            return
        if MsgBox(MSG["applyBody"], MSG["applyTitle"], "YesNo Iconi 0x40000") = "Yes"
            if RulesRun("--import-rules --apply") != ""
                Tip "Imprompt: " MSG["applied"], 3000
        UpdateRulesLabel()
    } finally
        ImportBusy := false
}
RulesText := MSG["rulesOff"]
UpdateRulesLabel() {
    global RulesText
    new := RulesLabel()
    if (new != RulesText) {
        RulesText := new
        BuildTray()
    }
}
BuildTray() {
    m := A_TrayMenu
    m.Delete()
    m.Add(MSG["jobs"], OpenJobs)
    m.Add(RulesText, (*) => 0)
    m.Disable(RulesText)
    m.Add(MSG["rulesEdit"], EditRules)
    m.Add(MSG["rulesImport"], ImportRules)
    m.Add(MSG["signMenu"], (*) => SignIn())
    m.Add(Format(MSG["keyMenu"], KeyLabel(HotkeyKey)), (*) => 0)
    m.Disable(Format(MSG["keyMenu"], KeyLabel(HotkeyKey)))
    m.Add(MSG["keyChange"], ChangeHotkey)
    if (HotkeyKey != DefaultKey)
        m.Add(Format(MSG["keyReset"], KeyLabel(DefaultKey)), ResetHotkey)
    m.Add()
    m.Add(MSG["remove"], RemoveImprompt)
    m.Add(MSG["exit"], (*) => ExitApp())      ; our items + Exit only (no Edit Script / Window Spy / Pause ...)
    A_IconTip := "Imprompt - " KeyLabel(HotkeyKey)
}
; ---------- Uninstall (tray menu) ----------
; Uninstall Imprompt... = Settings > Apps > Imprompt > Uninstall: install.ps1 remove (after a confirmation)
RemoveImprompt(*) {
    ps1 := A_ScriptDir "\..\install.ps1"
    Loop Files ps1
        ps1 := A_LoopFileFullPath                 ; resolve "..\" to a full path
    if !FileExist(ps1) || !CmdSafe(ps1) {
        Tip("Imprompt: " MSG["removeFail"], 4000)
        return
    }
    if MsgBox(MSG["removeAsk"], MSG["remove"], "YesNo Icon! Default2 0x40000") != "Yes"
        return
    try Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps1 '" remove')
    catch {
        Tip("Imprompt: " MSG["removeFail"], 4000)
        return
    }
    ExitApp                                       ; let go of the files so the folder can be deleted
}

; Register the saved hotkey; if it cannot be used, fall back to the default (and say so)
try Hotkey("$" HotkeyKey, Improve, "On")
catch {
    Tip("Imprompt: " Format(MSG["keyKept"], KeyLabel(DefaultKey), Format(MSG["keyTaken"], KeyLabel(HotkeyKey))), 5000)
    HotkeyKey := DefaultKey
    Hotkey("$" HotkeyKey, Improve, "On")
}
if FileExist(A_ScriptDir "\imprompt.ico")
    try TraySetIcon(A_ScriptDir "\imprompt.ico")   ; app icon instead of AutoHotkey's green H
BuildTray()
SetTimer UpdateRulesLabel, 15000   ; the status line follows edits made in Notepad
UpdateRulesLabel()
CleanStaleTemp()
if A_Args.Length && A_Args[1] = "/ready"   ; only when the installer starts it (not the Startup shortcut): say once where to find it
    TrayTip(Format(MSG["ready"], KeyLabel(HotkeyKey)), "Imprompt")

; Temp files hold the selected text and the result for one run and are deleted in `finally`. If this script was killed
; mid-run (Task Manager, sign-out, power loss) they stay in %TEMP% - remove our own ones older than 10 minutes at start
; (a run lasts at most ~90 s, so nothing in use is touched; only files named imprompt-*.txt)
CleanStaleTemp() {
    Loop Files A_Temp "\imprompt-*.txt" {
        try {
            if DateDiff(A_Now, A_LoopFileTimeModified, "Minutes") > 10
                FileDelete A_LoopFileFullPath
        }
    }
}

# ~/.zshrc (macOS) 또는 ~/.bashrc (Linux·Git Bash) 끝에 추가
# 프롬프트 개선기: Claude Code·Codex 입력창에서 Ctrl+Q → 개선 (~/bin/pi-edit)
export VISUAL="$HOME/bin/pi-edit"  # Claude/Codex 입력창 파일만 개선, 그 외(git 등)는 vim으로 넘김
# Windows 는 셸 rc 대신 Claude Code settings.json env.VISUAL 에 .cmd 래퍼를 넣는다 → snippets/windows-claude-settings-env.json

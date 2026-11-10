import json
from pathlib import Path


class TodoStore:
    """할일 목록을 JSON 파일에 저장한다."""

    def __init__(self, path):
        self.path = Path(path)
        self.items = []
        if self.path.exists():
            self.items = json.loads(self.path.read_text(encoding="utf-8"))

    def add(self, title):
        item = {"id": len(self.items) + 1, "title": title, "done": False}
        self.items.append(item)
        self._save()
        return item

    def list(self):
        return list(self.items)

    def _save(self):
        self.path.write_text(json.dumps(self.items, ensure_ascii=False, indent=1), encoding="utf-8")

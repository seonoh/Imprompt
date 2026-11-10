import sys
from .store import TodoStore


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    store = TodoStore("todo.json")
    if not argv or argv[0] == "list":
        for it in store.list():
            print(f"[{'x' if it['done'] else ' '}] {it['id']}. {it['title']}")
        return 0
    if argv[0] == "add":
        store.add(" ".join(argv[1:]))
        return 0
    print("usage: todo [list|add <title>]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

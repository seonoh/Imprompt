import tempfile, unittest, os
from todo import TodoStore


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(); self.path = os.path.join(self.dir, "t.json")

    def test_add_and_list(self):
        s = TodoStore(self.path); s.add("우유 사기")
        self.assertEqual([i["title"] for i in TodoStore(self.path).list()], ["우유 사기"])

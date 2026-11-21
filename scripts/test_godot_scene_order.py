"""Adding a node to the SceneTree re-enables _process() when its script defines _ready(), so tests
must call set_process(false) only after add_child()."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
FUNCTION = re.compile(r"^func\s+[A-Za-z_][A-Za-z0-9_]*\s*\(")
INSTANTIATE = re.compile(r"\b(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\b[^=\n]*=.*\.instantiate\s*\(")
GET_NODE = re.compile(
    r"\b(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\b[^=\n]*=\s*\(?([A-Za-z_][A-Za-z0-9_]*)\)?\.get_node(?:_or_null)?\s*\("
)
ADD_CHILD = re.compile(r"\badd_child\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)")
SET_PROCESS_FALSE = re.compile(
    r"\(?([A-Za-z_][A-Za-z0-9_]*)\)?(?:\.get_node(?:_or_null)?\([^)]*\))?(?:\s+as\s+[A-Za-z_][A-Za-z0-9_]*)?\)?\.set_process\s*\(\s*false\s*\)"
)


def violations_in_source(name, text):
    problems = []
    unadded_roots = {}
    for number, raw in enumerate(text.splitlines(), 1):
        code = raw.split("#", 1)[0]
        if FUNCTION.match(code):
            unadded_roots = {}
            continue
        for match in INSTANTIATE.finditer(code):
            variable = match[1]
            unadded_roots[variable] = variable
        for match in GET_NODE.finditer(code):
            variable, parent = match[1], match[2]
            if parent in unadded_roots:
                unadded_roots[variable] = unadded_roots[parent]
        for match in SET_PROCESS_FALSE.finditer(code):
            target = match[1]
            if target in unadded_roots:
                root_var = unadded_roots[target]
                problems.append(f"{name}:{number}: add_child({root_var}) 전에 set_process(false) 호출: {raw.strip()}")
        for match in ADD_CHILD.finditer(code):
            added = match[1]
            unadded_roots = {variable: root_var for variable, root_var in unadded_roots.items() if root_var != added}
    return problems


class GodotTestSceneOrderTests(unittest.TestCase):
    def test_all_godot_tests_disable_process_after_add_child(self):
        problems = []
        for path in sorted((ROOT / "tests").glob("*.gd")):
            problems += violations_in_source(path.relative_to(ROOT).as_posix(),
                                             path.read_text(encoding="utf-8"))
        self.assertEqual(problems, [])

    def test_set_process_false_before_add_child_is_rejected(self):
        child_before_add = """func _test_bad_child() -> void:
\tvar main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
\tvar stage_battle: Node2D = main.get_node("Battle") as Node2D
\tstage_battle.set_process(false)
\troot.add_child(main)
"""
        direct_before_add = """func _test_bad_direct() -> void:
\tvar battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
\tbattle.set_process(false)
\troot.add_child(battle)
"""
        chained_before_add = """func _test_bad_chained() -> void:
\tvar main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
\t(main.get_node("Battle") as Node2D).set_process(false)
\troot.add_child(main)
"""
        self.assertEqual(
            violations_in_source("tests/fixture.gd", child_before_add),
            ["tests/fixture.gd:4: add_child(main) 전에 set_process(false) 호출: stage_battle.set_process(false)"],
        )
        self.assertEqual(
            violations_in_source("tests/fixture.gd", direct_before_add),
            ["tests/fixture.gd:3: add_child(battle) 전에 set_process(false) 호출: battle.set_process(false)"],
        )
        self.assertEqual(
            violations_in_source("tests/fixture.gd", chained_before_add),
            ['tests/fixture.gd:3: add_child(main) 전에 set_process(false) 호출: '
             '(main.get_node("Battle") as Node2D).set_process(false)'],
        )

    def test_set_process_false_after_add_child_passes(self):
        valid = """func _test_good() -> void:
\tvar main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
\tvar stage_battle: Node2D = main.get_node("Battle") as Node2D
\troot.add_child(main)
\tstage_battle.set_process(false)
"""
        self.assertEqual(violations_in_source("tests/fixture.gd", valid), [])


if __name__ == "__main__":
    unittest.main()

"""Fault-injection checks for CSV integrity and semantic reference validation."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location(
    "design_checks", Path(__file__).with_name("check-design-examples.py"))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class DesignCSVValidationTests(unittest.TestCase):
    def parse(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "example.csv"
            path.write_text(content, encoding="utf-8")
            return checks.read_table(path)

    def tables(self, concept="storage.sqlite", tags="concurrency,recovery"):
        return {
            "concepts.csv": [
                {"id": "storage", "description": "Storage.", "parent": ""},
                {"id": "storage.sqlite", "description": "Transactions.", "parent": "storage"}],
            "rules.csv": [{"rule_id": "writer", "concept": concept, "tags": tags}],
        }

    def test_quoted_commas_quotes_and_unicode_survive(self):
        rows = self.parse('id,description,concept,tags\nwriter,"Owned, ""durable"" café",storage.sqlite,"concurrency,recovery"\n')
        self.assertEqual(rows[0]["description"], 'Owned, "durable" café')
        tables = self.tables()
        tables["rules.csv"] = rows
        self.assertEqual(checks.check_concepts(tables), 2)

    def test_bad_csv_fails(self):
        for text in [
            '', 'id,id\na,b\n', 'id,\na,b\n', '\ufeffid,value\na,b\n',
            'id,value\na,b,c\n', 'id,value\na\n', 'id,value\n,b\n',
            'id,value\na,b\na,c\n', 'id,value\na,"unterminated\n',
            'id,value\na,"first\nsecond"\n', 'id,value\na,"x"garbage\n',
        ]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.parse(text)

    def test_unknown_empty_or_malformed_references_fail(self):
        for concept in ["", "storage.missing", "Storage.sqlite", " storage.sqlite"]:
            with self.subTest(concept=concept), self.assertRaises(ValueError):
                checks.check_concepts(self.tables(concept=concept))

    def test_optional_tags_and_unannotated_table(self):
        tables = self.tables(tags="")
        tables["stages.csv"] = [{"stage_id": "period.plan", "executor": "Coordinator"}]
        self.assertEqual(checks.check_concepts(tables), 2)

    def test_invalid_tags_fail(self):
        for tags in ["recovery,recovery", "recovery, concurrency", "Recovery", "recovery,", "x;y"]:
            with self.subTest(tags=tags), self.assertRaises(ValueError):
                checks.check_concepts(self.tables(tags=tags))

    def test_registry_ids_descriptions_and_parents(self):
        changes = [
            {"id": "Storage.sqlite"}, {"id": "storage..sqlite"}, {"description": ""},
            {"parent": "missing"}, {"parent": "storage.sqlite"}, {"parent": ""},
        ]
        for change in changes:
            tables = self.tables()
            tables["concepts.csv"][1].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                checks.check_concepts(tables)

    def test_duplicate_registry_id_fails(self):
        tables = self.tables()
        tables["concepts.csv"].append(dict(tables["concepts.csv"][1]))
        with self.assertRaises(ValueError):
            checks.check_concepts(tables)

    def test_missing_registry_fails(self):
        for tables in [{}, {"concepts.csv": []}]:
            with self.subTest(tables=tables), self.assertRaises(ValueError):
                checks.check_concepts(tables)


if __name__ == "__main__":
    unittest.main()

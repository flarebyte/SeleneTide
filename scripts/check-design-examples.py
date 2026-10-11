#!/usr/bin/env python3
"""Check design-source references and generated coverage; not a query DSL engine."""

import csv
import argparse
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
META = ROOT / "doc/design-meta"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_json(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_table(path):
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.reader(stream, strict=True)
        rows = []
        previous_line = 0
        try:
            for row in reader:
                require(reader.line_num == previous_line + 1,
                        f"Multiline CSV record: {path}:{previous_line + 1}")
                previous_line = reader.line_num
                rows.append(row)
        except csv.Error as error:
            raise ValueError(f"Invalid CSV: {path}:{reader.line_num}: {error}") from error
    require(rows and rows[0] and all(cell.strip() == cell and cell for cell in rows[0])
            and len(set(rows[0])) == len(rows[0]), f"Invalid header: {path}")
    require(not rows[0][0].startswith("\ufeff"), f"Unexpected BOM: {path}")
    require(all(len(row) == len(rows[0]) for row in rows), f"Invalid row width: {path}")
    require(all(row[0] and row[0].strip() == row[0] for row in rows[1:]), f"Invalid ID: {path}")
    require(len({row[0] for row in rows[1:]}) == len(rows) - 1, f"Duplicate IDs: {path}")
    return [dict(zip(rows[0], row)) for row in rows[1:]]


def check_concepts(tables):
    require("concepts.csv" in tables and tables["concepts.csv"], "Missing/empty concept registry")
    registry = tables["concepts.csv"]
    require(all(set(row) == {"id", "description", "parent"} for row in registry),
            "Unexpected concept registry columns")
    identifiers = [row["id"] for row in registry]
    require(len(set(identifiers)) == len(identifiers), "Duplicate concept IDs")
    concepts = set(identifiers)
    for row in registry:
        identifier = row["id"]
        require(re.fullmatch(r"[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)*", identifier),
                f"Invalid concept ID: {identifier}")
        require(row["description"].strip(), f"Empty concept description: {identifier}")
        parent = row["parent"]
        require(not parent or parent in concepts, f"Unknown concept parent: {identifier}: {parent}")
        # Immediate prefix parents establish a tree and prohibit cycles/self-parenting.
        require(parent == identifier.rpartition(".")[0], f"Invalid concept hierarchy: {identifier}")
    for name, rows in tables.items():
        for row in rows:
            if "concept" in row:
                require(row["concept"] in concepts, f"Unknown/empty concept in {name}: {row['concept']}")
            if "tags" in row:
                tags = row["tags"].split(",") if row["tags"] else []
                require(len(tags) == len(set(tags)) and all(
                    re.fullmatch(r"[a-z][a-z0-9-]*", tag) for tag in tags),
                    f"Invalid/duplicate tags in {name}: {row['tags']}")
    return len(concepts)


def escape_cell(value):
    return value.replace("\r\n", "\n").replace("\r", "\n").replace("|", "\\|").replace("\n", "<br/>")


def heading_anchors(markdown):
    anchors, counts = set(), {}
    in_code = False
    for line in markdown.splitlines():
        if line.startswith("```"):
            in_code = not in_code
        heading = re.match(r"^#{1,6} (.+)$", line) if not in_code else None
        if heading:
            slug = re.sub(r"[^\w -]", "", heading.group(1).lower()).replace(" ", "-")
            occurrence = counts.get(slug, 0)
            anchors.add(f"{slug}-{occurrence}" if occurrence else slug)
            counts[slug] = occurrence + 1
    return anchors


def check_links(generated):
    for link in re.findall(r"\]\(([^)]+)\)", generated.read_text()):
        if link.startswith(("https://", "http://")):
            continue
        path, _, anchor = link.partition("#")
        target = generated.parent / path if path else generated
        require(target.exists(), f"Broken generated link: {link}")
        if anchor:
            require(anchor in heading_anchors(target.read_text()), f"Broken section link: {link}")


def main(csv_only=False):
    paths = sorted(path for path in (META / "examples").rglob("*")
                   if path.is_file() and not path.name.startswith("."))
    tables = {path.name: read_table(path) for path in paths if path.suffix == ".csv"}
    concept_count = check_concepts(tables)
    if csv_only:
        print(f"Checked {len(tables)} CSV files and {concept_count} registered concepts, "
              "references, IDs, tags, and single-line record integrity.")
        return
    model = json.loads(subprocess.check_output(
        ["cue", "export", "./doc/design-meta", "--out", "json"], cwd=ROOT, text=True))
    reports = {Path(report["filepath"]).name: report for report in model["reports"]}
    require(len(reports) == len(model["reports"]) == 2, "Expected two distinct design reports")
    require(set(reports) == {"selenetide-specs.md", "overview.md"}, "Unexpected design reports")
    file_notes = [note for note in model["notes"] if "filepath" in note]
    targets = [(META / note["filepath"]).resolve(strict=True) for note in file_notes]
    require(len(targets) == len(set(targets)), "An example is registered more than once")
    require(set(targets) == {path.resolve() for path in paths}, "Example coverage differs from flyb notes")
    referenced = set()

    def sections(items, report_references):
        for item in items:
            report_references.extend(item.get("notes", []))
            sections(item.get("sections", []), report_references)

    for report in reports.values():
        report_references = []
        sections(report["sections"], report_references)
        require(len(report_references) == len(set(report_references)), "Duplicate report note references")
        referenced.update(report_references)
        check_links((META / report["filepath"]).resolve(strict=True))
    require(referenced == {note["name"] for note in model["notes"]}, "Unreported notes")
    generated = (META / reports["selenetide-specs.md"]["filepath"]).resolve(strict=True)
    markdown = generated.read_text()
    for path in paths:
        source_link = f"[{path.name}](../design-meta/{path.relative_to(META).as_posix()})"
        require(markdown.count(source_link) == 1, f"Missing/duplicate source link: {path}")
        if path.suffix == ".csv":
            rows = tables[path.name]
            with path.open(newline="") as stream:
                header = next(csv.reader(stream))
            columns = sorted(header)
            for row in [dict(zip(header, header)), *rows]:
                line = "| " + " | ".join(escape_cell(row[column]) for column in columns) + " |"
                require(line in markdown, f"Missing generated CSV row: {path}: {row[header[0]]}")
        else:
            require(path.read_text().strip() in markdown, f"Missing code/email content: {path}")
    overview = (META / reports["overview.md"]["filepath"]).read_text()
    visible_overview = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", overview)
    overview_words = len(visible_overview.split())
    require(500 <= overview_words <= 700, "Keep the executive overview between 500 and 700 words")

    feature_ids = {row["feature_id"] for row in tables["features.csv"]}
    for row in tables["practical_use_cases.csv"]:
        require(set(row["related_feature_ids"].split(";")) <= feature_ids,
                f"Unknown feature in {row['use_case_id']}")

    test_catalogue = tables["test_catalog.csv"]
    require(test_catalogue, "Test catalogue is empty")
    require(set(test_catalogue[0]) == {
        "test_id", "test_level", "area", "title", "desc", "related_note_ids", "concept", "tags"
    }, "Unexpected test catalogue columns")
    require({row["test_level"] for row in test_catalogue} == {"unit", "integration"},
            "Test catalogue must contain unit and integration suites only")
    spec_notes = {note["name"] for note in model["notes"]} - {"selenetide.testing.catalog"}
    for row in test_catalogue:
        require(all(value.strip() for key, value in row.items() if key != "tags"),
                f"Empty test catalogue field: {row['test_id']}")
        require(row["test_id"].startswith(row["test_level"] + "."),
                f"Test ID disagrees with level: {row['test_id']}")
        related = row["related_note_ids"].split(";")
        require(len(related) == len(set(related)) and set(related) <= spec_notes,
                f"Invalid specification references: {row['test_id']}")

    workflow_fields = tables["sqlite_workflow_fields.csv"]
    pipeline_fields = tables["sqlite_email_pipeline_fields.csv"]
    fields = {(row["entity"], row["field"]): row for row in workflow_fields + pipeline_fields}
    require(len(fields) == len(workflow_fields) + len(pipeline_fields), "Duplicate entity fields")
    for row in fields.values():
        inverse = re.search(r"inverse=(\w+)", row["relationship"])
        if inverse:
            target = row["logical_type"]
            target = re.sub(r"^To-(?:one|many) ", "", target).strip("[]")
            require((target, inverse.group(1)) in fields,
                    f"Unknown inverse: {row['entity']}.{row['field']}")

    stages = {row["stage_id"]: row for row in tables["period_workflow_stages.csv"]}
    require(len({row["task_kind"] for row in stages.values()}) == len(stages), "Duplicate task kinds")
    dependencies = {}
    for name, row in stages.items():
        raw = row["depends_on"]
        # Catalogue gates map to concrete task dependencies at runtime.
        raw = raw.replace(" when instantiated", "")
        dependencies[name] = [value for value in raw.split(";") if value]
        require(set(dependencies[name]) <= stages.keys(), f"Unknown stage dependency: {name}")
    visited, active = set(), set()

    def visit(name):
        require(name not in active, f"Stage dependency cycle: {name}")
        if name in visited:
            return
        active.add(name)
        for parent in dependencies[name]:
            visit(parent)
        active.remove(name)
        visited.add(name)

    for name in stages:
        visit(name)
    require(all(row["applies_when"] != "always" for name, row in stages.items()
                if name.startswith("parquet.")), "Unconditional archive stages block open-period sync")

    catalogue = tables["query_catalog.csv"]
    datasets = {row["dataset"] for row in catalogue if row["item_kind"] == "dataset"}
    require(all(row["name"] == row["dataset"] for row in catalogue if row["item_kind"] == "dataset"),
            "Dataset name mismatch")
    require(datasets == {"email_metadata", "processing_results"}, "Unexpected query datasets")
    metadata_columns = {row["column_name"] for row in tables["email_metadata_parquet_columns.csv"]
                        if row["schema_placement"] == "core_column"}
    processing_columns = {row["column_name"] for row in tables["duckdb_processing_export_tables.csv"]
                          if "live" in row["tables"].split("|")}
    for row in catalogue:
        if row["item_kind"] == "column":
            source = metadata_columns if row["dataset"] == "email_metadata" else processing_columns
            require(row["sql_mapping"] in source, f"Unknown physical query column: {row['catalog_id']}")

    examples = json.loads((META / "examples/query/email_query_examples.json").read_text(),
                         object_pairs_hook=unique_json)
    require(len({example["name"] for example in examples}) == len(examples), "Duplicate query example names")
    allowed_keys = set("from select where group_by having order_by limit offset values relationships count stats".split())
    aggregates = {row["name"] for row in catalogue if row["item_kind"] == "aggregate"}
    functions = {row["name"] for row in catalogue if row["item_kind"] == "function"}
    for example in examples:
        query = example["request"]
        require(query.keys() <= allowed_keys, f"Unknown request keys: {example['name']}")
        require(query["from"] in datasets, f"Unknown dataset: {example['name']}")
        require(sum(key in query for key in ("select", "count", "stats")) <= 1, "Conflicting query modes")
        columns = {row["name"]: row for row in catalogue
                   if row["dataset"] == query["from"] and row["item_kind"] in {"column", "virtual_column"}}

        def column(name, context):
            require(name in columns and context in columns[name]["allowed_in"].split("|"),
                    f"Disallowed {context} column {name} in {example['name']}")

        grouped = query.get("group_by", [])
        outputs = set(grouped)
        for context in ("select", "group_by"):
            for name in query.get(context, []):
                column(name, context)
        outputs.update(query.get("select", []))
        used_values = set()
        if "count" in query:
            require(query["count"] is True, "Count must be true")
            outputs.add("count")
        for name, stats in query.get("stats", {}).items():
            column(name, "stats")
            for stat in stats:
                function = stat if isinstance(stat, str) else stat["function"]
                require(function in aggregates, f"Unknown aggregate: {function}")
                alias = stat.get("as", f"{name}_{function}") if isinstance(stat, dict) else f"{name}_{function}"
                require(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", alias) and alias not in outputs,
                        f"Invalid/colliding aggregate alias: {alias}")
                outputs.add(alias)
                if function == "quantile":
                    variable = stat["probability"]
                    require(re.fullmatch(r"\$[A-Za-z_][A-Za-z0-9_]*", variable), "Invalid probability reference")
                    used_values.add(variable[1:])
                    probability = query.get("values", {}).get(variable[1:])
                    require(type(probability) in (float, int) and 0 <= probability <= 1, "Invalid quantile probability")
        for context in ("where", "having"):
            expression = query.get(context, "")
            used_values.update(re.findall(r"\$([A-Za-z_][A-Za-z0-9_]*)", expression))
            for token in re.finditer(r"\$?[A-Za-z_][A-Za-z0-9_]*", expression):
                name = token.group()
                if name.startswith("$") or name in {"not", "and", "or", "in"}:
                    continue
                if expression[token.end():].lstrip().startswith("("):
                    require(name in functions, f"Unknown expression function: {name}")
                elif context == "having" and name in outputs:
                    continue
                else:
                    column(name, context)
        require(used_values == query.get("values", {}).keys(), f"Missing/unused values: {example['name']}")
        for order in query.get("order_by", []):
            require(order["field"] in outputs, f"Unknown order output: {order['field']}")
            require(order["direction"] in {"asc", "desc"}, "Invalid order direction")
        for control in ("limit", "offset"):
            if control in query:
                require(type(query[control]) is int and 0 <= query[control] <= 2**53 - 1, "Invalid result control")

    fixture = (META / "examples/content/simple_email_with_html.eml").read_bytes()
    from email import policy
    from email.parser import BytesParser
    message = BytesParser(policy=policy.default).parsebytes(fixture)
    require(not message.defects and message.get_content_type() == "multipart/alternative", "Invalid MIME fixture")
    require({part.get_content_type() for part in message.iter_parts()} == {"text/plain", "text/html"},
            "MIME fixture alternatives differ")
    print(f"Checked {len(paths)} examples, {sum(map(len, tables.values()))} CSV rows, "
          f"{len(examples)} query requests, entity inverses, stage gates, MIME, and complete generated coverage.")
    print(f"Checked both reports and their section links; executive overview: {overview_words} words.")
    print(f"Checked {concept_count} registered concepts, references, tags, and single-line CSV integrity.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv-only", action="store_true",
                        help="Validate CSV sources without CUE or generated Markdown")
    main(csv_only=parser.parse_args().csv_only)

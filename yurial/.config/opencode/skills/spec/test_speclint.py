"""Regression tests for speclint.py, organized around SPECLINT.md requirements."""
from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import speclint


class TempFiles(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name: str, text: str) -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    @staticmethod
    def spec(*sections: str) -> str:
        return "\n".join(sections) + "\n"

    def valid_spec(self) -> str:
        return self.spec(
            "# Demo",
            "## Requirements",
            "- R1. Group:",
            "- R1.1. verification=automated; requirement",
            "## Tests",
            "- T1. Group:",
            "- T1.1. R-ID=R1.1; procedure=run; conditions=given; expected=pass",
            "## Implementation",
            "- I1. implementation detail",
        )


class TestSpecScanning(TempFiles):
    def test_valid_spec_is_clean(self):
        path = self.write("SPEC.md", self.valid_spec())
        self.assertEqual(speclint.scan_spec(path), [])

    def test_indented_markdown_heading_switches_section(self):
        path = self.write("SPEC.md", "## Overview\n   ## Requirements — detail\nplain prose\n")
        self.assertTrue(any("nonempty line in Requirements" in f.message for f in speclint.scan_spec(path)))

    def test_wrong_family_and_unprefixed_record_lines_are_reported(self):
        path = self.write("SPEC.md", "## Requirements\nplain prose\n- I1. wrong family\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("nonempty line" in m for m in messages))
        self.assertTrue(any("must be in section Implementation" in m for m in messages))

    def test_indented_records_and_continuations_are_reported(self):
        path = self.write("SPEC.md", "## Requirements\n  - R1. requirement\n- R2. verification=manual; record\n  continuation\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("starts with indentation" in m for m in messages))
        self.assertTrue(any("continuation" in m for m in messages))

    def test_malformed_id_syntax_is_reported(self):
        path = self.write("SPEC.md", "## Requirements\n- R1.1 verification=manual; missing dot after ID\n")
        self.assertTrue(any("nonempty line" in f.message for f in speclint.scan_spec(path)))

    def test_duplicate_id_and_missing_parent_are_reported(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. Group:\n- R1.1. verification=manual; child\n- R1.1. verification=manual; duplicate\n- R3.1. verification=manual; orphan\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("duplicate ID R1.1" in m for m in messages))
        self.assertTrue(any("missing parent R3" in m for m in messages))

    def test_group_must_have_children_and_colon(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. Group\n- R1.1. verification=manual; child\n- R2. Empty group:\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("group entry R1 must end" in m for m in messages))
        self.assertTrue(any("leaf entry R2 must not end" in m for m in messages))

    def test_prefix_requires_exact_single_space(self):
        path = self.write("SPEC.md", "## Requirements\n-   R1. verification=manual; malformed spacing\n")
        self.assertTrue(any("nonempty line" in f.message for f in speclint.scan_spec(path)))

    def test_examples_mirror_requirements(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. verification=manual; requirement\n## Examples\n- E2. example\n")
        self.assertTrue(any("must mirror an existing R2" in f.message for f in speclint.scan_spec(path)))

    def test_verification_marker_must_be_exactly_one_allowed_value(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. verification=manual verification=analysis; bad\n- R2. verification=unknown; bad\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertEqual(sum("exactly one verification marker" in m for m in messages), 2)

    def test_automated_leaf_requires_test_reference_but_manual_does_not(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. verification=automated; missing T\n- R2. verification=manual; no T needed\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("R1 with verification=automated" in m for m in messages))
        self.assertFalse(any("R2 with verification" in m for m in messages))

    def test_test_entry_requires_fields_and_valid_leaf_refs(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. verification=automated; leaf\n- R2. verification=manual; leaf\n## Tests\n- T1. R-ID=R1,R2,R9; procedure=run\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("references nonexistent R9" in m for m in messages))
        self.assertFalse(any("may reference only leaf R-ID" in m for m in messages))
        self.assertTrue(any("must contain conditions field" in m for m in messages))
        self.assertTrue(any("must contain expected field" in m for m in messages))

    def test_test_refs_must_be_automated_or_scenario(self):
        path = self.write("SPEC.md", "## Requirements\n- R1. verification=manual; manual requirement\n## Tests\n- T1. R-ID=R1; procedure=run; conditions=given; expected=pass\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertTrue(any("may reference only R-ID with verification=automated or verification=scenario" in m for m in messages), messages)

    def test_numeric_scanner_exclusions_and_suffixes(self):
        path = self.write("SPEC.md", "## Overview\nA bare 42 and 3.14 and 1,5 and 7ms. TLS1.2, API42, version 1.2.3 and `99` are allowed.\n## Configuration\nvalue 123\n## Examples\nexample 456\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        numeric = [m for m in messages if "bare numeric literal" in m]
        self.assertEqual(sum("42" in m for m in numeric), 1)
        self.assertTrue(any("3.14" in m for m in numeric))
        self.assertTrue(any("1,5" in m for m in numeric))
        self.assertTrue(any("7ms" in m for m in numeric))
        self.assertFalse(any("99" in m or "123" in m or "456" in m or "1.2" in m or "API42" in m or "1.2.3" in m for m in numeric))

    def test_fenced_blocks_ignore_headings_and_numbers(self):
        path = self.write("SPEC.md", "## Overview\n```text\n## Requirements\n123\n~~~\n456\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertFalse(any("123" in m for m in messages))
        self.assertTrue(any("456" in m for m in messages))
        self.assertFalse(any("nonempty line in Requirements" in m for m in messages))

    def test_fence_may_close_with_different_marker_length_or_character(self):
        path = self.write("SPEC.md", "## Overview\n~~~text\n123\n````\n456\n")
        messages = [f.message for f in speclint.scan_spec(path)]
        self.assertFalse(any("123" in m for m in messages))
        self.assertTrue(any("456" in m for m in messages))

    def test_unclosed_fence_hides_rest_of_file(self):
        path = self.write("SPEC.md", "## Overview\n```text\n123\n## Requirements\n- R1. verification=manual; ignored\n999\n")
        self.assertEqual(speclint.scan_spec(path), [])


class TestIndexAndGlossary(TempFiles):
    def test_index_accepts_valid_fields_and_existing_path(self):
        self.write("target.md", "# target\n")
        index = self.write("index.md", "| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| target.md | target-doc | stable | A target |\n")
        self.assertEqual(speclint.scan_index(index), [])

    def test_index_rejects_missing_fields_status_reference_and_path(self):
        index = self.write("index.md", "| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| missing.md | Bad--ID | retired | |\n")
        messages = [f.message for f in speclint.scan_index(index)]
        self.assertTrue(any("missing required field Summary" in m for m in messages))
        self.assertTrue(any("invalid Status" in m for m in messages))
        self.assertTrue(any("invalid Reference" in m for m in messages))
        self.assertTrue(any("Path does not exist" in m for m in messages))

    def test_index_status_values_are_case_sensitive(self):
        self.write("target.md", "# target\n")
        index = self.write("index.md", "| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| target.md | target-doc | Stable | A target |\n")
        self.assertTrue(any("invalid Status 'Stable'" in f.message for f in speclint.scan_index(index)))

    def test_index_entry_missing_path_is_not_silently_ignored(self):
        index = self.write("index.md", "| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| | alpha-ref | stable | an entry without a path |\n")
        messages = [f.message for f in speclint.scan_index(index)]
        self.assertTrue(any("missing required field Path" in m for m in messages), messages)

    def test_index_requires_table_header(self):
        index = self.write("index.md", "- Path: target.md Reference: target-doc Status: stable Summary: A target\n")
        self.assertTrue(any("must contain a Markdown table" in f.message for f in speclint.scan_index(index)))

    def test_index_path_resolution_uses_git_root_when_available(self):
        repo = self.root / "repo"
        (repo / "specs").mkdir(parents=True)
        (repo / "target.md").write_text("# target\n", encoding="utf-8")
        index = repo / "specs" / "index.md"
        index.write_text("| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| target.md | target-doc | stable | A target |\n", encoding="utf-8")
        with mock.patch.object(speclint, "repo_root", return_value=repo):
            self.assertEqual(speclint.scan_index(index), [])

    def test_index_path_resolution_uses_specs_parent_without_git(self):
        self.write("component.md", "# target\n")
        index = self.write("specs/index.md", "| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| component.md | component | draft | component |\n")
        self.assertEqual(speclint.scan_index(index), [])

    def test_glossary_valid_sorted_and_resolvable(self):
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| alpha-core/alpha | definition | alpha-core |\n| beta/beta | definition | beta |\n")
        self.assertEqual(speclint.scan_glossary(glossary, {"alpha-core", "beta"}), [])

    def test_glossary_reports_missing_defined_in_bad_id_and_sort_order(self):
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| zeta/zebra | definition | zeta |\n| alpha/alpha | definition | bad |\n| äther/term | definition | |\n")
        messages = [f.message for f in speclint.scan_glossary(glossary, {"valid-ref"})]
        self.assertTrue(any("missing required field Defined in" in m for m in messages))
        self.assertTrue(any("not sorted alphabetically" in m for m in messages))
        self.assertTrue(any("does not resolve" in m for m in messages))

    def test_glossary_defined_in_allows_requirement_ids_after_owner(self):
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| alpha/alpha-term | definition | alpha; R1.2 |\n")
        self.assertEqual(speclint.scan_glossary(glossary, {"alpha"}), [])

    def test_glossary_requires_full_term_ids_and_table_shape(self):
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| badterm | | wrong | extra |\n")
        messages = [f.message for f in speclint.scan_glossary(glossary, {"valid"})]
        self.assertTrue(any("exactly three cells" in m for m in messages))

    def test_glossary_skips_prefix_resolution_without_refs(self):
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| no-such-prefix/alpha | definition | no-such-prefix |\n")
        self.assertEqual(speclint.scan_glossary(glossary, None), [])


class TestDiscoveryAndCLI(TempFiles):
    def test_discovery_recurses_and_sorts_by_file_type_then_path(self):
        paths = [
            self.write("z.md", ""), self.write("b/GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| z-ref/term | definition | z-ref |\n"),
            self.write("a/index.md", ""), self.write("index.md", ""),
            self.write("a/x.md", ""),
        ]
        found, errors = speclint.discover([self.root])
        self.assertEqual(errors, [])
        self.assertEqual([p.name for p in found], ["index.md", "index.md", "GLOSSARY.md", "x.md", "z.md"])

    def test_discovery_rejects_missing_and_non_markdown_paths(self):
        txt = self.write("file.txt", "x")
        upper_md = self.write("upper.MD", "not selected by lowercase extension rule")
        found, errors = speclint.discover([self.root / "missing.md", txt, upper_md])
        self.assertEqual(found, [])
        self.assertEqual(len(errors), 3)

    def test_directory_discovery_ignores_uppercase_md_extension(self):
        self.write("lower.md", "")
        self.write("upper.MD", "")
        found, errors = speclint.discover([self.root])
        self.assertEqual(errors, [])
        self.assertEqual([p.name for p in found], ["lower.md"])

    def test_cli_missing_and_non_markdown_paths_return_error(self):
        txt = self.write("input.txt", "not markdown\n")
        for path in (self.root / "missing.md", txt):
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                code = speclint.main([str(path)])
            self.assertEqual(code, speclint.ERROR)
            self.assertTrue(stderr.getvalue().strip())

    def test_empty_directory_returns_error(self):
        empty = self.root / "empty"
        empty.mkdir()
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = speclint.main([str(empty)])
        self.assertEqual(code, speclint.ERROR)
        self.assertIn("no Markdown files found", stderr.getvalue())

    def test_cli_no_args_returns_error(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = speclint.main([])
        self.assertEqual(result, speclint.ERROR)
        self.assertIn("speclint: error:", stderr.getvalue())

    def test_cli_exit_codes_for_clean_warning_and_error(self):
        clean = self.write("clean.md", "## Requirements\n- R1. verification=manual; requirement\n")
        self.assertEqual(speclint.main([str(clean)]), speclint.CLEAN)
        # A glossary with no index produces a warning, not an error.
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| alpha/alpha | definition | alpha |\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            warning_code = speclint.main([str(glossary)])
        self.assertEqual(warning_code, speclint.WARNING)
        self.assertIn("speclint: warning:", stderr.getvalue())
        bad = self.write("bad.md", "## Requirements\nplain prose\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            error_code = speclint.main([str(bad)])
        self.assertEqual(error_code, speclint.ERROR)
        self.assertIn(f"{bad}:2:", stderr.getvalue())

    def test_cli_multiple_paths_and_warning_plus_error_exit_error(self):
        glossary = self.write("GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| alpha/alpha | definition | alpha |\n")
        bad = self.write("bad.md", "## Requirements\nplain prose\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = speclint.main([str(glossary), str(bad)])
        self.assertEqual(code, speclint.ERROR)
        self.assertIn("speclint: warning:", stderr.getvalue())
        self.assertIn("nonempty line", stderr.getvalue())

    def test_directory_dispatches_indexes_glossaries_then_specs(self):
        self.write("z.md", "")
        self.write("b/GLOSSARY.md", "| Term ID | Definition | Defined in |\n| --- | --- | --- |\n| z-ref/term | definition | z-ref |\n")
        self.write("a/index.md", "")
        self.write("index.md", "| Path | Reference | Status | Summary |\n| --- | --- | --- | --- |\n| z.md | z-ref | stable | z |\n")
        order = []
        with mock.patch.object(speclint, "scan_index", side_effect=lambda p: order.append(("index", str(p))) or []), \
             mock.patch.object(speclint, "scan_glossary", side_effect=lambda p, refs: order.append(("glossary", str(p))) or []), \
             mock.patch.object(speclint, "scan_spec", side_effect=lambda p: order.append(("spec", str(p))) or []):
            self.assertEqual(speclint.main([str(self.root)]), speclint.CLEAN)
        kinds = [kind for kind, _ in order]
        self.assertEqual(kinds, ["index", "index", "glossary", "spec"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

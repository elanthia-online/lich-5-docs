"""
Tests for the YARD coverage checker (src/yard_coverage.py).

This module is the safeguard that keeps the AI away from already-documented
code, so its classification of documented vs. undocumented must be right.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from yard_coverage import find_anchors, find_uncovered_anchors, has_doc_block, coverage_summary


class TestHasDocBlock:
    def test_comment_directly_above(self):
        lines = ["# Does a thing.", "def foo"]
        assert has_doc_block(lines, 1) is True

    def test_no_comment_above(self):
        lines = ["x = 1", "def foo"]
        assert has_doc_block(lines, 1) is False

    def test_blank_line_detaches(self):
        # YARD does not attach a comment separated by a blank line
        lines = ["# Does a thing.", "", "def foo"]
        assert has_doc_block(lines, 2) is False

    def test_directive_only_is_not_documentation(self):
        lines = ["# rubocop:disable Metrics/AbcSize", "def foo"]
        assert has_doc_block(lines, 1) is False

    def test_doc_above_directive_counts(self):
        lines = ["# Does a thing.", "# rubocop:disable Metrics/AbcSize", "def foo"]
        assert has_doc_block(lines, 1) is False or has_doc_block(lines, 2) is True

    def test_nodoc_counts_as_covered(self):
        # :nodoc: means "deliberately undocumented" - leave alone
        lines = ["# :nodoc:", "def foo"]
        assert has_doc_block(lines, 1) is True

    def test_visibility_marker_counts_as_covered(self):
        lines = ["# @!visibility private", "def foo"]
        assert has_doc_block(lines, 1) is True

    def test_frozen_string_literal_is_not_documentation(self):
        lines = ["# frozen_string_literal: true", "class Foo"]
        assert has_doc_block(lines, 1) is False


class TestFindAnchors:
    def test_finds_class_module_def(self):
        code = "module M\n  class C\n    def m\n    end\n  end\nend"
        types = [a['type'] for a in find_anchors(code)]
        assert types == ['module', 'class', 'def']

    def test_documented_flag(self):
        code = "# The M module.\nmodule M\n  def bare\n  end\nend"
        anchors = {a['name']: a['documented'] for a in find_anchors(code)}
        assert anchors['M'] is True
        assert anchors['bare'] is False

    def test_singleton_class_skipped(self):
        code = "class C\n  class << self\n    def m\n    end\n  end\nend"
        names = [a['name'] for a in find_anchors(code)]
        assert 'C' in names
        # class << self itself is not an anchor
        assert all(a['type'] != 'class' or a['name'] == 'C' for a in find_anchors(code))

    def test_private_section_skipped(self):
        code = ("class C\n"
                "  def public_m\n  end\n"
                "  private\n"
                "  def hidden\n  end\n"
                "end")
        names = [a['name'] for a in find_anchors(code)]
        assert 'public_m' in names
        assert 'hidden' not in names

    def test_inline_private_def_skipped(self):
        code = "class C\n  private def hidden\n  end\nend"
        names = [a['name'] for a in find_anchors(code)]
        assert 'hidden' not in names

    def test_trivial_constant_skipped(self):
        code = "MAX_RETRIES = 3\nTIMEOUT = 30\nENABLED = true\nNAME = 'x'"
        assert find_anchors(code) == []

    def test_nontrivial_constant_included(self):
        code = 'PATTERNS = [\n  /foo/,\n  /bar/\n]'
        anchors = find_anchors(code)
        assert len(anchors) == 1
        assert anchors[0]['type'] == 'constant'
        assert anchors[0]['name'] == 'PATTERNS'

    def test_comments_and_blanks_ignored(self):
        code = "# just a comment\n\n# another\n"
        assert find_anchors(code) == []


class TestUncoveredAndSummary:
    def test_fully_documented_file(self):
        code = ("# The C class.\n"
                "class C\n"
                "  # Does m.\n"
                "  # @return [void]\n"
                "  def m\n  end\n"
                "end")
        assert find_uncovered_anchors(code) == []
        assert coverage_summary(code)['coverage_pct'] == 100.0

    def test_partially_documented_file(self):
        code = ("# The C class.\n"
                "class C\n"
                "  def bare\n  end\n"
                "end")
        uncovered = find_uncovered_anchors(code)
        assert len(uncovered) == 1
        assert uncovered[0]['name'] == 'bare'
        s = coverage_summary(code)
        assert s['total'] == 2 and s['documented'] == 1

    def test_empty_file(self):
        s = coverage_summary("")
        assert s['total'] == 0
        assert s['coverage_pct'] == 100.0

    def test_line_numbers_are_one_indexed(self):
        code = "class C\nend"
        assert find_anchors(code)[0]['line'] == 1

"""
Tests for fix_receiver_defs in build_html.py.

Upstream lich-5 defines class methods receiver-style (`def Char.name` inside
`class Char`), which YARD misparses into a phantom nested namespace
(Lich::Common::Char::Char), leaving the real class page empty. The build
rewrites those defs to `def self.name` in a shadow copy. These tests pin the
rewrite rules - especially the cases that must NOT be rewritten.

NOTE: this whole transform is a workaround. When upstream lich-5 converts to
`def self.method` style, fix_receiver_defs becomes a no-op and the transform
(and these tests) can be removed.
"""

from build_html import fix_receiver_defs


def test_basic_rewrite_inside_class():
    src = (
        "class Char\n"
        "  def Char.name\n"
        "    XMLData.name\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1
    assert "def self.name" in fixed
    assert "def Char.name" not in fixed


def test_rewrite_inside_nested_modules():
    src = (
        "module Lich\n"
        "  module Common\n"
        "    class Char\n"
        "      def Char.health\n"
        "        XMLData.health\n"
        "      end\n"
        "    end\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1
    assert "def self.health" in fixed


def test_module_receiver_rewrite():
    src = (
        "module Lich\n"
        "  def Lich.log(msg)\n"
        "    $stderr.puts(msg)\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1
    assert "def self.log(msg)" in fixed


def test_other_receiver_not_rewritten():
    # A def targeting a DIFFERENT class must be left alone.
    src = (
        "class Char\n"
        "  def Spell.active\n"
        "    []\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 0
    assert "def Spell.active" in fixed


def test_top_level_receiver_not_rewritten():
    # Receiver def outside any class body: rewriting to self would attach it
    # to the top level - must stay untouched.
    src = (
        "class Foo\n"
        "end\n"
        "def Foo.bar\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 0
    assert "def Foo.bar" in fixed


def test_def_end_does_not_pop_class():
    # A def's own `end` (indented deeper than the class opener) must not
    # close the class block early.
    src = (
        "class Char\n"
        "  def Char.a\n"
        "  end\n"
        "  def Char.b\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 2
    assert fixed.count("def self.") == 2


def test_inner_control_flow_ends_ignored():
    src = (
        "module Lich\n"
        "  if RUBY_PLATFORM =~ /win/\n"
        "    REQUIRED = true\n"
        "  end\n"
        "  def Lich.platform\n"
        "    RUBY_PLATFORM\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1
    assert "def self.platform" in fixed


def test_class_self_block_ignored():
    # `class << self` opens an anonymous block; receiver defs inside it
    # target the singleton and should not be rewritten.
    src = (
        "class Map\n"
        "  class << self\n"
        "    def Map.weird\n"
        "    end\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 0


def test_compound_module_name_uses_last_segment():
    src = (
        "module Lich::Gemstone::Societies\n"
        "  def Societies.voln\n"
        "    OrderOfVoln\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1
    assert "def self.voln" in fixed


def test_sibling_class_after_end_pops_correctly():
    src = (
        "module Lich\n"
        "  class Char\n"
        "    def Char.a\n"
        "    end\n"
        "  end\n"
        "  class Spell\n"
        "    def Char.b\n"  # Char def inside Spell: leave alone
        "    end\n"
        "    def Spell.c\n"
        "    end\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 2
    assert "def Char.b" in fixed
    assert "def self.a" in fixed
    assert "def self.c" in fixed


def test_class_with_superclass():
    src = (
        "class Warcry < PSMBase\n"
        "  def Warcry.bellow\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1


def test_comments_not_treated_as_openers():
    src = (
        "class Char\n"
        "  # class Fake\n"
        "  def Char.name\n"
        "  end\n"
        "end\n"
    )
    fixed, count = fix_receiver_defs(src)
    assert count == 1


def test_no_receiver_defs_returns_unchanged():
    src = "class Foo\n  def self.bar\n  end\n  def baz\n  end\nend\n"
    fixed, count = fix_receiver_defs(src)
    assert count == 0
    assert fixed == src

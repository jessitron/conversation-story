# frozen_string_literal: true

require "minitest/autorun"
require "conversation_story/markdown"

# ConversationStory::Markdown is a minimal, safe subset renderer — these lock
# in the shapes actually seen in the example logs (bold, inline code, loose
# lists, fenced code) and the safety property that raw HTML never survives.
class MarkdownTest < Minitest::Test
  Markdown = ConversationStory::Markdown

  def test_bold_and_inline_code
    html = Markdown.to_html("**no** the `just dev` command")
    assert_includes html, "<strong>no</strong>"
    assert_includes html, "<code>just dev</code>"
  end

  def test_raw_html_is_escaped_not_rendered
    html = Markdown.to_html("<script>alert(1)</script> and <b>bold</b>")
    refute_includes html, "<script>"
    refute_includes html, "<b>bold</b>"
    assert_includes html, "&lt;script&gt;"
  end

  def test_tight_bullet_list_becomes_one_ul
    html = Markdown.to_html("- one\n- two\n- three")
    assert_equal 1, html.scan("<ul>").size
    assert_equal 3, html.scan("<li>").size
  end

  # Claude's numbered lists are often "loose" (a blank line between items);
  # naive blank-line block-splitting would give each item its own <ol>,
  # restarting the numbering at 1 every time.
  def test_loose_numbered_list_stays_one_ol
    html = Markdown.to_html("1. first thing\n\n2. second thing")
    assert_equal 1, html.scan("<ol>").size
    assert_equal 2, html.scan("<li>").size
  end

  def test_fenced_code_block_is_preformatted_and_not_bold_processed
    html = Markdown.to_html("before\n\n```\n**not bold** in code\n```\n\nafter")
    assert_includes html, "<pre class=\"code\">"
    refute_includes html, "<strong>"
    assert_includes html, "**not bold** in code"
  end

  def test_blank_or_nil_text_renders_empty
    assert_equal "", Markdown.to_html(nil)
    assert_equal "", Markdown.to_html("   \n  ")
  end
end

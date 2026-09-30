# frozen_string_literal: true

require "asciidoctor"
require "asciidoctor/extensions"

# Asciidoctor extensions copied from roc-ray docs/theme/manual_extensions.rb (literal code spans only), loaded with `-r` by
# render.sh for both the HTML and the PDF build.

# ---------------------------------------------------------------------------
# Inline code is code: no typographic replacements inside it.
#
# Asciidoctor's `replacements` substitution runs after `quotes`, so by the time
# it sees a paragraph, `` `render! : Model => Try(...)` `` is already
# `<code>render! : Model =&gt; ...</code>` and the `=>`, `->`, `...`, `--` and
# apostrophe rules rewrite Roc into arrows, ellipses and curly quotes. A reader
# who copies that code gets something the compiler rejects.
#
# Both converters emit a monospace span as `<code ...>...</code>` at that point
# (the HTML one and asciidoctor-pdf's internal markup), so this applies the
# replacements to the text between code spans only. Prose keeps its dashes and
# curly quotes. render.sh fails the build if a replaced character
# ever reaches a code span again.
module RocLiteralCodeSpans
  CODE_SPAN_RX = %r{(<code\b[^>]*>.*?</code>)}m

  def sub_replacements(text)
    return super unless text.include? "<code"

    # With a capture group, split alternates prose (even) and code (odd).
    text.split(CODE_SPAN_RX, -1).each_with_index.map do |part, index|
      index.odd? ? part : super(part)
    end.join
  end
end
Asciidoctor::Substitutors.prepend RocLiteralCodeSpans

#!/usr/bin/env bash
# Render the report to PDF and produce its archive.
# Usage: ./render.sh <report-id>            draft: rule violations are printed, not fatal
#        FINAL=1 ./render.sh <report-id>    final: the review's exit criteria must pass
# Output: out/roc-cve-review-<id>.pdf and out/roc-cve-review-<id>.tar.gz
set -euo pipefail

edition="${1:?usage: ./render.sh <report-id>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
image="roc-cve-review:local"
name="roc-cve-review-${edition}"
out="$here/out"

python3 "$here/tools/review.py" generate
if [[ "${FINAL:-0}" == 1 ]]; then
  python3 "$here/tools/review.py" check --final
else
  python3 "$here/tools/review.py" check || echo "(draft render: rule violations above are not fatal)"
fi

docker build --quiet -t "$image" "$here" >/dev/null
rm -rf "$out" && mkdir -p "$out"

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$here:/report" "$image" \
  asciidoctor-pdf --failure-level WARN \
    -r asciidoctor-diagram \
    -r ./theme/rouge_roc.rb \
    -r ./theme/literal_code_spans.rb \
    -a docs-version="$edition" \
    -a source-highlighter=rouge -a rouge-style=rocray \
    -a pdf-themesdir=theme -a pdf-theme=roc \
    -a "pdf-fontsdir=theme/fonts;GEM_FONTS_DIR" \
    -a toclevels=2 \
    -a mermaid-format=png -a mermaid-scale=2 -a mermaid-background=FAFAF7 \
    -a mermaid-config=theme/mermaid-config.json \
    -a mermaid-puppeteer-config=theme/mermaid-puppeteer.json \
    -a diagram-cachedir=out/.diagram-cache -a imagesoutdir=out/images \
    -o "out/${name}.pdf" index.adoc

# The archive holds every source file, the PDF and a SHA-256 manifest.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/$name"
(cd "$here" && tar --exclude=./out -cf - .) | tar -xf - -C "$stage/$name"
cp "$out/${name}.pdf" "$stage/$name/"
(cd "$stage/$name" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS)
tar -czf "$out/${name}.tar.gz" -C "$stage" "$name"
echo "PDF:     $out/${name}.pdf"
echo "Archive: $out/${name}.tar.gz"

# Same pinned Asciidoctor base image as roc-automation actions/build-docs, with
# Chromium and mermaid-cli for diagrams (asciidoctor-diagram renders Mermaid to PNG for the PDF).
FROM asciidoctor/docker-asciidoctor:1.100.0@sha256:93ea06944afbc8e7a74ea31348b5f0624f1dfc69fa038ead3e7c4838faaa27d7

RUN apk add --no-cache chromium nodejs npm fontconfig \
    && npm install --global @mermaid-js/mermaid-cli@11.16.0 \
    && npm cache clean --force

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Mermaid measures labels in Chromium; give it the theme's faces so boxes fit the text.
COPY theme/fonts /usr/share/fonts/roc
RUN fc-cache -f

WORKDIR /report

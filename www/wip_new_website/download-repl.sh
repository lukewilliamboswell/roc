#!/usr/bin/env bash

REPL_DIST="dist/wip/"

mkdir -p $REPL_DIST

# Download the latest pre-built Web REPL as a zip file. (Build takes longer than Netlify's timeout.)
REPL_TARFILE="roc_repl_wasm.tar.gz"
curl -fLJO https://github.com/roc-lang/roc/releases/download/nightly/$REPL_TARFILE
tar -xzf $REPL_TARFILE -C $REPL_DIST
rm $REPL_TARFILE
ls -lh $REPL_DIST
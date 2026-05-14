# Introduction

End-to-end smoke test for `rules_mdbook`. If `bazel build
//examples/smoke:site` produces a non-empty tarball that contains an
`index.html`, the chain works:

1. `@mdbook//:mdbook` resolved from the host platform's prebuilt release.
2. The `mdbook_book` rule staged `book.toml` + `src/` + the plugin
   binaries into a sandbox.
3. `mdbook build` rendered the Markdown into HTML.
4. The action packaged `book/html/` as a `.tar.gz`.

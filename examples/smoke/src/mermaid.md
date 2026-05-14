# Mermaid

Exercises the `@mdbook_mermaid` plugin path. If the rendered HTML
includes a `mermaid` script tag for this code block, the plugin was
correctly staged on PATH and found by mdbook.

```mermaid
graph LR
  A[Bazel] -->|repository rule| B[@mdbook]
  A -->|repository rule| C[@mdbook_mermaid]
  B & C --> D[mdbook_book rule]
  D --> E[site.tar.gz]
```

# rules_mdbook

Bazel rules for [mdbook](https://rust-lang.github.io/mdBook/). Fetches the
prebuilt mdbook binary (plus mdbook-mermaid) and orchestrates a hermetic
`mdbook build` from a Bazel-managed sandbox.

- **module extension**: `mdbook` — auto-creates `@mdbook` + `@mdbook_mermaid` external repos. See [docs/extensions.md](docs/extensions.md).
- **rule**: `mdbook_book` — runs mdbook over a staged source tree, packages the rendered HTML as a `.tar.gz`. See [docs/defs.md](docs/defs.md).

## Install

Add the registry to your `.bazelrc`:

```
common --registry=https://raw.githubusercontent.com/mattmarshall/bazel-registry/main/
common --registry=https://bcr.bazel.build/
```

In your `MODULE.bazel`:

```python
bazel_dep(name = "rules_mdbook", version = "0.1.0")

mdbook = use_extension("@rules_mdbook//mdbook:extensions.bzl", "mdbook")
use_repo(mdbook, "mdbook", "mdbook_mermaid")
```

Override versions if needed:

```python
mdbook.toolchain(
    mdbook_version  = "0.5.2",
    mermaid_version = "0.17.0",
)
```

## Quick start

Standard mdbook layout in your repo:

```
docs/
├── BUILD.bazel
├── book.toml
└── src/
    ├── SUMMARY.md
    ├── intro.md
    └── ...
```

In `docs/BUILD.bazel`:

```python
load("@rules_mdbook//mdbook:defs.bzl", "mdbook_book")

mdbook_book(
    name      = "site",
    book_toml = "book.toml",
    srcs      = glob(["src/**/*.md"]),
    plugins   = ["@mdbook_mermaid//:mdbook-mermaid"],
    out       = "site.tar.gz",
)
```

`bazel build //docs:site` produces `bazel-bin/docs/site.tar.gz` containing
the rendered HTML.

## How it works

`mdbook_book`:

1. Stages `book.toml` + every src file into a sandbox dir at their
   package-relative paths (minus `src_strip_prefix`).
2. Copies the mdbook binary and each plugin into the sandbox's `bin/`
   under their bare filenames (so mdbook can resolve plugins by name on
   `PATH`).
3. Runs `mdbook build` from the sandbox root.
4. Tars `book/html/` (or `book/`, whichever the mdbook backend wrote)
   into the declared `out`.

The `MdbookSiteInfo` provider also returned by the rule wraps the
tarball file — downstream rules (a `mdbook_serve` wrapper, a deploy
target, link-check gates) can consume sites programmatically without
re-running mdbook.

### Hermeticity

| Layer            | Pinned by                                                       |
| ---------------- | --------------------------------------------------------------- |
| mdbook binary    | `sha256` in [`mdbook/private/known_versions.bzl`](mdbook/private/known_versions.bzl) per `(version, platform)` |
| mermaid plugin   | same table                                                      |
| Source tree      | Bazel's normal file-tracking (srcs label_list)                  |

Unpinned versions download unverified (warning emitted). Add an entry
to `known_versions.bzl` to lock a new version — compute with
`curl -fsSL <url> | shasum -a 256`.

## Scope and non-goals

This module intentionally stays small. It provides the **generally
reusable** piece — fetching mdbook + plugins + running `mdbook build`
hermetically. Project-specific bits stay in your repo:

- Custom mdbook preprocessors (RFC autolinking, frontmatter stripping, …)
  — keep them as your own `cc_binary` / `rust_binary` / `sh_binary` and
  pass them via the `plugins` attr.
- Source-tree staging that reorganizes a non-standard layout into what
  `book.toml` expects — keep as a project-local script invoked before
  `mdbook_book`.
- Linkcheck — pass `mdbook-linkcheck` (or `mdbook-linkcheck2`) via
  `plugins` like any other plugin.

## Compatibility

- **Bazel**: 7.4+, bzlmod required.
- **mdbook**: 0.5.2 pinned by default. Bump via `known_versions.bzl`.
- **Platforms**: `darwin_aarch64`, `darwin_x86_64`, `linux_x86_64`,
  `windows_x86_64` (per upstream release coverage).

## Contributing

Reference docs (`docs/defs.md`, `docs/extensions.md`) are stardoc-generated
from the `.bzl` docstrings and committed to source. After editing a rule
docstring:

```sh
bazel run //docs:update
```

CI gates this via `bazel test //docs/...` (diff_test against the
committed output) and the smoke build in `examples/smoke/`.

## License

MIT.

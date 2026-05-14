"""User-facing Bazel rules for rules_mdbook.

Exports `mdbook_book`, which runs `mdbook build` over a staged source
tree and packages the rendered HTML into a tarball. Optional plugin
executables (e.g. mdbook-mermaid) are staged onto PATH so mdbook can
resolve them by their bare names.

Targets returning `MdbookSiteInfo` expose the site tarball
programmatically so future rules (a deploy step, a link checker, a
`mdbook serve` wrapper) can consume the output without re-running
mdbook.
"""

MdbookSiteInfo = provider(
    doc = "A rendered mdbook site.",
    fields = {
        "tarball": "File: the gzipped tar of the rendered HTML tree.",
    },
)

def _mdbook_book_impl(ctx):
    out = ctx.outputs.out
    book_toml = ctx.file.book_toml
    mdbook = ctx.file.mdbook

    # Stage each src file into a scratch tree, preserving the relative
    # path beneath `src_strip_prefix`. The book.toml's `src = "..."` config
    # decides which subdir mdbook reads; the rule trusts that the user's
    # layout already matches book.toml.
    strip = ctx.attr.src_strip_prefix
    if strip and not strip.endswith("/"):
        strip += "/"

    rel_srcs = []
    for f in ctx.files.srcs:
        # Compute a path relative to the package + strip_prefix.
        p = f.short_path

        # Drop the bazel-out/.../bin/ prefix if present (generated files);
        # use path instead. Source files come through short_path cleanly.
        rel = p
        if strip and rel.startswith(ctx.label.package + "/" + strip):
            rel = rel[len(ctx.label.package) + 1 + len(strip):]
        elif rel.startswith(ctx.label.package + "/"):
            rel = rel[len(ctx.label.package) + 1:]
        rel_srcs.append((f, rel))

    plugin_lines = []
    plugin_inputs = []
    for plugin_file in ctx.files.plugins:
        plugin_inputs.append(plugin_file)

        # mdbook invokes plugins by their bare name (e.g. `mdbook-mermaid`),
        # so the staged copy must match the binary's filename.
        plugin_lines.append(
            'cp "{src}" "$STAGE/bin/{basename}"'.format(
                src = plugin_file.path,
                basename = plugin_file.basename,
            ),
        )

    cmd = """\
set -euo pipefail
OUT_ABS="$PWD/{out}"
mkdir -p "$(dirname "$OUT_ABS")"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/bin"
""".format(out = out.path) + "\n".join(plugin_lines) + """

# Stage book.toml at the root of the staging tree.
cp "{book_toml}" "$STAGE/book.toml"

""".format(book_toml = book_toml.path) + "\n".join([
        'mkdir -p "$STAGE/$(dirname "{rel}")"\ncp "{src}" "$STAGE/{rel}"'.format(
            src = f.path,
            rel = rel,
        )
        for f, rel in rel_srcs
    ]) + """

cp "{mdbook}" "$STAGE/bin/mdbook"
chmod +x "$STAGE/bin/"* 2>/dev/null || true
export PATH="$STAGE/bin:$PATH"
cd "$STAGE"
mdbook build >/dev/null

# Detect the rendered HTML output directory. mdbook writes to book/ by
# default, or book/html if [output.html] (the default backend) was
# configured with site-root etc. Prefer book/html if present.
if [ -d "$STAGE/book/html" ]; then
  OUT_DIR="$STAGE/book/html"
elif [ -d "$STAGE/book" ]; then
  OUT_DIR="$STAGE/book"
else
  echo "rules_mdbook: mdbook produced no book/ or book/html output" >&2
  exit 1
fi
tar -czf "$OUT_ABS" -C "$OUT_DIR" .
""".format(
        mdbook = mdbook.path,
    )

    ctx.actions.run_shell(
        outputs = [out],
        inputs = depset(
            direct = [book_toml, mdbook] + ctx.files.srcs + plugin_inputs,
        ),
        command = cmd,
        mnemonic = "MdbookBuild",
        progress_message = "mdbook build %s" % ctx.label.name,
    )

    return [
        DefaultInfo(files = depset([out])),
        MdbookSiteInfo(tarball = out),
    ]

mdbook_book = rule(
    implementation = _mdbook_book_impl,
    attrs = {
        "book_toml": attr.label(
            allow_single_file = [".toml"],
            mandatory = True,
            doc = "The mdbook configuration file. Staged at the root of the build sandbox.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "All source files (Markdown, SUMMARY.md, theme assets, etc.). " +
                  "Each file is staged at its package-relative path minus `src_strip_prefix`.",
        ),
        "src_strip_prefix": attr.string(
            default = "",
            doc = "Prefix to strip from each src's package-relative path before " +
                  "staging. Empty means files land at their package-relative paths.",
        ),
        "plugins": attr.label_list(
            allow_files = True,
            cfg = "exec",
            doc = "mdbook plugin executables (e.g. `@mdbook_mermaid//:mdbook-mermaid`). " +
                  "Staged onto PATH so mdbook can resolve them by bare name.",
        ),
        "mdbook": attr.label(
            default = "@mdbook//:mdbook",
            allow_single_file = True,
            cfg = "exec",
            doc = "The mdbook binary. Defaults to `@mdbook//:mdbook` from the module extension.",
        ),
        "out": attr.output(
            mandatory = True,
            doc = "The rendered site, packaged as a `.tar.gz`.",
        ),
    },
    doc = "Run `mdbook build` over a staged source tree and produce an HTML tarball.",
)

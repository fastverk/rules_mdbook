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
    mdbook = ctx.toolchains["@rules_mdbook//mdbook:toolchain_type"].mdbookinfo.mdbook

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
        "out": attr.output(
            mandatory = True,
            doc = "The rendered site, packaged as a `.tar.gz`.",
        ),
    },
    toolchains = ["@rules_mdbook//mdbook:toolchain_type"],
    doc = "Run `mdbook build` over a staged source tree and produce an HTML tarball.",
)

def _mdbook_serve_impl(ctx):
    mdbook = ctx.toolchains["@rules_mdbook//mdbook:toolchain_type"].mdbookinfo.mdbook

    # plugins are addressed via short_path so they resolve under the runner's
    # runfiles tree at execution time.
    plugin_copies = "\n".join([
        ('plugin_sp="{sp}"; ' +
         'if [[ "$plugin_sp" == "../"* ]]; then plugin_abs="${{RUNFILES_DIR}}/${{plugin_sp#../}}"; ' +
         'else plugin_abs="${{RUNFILES_DIR}}/${{WS_NAME}}/${{plugin_sp}}"; fi; ' +
         'cp "$plugin_abs" "$STAGE/bin/{basename}"').format(
            sp = p.short_path,
            basename = p.basename,
        )
        for p in ctx.files.plugins
    ])

    package_path = ctx.label.package or "."

    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = runner,
        is_executable = True,
        content = """\
#!/usr/bin/env bash
# Generated by mdbook_serve.
#
# Stages mdbook + plugins onto PATH, then invokes `mdbook serve` from the
# *live* user source directory under BUILD_WORKSPACE_DIRECTORY so its
# watch-mode picks up real-time edits. Bazel only orchestrates the
# toolchain; the source tree is not staged through Bazel sandboxing.
set -euo pipefail

if [[ -z "${{BUILD_WORKSPACE_DIRECTORY:-}}" ]]; then
  echo "error: mdbook_serve must be invoked via 'bazel run'" >&2
  exit 1
fi

if [[ -z "${{RUNFILES_DIR:-}}" ]]; then
  if [[ -d "$0.runfiles" ]]; then
    RUNFILES_DIR="$0.runfiles"
  fi
fi

WS_NAME="{ws_name}"
mdbook_sp="{mdbook_sp}"
if [[ "$mdbook_sp" == "../"* ]]; then
  MDBOOK_BIN="${{RUNFILES_DIR}}/${{mdbook_sp#../}}"
else
  MDBOOK_BIN="${{RUNFILES_DIR}}/${{WS_NAME}}/${{mdbook_sp}}"
fi
if [[ ! -f "$MDBOOK_BIN" ]]; then
  echo "ERROR: cannot find mdbook binary at $MDBOOK_BIN" >&2
  exit 2
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/bin"
cp "$MDBOOK_BIN" "$STAGE/bin/mdbook"
{plugin_copies}
chmod +x "$STAGE/bin/"* 2>/dev/null || true
export PATH="$STAGE/bin:$PATH"

cd "$BUILD_WORKSPACE_DIRECTORY/{package_path}"
exec mdbook serve "$@"
""".format(
            ws_name = ctx.workspace_name,
            mdbook_sp = mdbook.short_path,
            plugin_copies = plugin_copies if ctx.files.plugins else "# (no plugins)",
            package_path = package_path,
        ),
    )

    runfiles = ctx.runfiles(files = [mdbook] + ctx.files.plugins)
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

mdbook_serve = rule(
    implementation = _mdbook_serve_impl,
    executable = True,
    attrs = {
        "plugins": attr.label_list(
            allow_files = True,
            cfg = "exec",
            doc = "mdbook plugin executables, staged onto PATH so mdbook resolves " +
                  "them by bare name. Match the plugins listed in your book.toml.",
        ),
    },
    toolchains = ["@rules_mdbook//mdbook:toolchain_type"],
    doc = "Run `mdbook serve` (with watch + live reload) against the live user " +
          "source tree under `$BUILD_WORKSPACE_DIRECTORY/<package>`. Invoke via " +
          "`bazel run //path/to:target`. The target's package directory must " +
          "contain the `book.toml`; mdbook's own watch picks up edits without " +
          "Bazel re-running.",
)

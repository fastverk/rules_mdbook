"""Toolchain rule for rules_mdbook.

`mdbook_toolchain` wraps a single mdbook binary as a Bazel toolchain.
Consumers (the `mdbook_book` and `mdbook_serve` rules) resolve mdbook
through `@rules_mdbook//mdbook:toolchain_type`, so users can register
custom mdbook binaries (locally-built fork, alternate version, …) via
`register_toolchains(...)` without modifying rule attributes.

The module extension at `@rules_mdbook//mdbook:extensions.bzl` generates
a default toolchain (`@mdbook//:mdbook_toolchain_def`) wrapping the
prebuilt binary. Users register it from their `MODULE.bazel`:

    register_toolchains("@mdbook//:mdbook_toolchain_def")
"""

MdbookToolchainInfo = provider(
    doc = "The mdbook binary, resolved via a toolchain.",
    fields = {
        "mdbook": "File: the mdbook executable.",
    },
)

def _mdbook_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        mdbookinfo = MdbookToolchainInfo(
            mdbook = ctx.file.mdbook,
        ),
    )]

mdbook_toolchain = rule(
    implementation = _mdbook_toolchain_impl,
    attrs = {
        "mdbook": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "Path to the mdbook executable.",
        ),
    },
    doc = "Declare an mdbook binary as a Bazel toolchain.",
)

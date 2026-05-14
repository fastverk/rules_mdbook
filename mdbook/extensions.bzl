"""Module extension for rules_mdbook.

Auto-fetches prebuilt mdbook + mdbook-mermaid binaries for the host
platform. Versions are pinned by sha256 in
`private/known_versions.bzl`. Consumers can override the version per
tool via the `toolchain` tag class.

Default usage (pulls the default-pinned mdbook + mdbook-mermaid):

    mdbook = use_extension("@rules_mdbook//mdbook:extensions.bzl", "mdbook")
    use_repo(mdbook, "mdbook", "mdbook_mermaid")

Pin a specific version:

    mdbook = use_extension("@rules_mdbook//mdbook:extensions.bzl", "mdbook")
    mdbook.toolchain(mdbook_version = "0.5.2", mermaid_version = "0.17.0")
    use_repo(mdbook, "mdbook", "mdbook_mermaid")
"""

load(
    "//mdbook/private:known_versions.bzl",
    "DEFAULT_VERSIONS",
    "KNOWN_VERSIONS",
    "URL_TEMPLATES",
)

def _resolve_platform(rctx):
    os = rctx.os.name.lower()
    arch = rctx.os.arch.lower()
    if "linux" in os and arch in ("x86_64", "amd64"):
        return "x86_64-unknown-linux-gnu", "tar.gz"
    if ("mac" in os or "darwin" in os) and arch in ("aarch64", "arm64"):
        return "aarch64-apple-darwin", "tar.gz"
    if ("mac" in os or "darwin" in os) and arch in ("x86_64", "amd64"):
        return "x86_64-apple-darwin", "tar.gz"
    if "windows" in os and arch in ("x86_64", "amd64"):
        return "x86_64-pc-windows-msvc", "zip"
    fail("rules_mdbook: unsupported platform os=%s arch=%s" % (os, arch))

def _binary_repo_impl(rctx, *, name, version, platform, ext, sha256):
    url = URL_TEMPLATES[name].format(version = version, platform = platform, ext = ext)
    if not sha256:
        # buildifier: disable=print
        print(("rules_mdbook: WARNING — no pinned sha256 for {n}@{v} on {p}; " +
               "downloading unverified. Add an entry to known_versions.bzl " +
               "for hermetic builds.").format(n = name, v = version, p = platform))
    rctx.download_and_extract(
        url = url,
        sha256 = sha256 or "",
        stripPrefix = "",
    )
    binary_name = name + (".exe" if ext == "zip" else "")

    # Only the @mdbook repo gets a toolchain declaration — plugins are
    # consumed by mdbook_book as plain executables, not via toolchains.
    toolchain_block = ""
    if name == "mdbook":
        toolchain_block = """\

load("@rules_mdbook//mdbook:toolchains.bzl", "mdbook_toolchain")

mdbook_toolchain(
    name = "mdbook_toolchain",
    mdbook = ":{name}",
)

toolchain(
    name = "mdbook_toolchain_def",
    toolchain = ":mdbook_toolchain",
    toolchain_type = "@rules_mdbook//mdbook:toolchain_type",
)
""".format(name = binary_name)

    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files(["{name}"])
{toolchain}""".format(name = binary_name, toolchain = toolchain_block))

def _make_binary_repo_rule(tool_name):
    """Build a repository rule that downloads `tool_name`."""

    def impl(rctx):
        platform, ext = _resolve_platform(rctx)
        version = rctx.attr.version
        sha256 = KNOWN_VERSIONS.get(tool_name, {}).get(version, {}).get(platform, "")
        _binary_repo_impl(
            rctx,
            name = tool_name,
            version = version,
            platform = platform,
            ext = ext,
            sha256 = sha256,
        )

    return repository_rule(
        implementation = impl,
        attrs = {
            "version": attr.string(
                mandatory = True,
                doc = "Upstream release version (e.g. \"0.5.2\").",
            ),
        },
        doc = "Fetch a prebuilt {tool} binary for the host platform.".format(tool = tool_name),
    )

_mdbook_repository = _make_binary_repo_rule("mdbook")
_mdbook_mermaid_repository = _make_binary_repo_rule("mdbook-mermaid")

def _mdbook_extension_impl(mctx):
    # Reduce all toolchain tags across the dep graph to one (mdbook_version,
    # mermaid_version) pair. Root module wins; otherwise the latest seen.
    mdbook_version = DEFAULT_VERSIONS["mdbook"]
    mermaid_version = DEFAULT_VERSIONS["mdbook-mermaid"]
    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            if tag.mdbook_version:
                mdbook_version = tag.mdbook_version
            if tag.mermaid_version:
                mermaid_version = tag.mermaid_version

    _mdbook_repository(name = "mdbook", version = mdbook_version)
    _mdbook_mermaid_repository(name = "mdbook_mermaid", version = mermaid_version)

_toolchain_tag = tag_class(attrs = {
    "mdbook_version": attr.string(
        default = "",
        doc = "Override mdbook version. Defaults to the value in known_versions.bzl.",
    ),
    "mermaid_version": attr.string(
        default = "",
        doc = "Override mdbook-mermaid version. Defaults to the value in known_versions.bzl.",
    ),
})

mdbook = module_extension(
    implementation = _mdbook_extension_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    doc = "Sets up @mdbook and @mdbook_mermaid as Bazel-fetched prebuilt binaries.",
)

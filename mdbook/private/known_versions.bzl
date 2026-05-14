"""SHA-256 pins for prebuilt mdbook + plugin binaries.

Bumping a version requires adding an entry here. Compute with:

    curl -fsSL <url> | shasum -a 256

Unpinned versions fall back to unverified downloads (warning emitted).
"""

# Map: tool name -> version -> platform -> sha256.
KNOWN_VERSIONS = {
    "mdbook": {
        "0.5.2": {
            "aarch64-apple-darwin": "da2f55653e96e3f6e1c53e2e13e91cc0cfbce8ab971c2e0de792c0f1f8d24222",
            "x86_64-apple-darwin": "17cc64478ec279a73881420e850bd8f9d460552e56b50159ff465bc97eb90d6c",
            "x86_64-unknown-linux-gnu": "084e4342ba564db270108763e404a7d1f309d932651a22484e93c0dc1a071f6d",
            "x86_64-pc-windows-msvc": "e78fa1159bfc381d03f9c6659c48c883706497dc63c9153007a8a4c8df8da166",
        },
    },
    "mdbook-mermaid": {
        "0.17.0": {
            "aarch64-apple-darwin": "6e4a6bb7423a03d68c2f5869bfe7d3eab339304452129779a9d9abe4c510034f",
            "x86_64-apple-darwin": "88c6bee0226a8947837344c96ae7f86b4ad3447f91049b2c877772a2732ac752",
            "x86_64-unknown-linux-gnu": "8aced70d781830fb0e81988f081c4abdd49e056a001ae2f1e4d484e1f6385c57",
            "x86_64-pc-windows-msvc": "6ff34f3c008ca6905d49ec9eedd1a25b2d0d17e2affe95e959196756daf96886",
        },
    },
}

# Upstream URL templates per tool.
URL_TEMPLATES = {
    "mdbook": "https://github.com/rust-lang/mdBook/releases/download/v{version}/mdbook-v{version}-{platform}.{ext}",
    "mdbook-mermaid": "https://github.com/badboy/mdbook-mermaid/releases/download/v{version}/mdbook-mermaid-v{version}-{platform}.{ext}",
}

DEFAULT_VERSIONS = {
    "mdbook": "0.5.2",
    "mdbook-mermaid": "0.17.0",
}

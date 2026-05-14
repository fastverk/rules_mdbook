#!/usr/bin/env bash
# Regenerate docs/defs.md and docs/extensions.md from stardoc output.
# Run after changing rule docstrings. Invoked via `bazel run //docs:update`.
set -euo pipefail

if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  echo "error: must be invoked via 'bazel run //docs:update'" >&2
  exit 1
fi

RUNFILES_DIR="${RUNFILES_DIR:-$0.runfiles}"
DEFS_GEN="$(find "$RUNFILES_DIR" -name defs.md.generated -print -quit)"
EXT_GEN="$(find "$RUNFILES_DIR" -name extensions.md.generated -print -quit)"

cp "$DEFS_GEN" "$BUILD_WORKSPACE_DIRECTORY/docs/defs.md"
cp "$EXT_GEN"  "$BUILD_WORKSPACE_DIRECTORY/docs/extensions.md"

echo "docs/defs.md and docs/extensions.md regenerated."

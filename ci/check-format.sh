#!/usr/bin/env bash
# Checks formatting of the new C++ libraries (kmipcore, kmipclient).
# Legacy code (libkmip, kmippp) is intentionally exempt.
# Requires clang-format 18.1.8 on PATH (CI installs it via pipx; locally:
# pip install clang-format==18.1.8).
set -euo pipefail
cd "$(dirname "$0")/.."

ver="$(clang-format --version)"
echo "$ver"
if [[ "$ver" != *"version 18.1.8"* ]]; then
  echo "error: clang-format 18.1.8 required (pipx install clang-format==18.1.8); found: $ver" >&2
  exit 1
fi

if find kmipcore kmipclient \( -name '*.hpp' -o -name '*.cpp' \) -print0 \
  | xargs -0r clang-format --dry-run --Werror; then
  echo "formatting OK"
else
  echo "To fix: find kmipcore kmipclient \\( -name '*.hpp' -o -name '*.cpp' \\) -print0 | xargs -0 clang-format -i" >&2
  exit 1
fi

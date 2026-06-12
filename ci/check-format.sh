#!/usr/bin/env bash
# Checks formatting of the new C++ libraries (kmipcore, kmipclient).
# Legacy code (libkmip, kmippp) is intentionally exempt.
# Requires clang-format 18.1.8 on PATH (CI installs it via pipx).
set -euo pipefail
cd "$(dirname "$0")/.."

clang-format --version
find kmipcore kmipclient \( -name '*.hpp' -o -name '*.cpp' \) -print0 \
  | xargs -0 clang-format --dry-run --Werror

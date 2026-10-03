#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
test_build=$(mktemp -d /tmp/macoblox-tests.XXXXXX)
trap 'rm -rf -- "$test_build"' EXIT
clang -O2 -Wall -Wextra -pthread tests/runtime_helpers_test.c worker_wake.c -o "$test_build/runtime"
"$test_build/runtime"
clang -O2 -Wall -Wextra tests/shader_compat_test.c shader_compat.c -o "$test_build/shader"
"$test_build/shader"
clang -O2 -Wall -Wextra tests/telemetry_hosts_test.c -o "$test_build/telemetry"
"$test_build/telemetry"
clang -O2 -Wall -Wextra tests/connectx_compat_test.c -o "$test_build/connectx"
"$test_build/connectx"
PYTHONPATH=launcher python3 -m unittest discover -s tests -p '*_test.py'

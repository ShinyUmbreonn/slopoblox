#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# Output goes to MACOBLOX_BUILD_DIR when the sources are read-only (a package).
build_dir=${MACOBLOX_BUILD_DIR:-$project_dir/build}
# Packages put Darling's macOS root in /usr/libexec, a source build in /usr/local.
sysroot=${DARLING_SYSROOT:-/usr/libexec/darling}
[[ -d $sysroot || -n ${DARLING_SYSROOT:-} || ! -d /usr/local/libexec/darling ]] || sysroot=/usr/local/libexec/darling
mkdir -p "$build_dir"
tmp_output=$(mktemp "$build_dir/.shim.XXXXXX")
trap 'rm -f -- "$tmp_output"' EXIT
# Memory/string functions replacing Darling's unoptimized ones: -O2 and no
# builtins, compiled on their own (see fast_libc.c).
clang -target x86_64-apple-darwin -isysroot "$sysroot" -mmacosx-version-min=11.0 \
  -O2 -fno-builtin -c "$project_dir/fast_libc.c" -o "$build_dir/fast_libc.o"
# Newer clang compiles Objective-C literals (@1, @[], @{}) to constant objects
# of classes Darling's runtime does not have; -fno-objc-constant-literals turns
# that off. Older clang (22 and before) has neither the feature nor the flag
# and stops with "unknown argument", so it is passed only where it exists.
objc_literal_flag=
if clang -target x86_64-apple-darwin -fno-objc-constant-literals -x objective-c -fsyntax-only /dev/null 2>/dev/null; then
  objc_literal_flag=-fno-objc-constant-literals
fi
clang -target x86_64-apple-darwin -fuse-ld=lld \
  -isysroot "$sysroot" -mmacosx-version-min=11.0 \
  -O2 -g -fno-omit-frame-pointer -dynamiclib -fno-objc-arc $objc_literal_flag -Werror=incompatible-function-pointer-types \
  -Wl,-undefined,dynamic_lookup \
  -install_name @rpath/libMacOBloxShims.dylib \
  "$project_dir/libMacOBloxShims.m" "$project_dir/xattr_compat.c" "$project_dir/exit_compat.c" "$project_dir/missing_symbols.c" "$project_dir/net_trace.c" "$project_dir/darling_fixes.c" "$project_dir/thread_kick.c" "$project_dir/xfixes_raw.c" "$project_dir/raw_mouse.c" "$project_dir/cursor_overlay.c" "$project_dir/worker_wake.c" "$project_dir/shader_compat.c" "$project_dir/dns_override.c" "$project_dir/audio_hal.c" "$project_dir/gpu_info.c" "$project_dir/gl_profile.c" "$project_dir/connectx_compat.c" "$project_dir/memory_stats.c" "$project_dir/web_bridge.m" "$build_dir/fast_libc.o" \
  -lobjc -lc++ -lc++abi -framework Foundation -framework AppKit -framework WebKit -framework Metal \
  -o "$tmp_output"
mv -- "$tmp_output" "$build_dir/libMacOBloxShims.dylib"
printf 'Built: %s\n' "$build_dir/libMacOBloxShims.dylib"

# Frameworks RobloxPlayer links that Darling does not have (see frameworks/).
# The launcher copies them into the Darling prefix.
for name in CoreML CoreHaptics DeviceCheck; do
  framework="$build_dir/frameworks/$name.framework"
  mkdir -p "$framework/Versions/A"
  clang -target x86_64-apple-darwin -fuse-ld=lld \
    -isysroot "$sysroot" -mmacosx-version-min=11.0 \
    -dynamiclib -fno-objc-arc \
    -install_name "/System/Library/Frameworks/$name.framework/Versions/A/$name" \
    "$project_dir/frameworks/$name.m" -lobjc -framework CoreFoundation \
    -o "$framework/Versions/A/$name"
  ln -sfn A "$framework/Versions/Current"
  ln -sfn "Versions/Current/$name" "$framework/$name"
done
printf 'Built: %s\n' "$build_dir/frameworks"

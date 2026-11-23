#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
cd "$ROOT"

TARGETS=(aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
rustup target add "${TARGETS[@]}"
for target in "${TARGETS[@]}"; do
  cargo build --release --target "$target"
done

mkdir -p "$OUT"
lipo -create \
  "$ROOT/target/aarch64-apple-darwin/release/libnear_but_far_session.a" \
  "$ROOT/target/x86_64-apple-darwin/release/libnear_but_far_session.a" \
  -output "$OUT/libnear-but-far-macos.a"
lipo -create \
  "$ROOT/target/aarch64-apple-ios-sim/release/libnear_but_far_session.a" \
  "$ROOT/target/x86_64-apple-ios/release/libnear_but_far_session.a" \
  -output "$OUT/libnear-but-far-ios-simulator.a"

rm -rf "$OUT/NearButFarSession.xcframework"
xcodebuild -create-xcframework \
  -library "$OUT/libnear-but-far-macos.a" -headers "$ROOT/include" \
  -library "$ROOT/target/aarch64-apple-ios/release/libnear_but_far_session.a" -headers "$ROOT/include" \
  -library "$OUT/libnear-but-far-ios-simulator.a" -headers "$ROOT/include" \
  -output "$OUT/NearButFarSession.xcframework"

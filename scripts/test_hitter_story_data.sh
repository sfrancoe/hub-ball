#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/hub-hitter-test.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
cp "$ROOT/scripts/test_hitter_story_data.swift" "$TEST_DIR/main.swift"
swiftc "$ROOT/ios/Hub Ball/Hub Ball/MLB300HitterData.swift" "$ROOT/ios/Hub Ball/Hub Ball/StoryAudioLoop.swift" "$TEST_DIR/main.swift" -o "$TEST_DIR/test"
"$TEST_DIR/test"

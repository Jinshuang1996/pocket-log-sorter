#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
TEST_BINARY=$(mktemp /tmp/pocket-log-sorter-tests.XXXXXX)
trap 'rm -f "$TEST_BINARY"' EXIT

xcrun swiftc \
  "$SCRIPT_DIR/DjiMetadataReader.swift" \
  "$SCRIPT_DIR/DjiMetadataReaderTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

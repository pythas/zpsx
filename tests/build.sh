#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: ./build_test.sh <test_name>"
    echo "Example: ./build_test.sh delay_read"
    exit 1
fi

TEST_NAME=$(basename "$1" .s)

SRC_FILE="${TEST_NAME}.s"
OBJ_FILE="${TEST_NAME}.o"
ELF_FILE="${TEST_NAME}.elf"
BIN_FILE="${TEST_NAME}.bin"

if [ ! -f "$SRC_FILE" ]; then
    echo "Error: Source file '$SRC_FILE' not found!"
    exit 1
fi

echo "Building ${TEST_NAME}..."

echo "  -> Assembling..."
clang --target=mipsel-none-elf -march=mips1 -c "$SRC_FILE" -o "$OBJ_FILE"

echo "  -> Linking (Base address: 0xBFC00000)..."
ld.lld -m elf32ltsmip -Ttext 0xBFC00000 "$OBJ_FILE" -o "$ELF_FILE"

echo "  -> Extracting raw binary..."
llvm-objcopy -O binary "$ELF_FILE" "$BIN_FILE"

echo "  -> Padding to 512KB..."
dd if=/dev/zero of="$BIN_FILE" bs=1 seek=524288 count=0 status=none

echo "  -> Cleaning up..."
rm "$OBJ_FILE" "$ELF_FILE"

echo "Success! Created 512KB ROM: $BIN_FILE"

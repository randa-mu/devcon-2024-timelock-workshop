#!/bin/bash

# Usage:
# ./anvil-skip-to-block 5

# Check if target block number is passed as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 TARGET_BLOCK_NUMBER"
  exit 1
fi

# Assign the command line input to TARGET_BLOCK_NUMBER
TARGET_BLOCK_NUMBER=$1

# Get the current block number
current_block=$(cast block-number)

# Calculate the number of blocks to skip
blocks_to_skip=$((TARGET_BLOCK_NUMBER - current_block))

# Ensure blocks_to_skip is positive
if [ "$blocks_to_skip" -le 0 ]; then
  echo "Current block ($current_block) is already at or beyond target block ($TARGET_BLOCK_NUMBER)."
  exit 1
fi

# Mine blocks to reach the target
for _ in $(seq 1 $blocks_to_skip); do
  cast rpc anvil_mine
done

echo "Reached target block number: $TARGET_BLOCK_NUMBER"

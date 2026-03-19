#!/usr/bin/env bash
set -e

echo "[NoIdle] Installing..."

chmod +x noidle.sh

sudo cp noidle.sh /usr/local/bin/noidle

echo "[NoIdle] Installed successfully!"
echo "Run: noidle --help"

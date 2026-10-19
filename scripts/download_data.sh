#!/bin/bash
# 단어 빈도 목록을 받는다: https://github.com/hermitdave/FrequencyWords (OpenSubtitles 2018)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/raw
for lang in ko en; do
  curl -sfL -o "data/raw/${lang}_50k.txt" \
    "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/$lang/${lang}_50k.txt"
done
echo "✓ data/raw"

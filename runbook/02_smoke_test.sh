#!/usr/bin/env bash
# Phase C — 스모크 테스트 (학습 전 필수)
# 공개 radar_distill.pth 로 val 평가 -> 데이터+환경 정상 여부 확정
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
BATCH_SIZE="${BATCH_SIZE:-16}"
CKPT="${CKPT:-$REPO_ROOT/ckpt/radar_distill.pth}"
URL="https://github.com/geonhobang/RadarDistill/releases/download/v0.0.1/radar_distill.pth"

cd "$REPO_ROOT"
mkdir -p ckpt
if [ ! -f "$CKPT" ]; then
  echo "==> 공개 체크포인트 다운로드"
  wget -O "$CKPT" "$URL"
fi

cd tools
echo "==> val 평가 (batch=$BATCH_SIZE)"
python test.py \
  --cfg_file cfgs/radar_distill/radar_distill_val.yaml \
  --batch_size "$BATCH_SIZE" \
  --ckpt "$CKPT"

echo "==> 기대값: mAP ≈ 20.5 / NDS ≈ 43.7 (근접하면 데이터·환경 정상 -> 학습 진행)"

#!/usr/bin/env bash
# Phase D — 평가
#   기본: 자가 학습한 checkpoint_epoch_40.pth 평가
#   EVAL_ALL=1: 모든 epoch 스윕 (best epoch 확인용)
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
BATCH_SIZE="${BATCH_SIZE:-16}"
EXTRA_TAG="${EXTRA_TAG:-repro}"
EPOCH="${EPOCH:-40}"
EVAL_ALL="${EVAL_ALL:-0}"
CKPT_DIR="$REPO_ROOT/output/radar_distill/radar_distill_train/$EXTRA_TAG/ckpt"

cd "$REPO_ROOT/tools"

if [ "$EVAL_ALL" = "1" ]; then
  echo "==> 전체 epoch 평가 (ckpt_dir=$CKPT_DIR)"
  python test.py \
    --cfg_file cfgs/radar_distill/radar_distill_val.yaml \
    --batch_size "$BATCH_SIZE" \
    --eval_all \
    --ckpt_dir "$CKPT_DIR"
else
  CKPT="$CKPT_DIR/checkpoint_epoch_${EPOCH}.pth"
  echo "==> epoch ${EPOCH} 평가: $CKPT"
  python test.py \
    --cfg_file cfgs/radar_distill/radar_distill_val.yaml \
    --batch_size "$BATCH_SIZE" \
    --ckpt "$CKPT"
fi

echo "==> 목표: mAP 20.5 / NDS 43.7 (±0.5 mAP 이내면 재현 성공)"

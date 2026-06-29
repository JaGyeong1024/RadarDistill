#!/usr/bin/env bash
# Phase D — 전체 학습 (단일 A100 80GB, effective batch 16)
# spot/interruptible 대응: 자동 재개 + 시간 기반 중간 저장 내장
#
# 사용:
#   tmux new -s train
#   bash runbook/03_train.sh
# OOM 시:
#   BATCH_SIZE=8 LR=0.0005 bash runbook/03_train.sh
# spot에서 프로세스가 죽어도 같은 pod 안이면 자동 재시도:
#   AUTO_RESTART=1 bash runbook/03_train.sh
#   (pod 자체가 reclaim되면 새 pod에서 같은 명령 재실행 -> 최신 ckpt에서 자동 재개)
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
BATCH_SIZE="${BATCH_SIZE:-16}"
LR="${LR:-}"                                  # 비우면 config 기본(0.001) 사용
EPOCHS="${EPOCHS:-40}"
EXTRA_TAG="${EXTRA_TAG:-repro}"
CKPT_SAVE_INTERVAL="${CKPT_SAVE_INTERVAL:-1}" # epoch 단위 저장
MAX_CKPT="${MAX_CKPT:-40}"                     # 40 epoch 전부 보존 (eval_all 대비)
CKPT_TIME_INTERVAL="${CKPT_TIME_INTERVAL:-600}" # 초; spot kill 시 손실 <= 이 값
AUTO_RESTART="${AUTO_RESTART:-0}"

OUT="$REPO_ROOT/output/radar_distill/radar_distill_train/$EXTRA_TAG"
CKPT_DIR="$OUT/ckpt"

cd "$REPO_ROOT"

# ---- init 체크포인트 준비 (최초 1회) -------------------------------------
if [ ! -f ckpt/pillarnet_fullset_init.pth ]; then
  echo "==> init 체크포인트 생성"
  if [ ! -f ckpt/pillarnet_fullset_lidar.pth ]; then
    wget -O ckpt/pillarnet_fullset_lidar.pth \
      https://github.com/geonhobang/RadarDistill/releases/download/v0.0.1/pillarnet_fullset_lidar.pth
  fi
  python ckpt.py
fi

# ---- train args (재개 시 pretrained_model 자동 제외) ---------------------
build_args() {
  ARGS=(
    --cfg_file cfgs/radar_distill/radar_distill_train.yaml
    --batch_size "$BATCH_SIZE"
    --epochs "$EPOCHS"
    --extra_tag "$EXTRA_TAG"
    --ckpt_save_interval "$CKPT_SAVE_INTERVAL"
    --max_ckpt_save_num "$MAX_CKPT"
    --ckpt_save_time_interval "$CKPT_TIME_INTERVAL"
  )
  if compgen -G "$CKPT_DIR/*.pth" >/dev/null 2>&1; then
    echo "==> 기존 체크포인트 발견 -> 자동 재개 (pretrained_model 미적용)"
  else
    echo "==> 신규 학습 -> pretrained_model 적용"
    ARGS+=(--pretrained_model ../ckpt/pillarnet_fullset_init.pth)
  fi
  if [ -n "$LR" ]; then ARGS+=(--set OPTIMIZATION.LR "$LR"); fi
}

cd tools
run_once() { build_args; echo "python train.py ${ARGS[*]}"; python train.py "${ARGS[@]}"; }

if [ "$AUTO_RESTART" = "1" ]; then
  until run_once; do
    echo "==> train 비정상 종료. 15초 후 최신 ckpt에서 재개..."; sleep 15
  done
else
  run_once
fi

echo "==> 학습 종료. 체크포인트: $CKPT_DIR"

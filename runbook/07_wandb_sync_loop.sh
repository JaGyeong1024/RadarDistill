#!/usr/bin/env bash
# pod-side: wandb Option A (코드 0수정). train.py가 만든 tfevents를 주기적으로 wandb로 push.
# 사전: export WANDB_API_KEY=... ; export WANDB_PROJECT=radardistill
# 사용: nohup bash pod_wandb_sync_loop.sh </dev/null >/workspace/wandb_sync.log 2>&1 &
set -uo pipefail
REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
EXTRA_TAG="${EXTRA_TAG:-repro}"
WANDB_PROJECT="${WANDB_PROJECT:-radardistill}"
TB="$REPO_ROOT/output/radar_distill/radar_distill_train/$EXTRA_TAG/tensorboard"
INTERVAL="${WANDB_SYNC_INTERVAL:-1800}"   # 30분

echo "wandb sync loop start: TB=$TB project=$WANDB_PROJECT interval=${INTERVAL}s"
while true; do
  if [ -d "$TB" ]; then
    wandb sync --sync-tensorboard --project "$WANDB_PROJECT" "$TB" 2>&1 | tail -3 || echo "(sync 일시 실패 — 다음 주기 재시도)"
  else
    echo "$(date +%H:%M:%S) tfevents 아직 없음 (학습 시작 전)"
  fi
  sleep "$INTERVAL"
done

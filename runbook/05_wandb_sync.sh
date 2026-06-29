#!/usr/bin/env bash
# (선택) wandb 연동 — 옵션 A: 코드 수정 없이 TensorBoard 로그를 wandb로 동기화
# 사전: wandb login   (또는 WANDB_API_KEY 환경변수)
# 학습 중/후 아무 때나 실행하면 최신 tfevents를 업로드한다.
# (라이브 스트리밍을 원하면 README 의 '옵션 B 3줄 패치' 참고)
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
EXTRA_TAG="${EXTRA_TAG:-repro}"
WANDB_PROJECT="${WANDB_PROJECT:-radardistill}"
TB="$REPO_ROOT/output/radar_distill/radar_distill_train/$EXTRA_TAG/tensorboard"

[ -d "$TB" ] || { echo "ERROR: tensorboard 디렉토리 없음: $TB (학습 시작 후 실행)"; exit 1; }

echo "==> wandb 동기화: $TB -> project=$WANDB_PROJECT"
wandb sync --sync-tensorboard --project "$WANDB_PROJECT" "$TB"

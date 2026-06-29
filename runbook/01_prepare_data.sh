#!/usr/bin/env bash
# Phase B — 데이터 검증 + info/gt_database 생성
# 전제: data/nuscenes/ 아래에 nuScenes 원천 데이터를 이미 올려둔 상태
#   - 이미 info .pkl + gt_database 보유 시: SKIP_INFO=1 로 검증만 수행
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
NUSC_VERSION="${NUSC_VERSION:-v1.0-trainval}"
SKIP_INFO="${SKIP_INFO:-0}"
DATA="$REPO_ROOT/data/nuscenes"

cd "$REPO_ROOT"

echo "==> [1/3] 디렉토리 레이아웃 점검: $DATA/$NUSC_VERSION"
miss=0
for d in samples sweeps maps "$NUSC_VERSION"; do
  if [ -d "$DATA/$NUSC_VERSION/$d" ]; then
    echo "  OK   $NUSC_VERSION/$d"
  else
    echo "  MISS $NUSC_VERSION/$d"; miss=1
  fi
done
if [ "$miss" = "1" ]; then
  echo "ERROR: 데이터 레이아웃이 맞지 않음. 아래 구조로 배치 후 재실행:"
  echo "  $DATA/$NUSC_VERSION/{samples,sweeps,maps,$NUSC_VERSION}"
  exit 1
fi

if [ "$SKIP_INFO" != "1" ]; then
  echo "==> [2/3] info / gt_database 생성 (수십 분~1시간+, 디스크 +100GB)"
  python -m pcdet.datasets.nuscenes.nuscenes_dataset_distill \
    --func create_nuscenes_infos \
    --cfg_file tools/cfgs/dataset_configs/nuscenes_dataset_distill.yaml \
    --version "$NUSC_VERSION"
else
  echo "==> [2/3] SKIP_INFO=1 -> info 생성 건너뜀 (검증만)"
fi

echo "==> [3/3] 산출물 검증"
# 코드가 root_path = DATA_PATH/VERSION 으로 쓰므로 산출물은 data/nuscenes/<VERSION>/ 아래에 생김
OUT="$DATA/$NUSC_VERSION"
fail=0
for f in \
  nuscenes_infos_6radar_10sweeps_train.pkl \
  nuscenes_infos_6radar_10sweeps_val.pkl \
  nuscenes_dbinfos_10sweeps_with_radar_withvelo.pkl ; do
  if [ -f "$OUT/$f" ]; then echo "  OK   $f"; else echo "  MISS $f"; fail=1; fi
done
if [ -d "$OUT/gt_database_10sweeps_with_radar_withvelo" ]; then
  echo "  OK   gt_database_10sweeps_with_radar_withvelo/"
else
  echo "  MISS gt_database_10sweeps_with_radar_withvelo/"; fail=1
fi

[ "$fail" = "0" ] && echo "==> 데이터 준비 완료." || { echo "ERROR: 산출물 누락"; exit 1; }

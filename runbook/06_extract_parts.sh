#!/usr/bin/env bash
# pod-side: _parts/*.tar 를 data/nuscenes/v1.0-trainval/ 로 하나씩 풀고 즉시 삭제 (볼륨 용량 절약)
# nohup 로 띄우고 로그 폴링. tar 내부경로 = samples/.. sweeps/.. v1.0-trainval/.. maps/..
set -uo pipefail
DST=/workspace/RadarDistill/data/nuscenes/v1.0-trainval
PARTS=/workspace/RadarDistill/data/_parts
mkdir -p "$DST"
shopt -s nullglob
ok=0; fail=0
for p in "$PARTS"/part_*.tar; do
  if tar xf "$p" -C "$DST"; then rm -f "$p"; ok=$((ok+1)); echo "EXTRACTED $(basename "$p") (ok=$ok)"; else fail=$((fail+1)); echo "FAIL $(basename "$p")"; fi
done
echo "=== EXTRACT_DONE ok=$ok fail=$fail ==="
echo "--- v1.0-trainval 레이아웃 ---"
ls -la "$DST" 2>/dev/null
echo "--- 남은 parts(0이어야 정상) ---"
ls "$PARTS" 2>/dev/null | wc -l

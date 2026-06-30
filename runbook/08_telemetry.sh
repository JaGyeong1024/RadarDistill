#!/usr/bin/env bash
# pod-side 텔레메트리: GPU+시스템+디스크 상태를 30초마다 CSV로 영구 기록 (사후 분석용).
# 사용: nohup bash runbook/08_telemetry.sh </dev/null >/dev/null 2>&1 &
set -u
F="${TELEMETRY_CSV:-/workspace/telemetry.csv}"
INT="${TELEMETRY_INTERVAL:-30}"
if [ ! -f "$F" ]; then
  echo "utc_time,gpu_util_pct,gpu_mem_used_mib,gpu_mem_total_mib,gpu_temp_c,gpu_power_w,sys_mem_used_mb,sys_mem_total_mb,load1,workspace_disk_pct,train_running" > "$F"
fi
while true; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%S)
  g=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
  [ -z "$g" ] && g="NA,NA,NA,NA,NA"
  m=$(free -m 2>/dev/null | awk '/Mem:/{print $3","$2}'); [ -z "$m" ] && m="NA,NA"
  l=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null); [ -z "$l" ] && l="NA"
  d=$(df -h /workspace 2>/dev/null | tail -1 | awk '{print $5}'); [ -z "$d" ] && d="NA"
  tr=$(pgrep -f 'train.py' >/dev/null 2>&1 && echo 1 || echo 0)
  echo "$ts,$g,$m,$l,$d,$tr" >> "$F"
  sleep "$INT"
done

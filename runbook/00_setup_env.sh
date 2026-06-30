#!/usr/bin/env bash
# Phase A — 환경 구축 (RunPod pod 안에서 실행)
# 기반 이미지 가정: pytorch/pytorch:1.10.0-cuda11.3-cudnn8-devel
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/workspace/RadarDistill}"
INSTALL_WANDB="${INSTALL_WANDB:-1}"   # wandb 사용 안 하면 0

echo "==> [1/6] System packages"
# 베이스 이미지의 NVIDIA CUDA apt repo는 GPG 키 만료로 apt-get update를 깨뜨림(NO_PUBKEY).
# git/ffmpeg 등은 우분투 repo에서 받으므로 NVIDIA repo는 불필요 -> 제거(견고화).
rm -f /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/nvidia*.list 2>/dev/null || true
apt-get update
apt-get install -y ffmpeg libsm6 libxext6 git ninja-build \
  libglib2.0-0 libxrender-dev tmux rclone wget

cd "$REPO_ROOT"

echo "==> [2/6] Pinned numpy/numba 먼저 설치 (resolver 충돌 회피)"
pip install numpy==1.19.5 numba==0.48.0

echo "==> [3/6] spconv + torch-scatter (torch1.10+cu113 매칭)"
pip install spconv-cu113
pip install torch-scatter==2.1.1 -f https://data.pyg.org/whl/torch-1.10.0+cu113.html

echo "==> [4/6] requirements + nuscenes-devkit"
pip install -r requirements.txt
pip install nuscenes-devkit
if [ "$INSTALL_WANDB" = "1" ]; then
  pip install wandb
fi

echo "==> [5/6] pcdet 빌드"
python setup.py develop
if [ -f make.sh ]; then sh make.sh; fi

echo "==> [6/6] 검증"
python - <<'PY'
import torch
import spconv.pytorch  # noqa: F401
import pcdet           # noqa: F401
print("torch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("device:", torch.cuda.get_device_name(0))
    cap = torch.cuda.get_device_capability(0)
    print("compute capability:", cap)
    if cap[0] >= 9 or (cap[0] == 8 and cap[1] >= 9):
        print("WARNING: Ada/Hopper 계열 -> CUDA 11.3 커널 미지원 가능. A100(sm_80) 권장.")
PY
echo "==> 환경 구축 완료. 'CUDA available: True' 확인."

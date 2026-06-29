# RadarDistill 재현 런북 (RunPod / A100 80GB)

이 디렉토리의 스크립트는 클라우드 GPU 인스턴스(권장: RunPod A100 80GB ×1)에서
RadarDistill (CVPR 2024) 의 헤드라인 수치 **20.5 mAP / 43.7 NDS** 를 재현하기 위한 것이다.
전체 설계는 승인된 계획서(`~/.claude/plans/mutable-tinkering-crab.md`)를 따른다.

- CMA·AFD·PFD **3개를 한 번에 다 적용한 풀 모델만** 재현(ablation 미수행).
- 단일 A100 80GB에서 effective batch 16(= 논문의 4-GPU×4와 동등) 유지.
- nuScenes 데이터는 이미 보유 가정 → 인스턴스로 전송만.

## 사용 흐름

스크립트는 모두 `REPO_ROOT`(기본 `/workspace/RadarDistill`) 기준으로 동작한다.
변수는 환경변수로 덮어쓸 수 있다(예: `BATCH_SIZE=8 bash 03_train.sh`).

| 환경변수 | 기본값 | 의미 |
|---|---|---|
| `REPO_ROOT` | `/workspace/RadarDistill` | 레포 경로(=Network Volume) |
| `BATCH_SIZE` | `16` | 단일 GPU effective batch. OOM 시 8 |
| `LR` | (config 0.001) | LR 오버라이드. batch 8이면 0.0005 권장 |
| `EPOCHS` | `40` | 학습 epoch |
| `EXTRA_TAG` | `repro` | 출력 디렉토리 태그(실험 구분) |
| `CKPT_TIME_INTERVAL` | `600` | spot: epoch 도중 저장 주기(초) |
| `MAX_CKPT` | `40` | 보존할 체크포인트 수 |
| `AUTO_RESTART` | `0` | 1이면 학습 죽어도 같은 pod에서 자동 재개 |
| `SKIP_INFO` | `0` | 1이면 info 생성 건너뛰고 검증만 |
| `EVAL_ALL` | `0` | 1이면 전체 epoch 평가 스윕 |
| `INSTALL_WANDB` | `1` | 0이면 wandb 미설치 |
| `WANDB_PROJECT` | `radardistill` | wandb 프로젝트명 |

### 0. RunPod 수동 셋업 (콘솔에서, 스크립트 외)
1. A100 80GB 재고 있는 데이터센터에서 **Network Volume 600GB** 생성.
   - nuScenes는 카메라 블롭 제외(LiDAR+Radar만)로 받으면 실사용 ~250-300GB → 600GB면 충분.
   - ⚠️ 카메라 포함 전체(~350GB)를 통째로 받으면 빠듯해지니 LiDAR/Radar 블롭만 선택 다운로드.
2. Pod 생성: GPU = A100 80GB ×1, 위 볼륨을 `/workspace`에 마운트,
   컨테이너 이미지 = `pytorch/pytorch:1.10.0-cuda11.3-cudnn8-devel`.
   - ⚠️ RTX 4090/L40/H100 등 Ada/Hopper는 CUDA 11.3 커널 미지원 → 반드시 A100(Ampere).
3. 웹터미널/SSH 접속 후 레포 클론:
   ```bash
   cd /workspace && git clone https://github.com/geonhobang/RadarDistill.git
   ```
4. 이 `runbook/` 디렉토리를 pod의 `/workspace/RadarDistill/runbook/` 로 복사
   (scp 또는 git에 함께 두기).

### 1. 환경 구축 — `00_setup_env.sh`
```bash
cd /workspace/RadarDistill && bash runbook/00_setup_env.sh
```
끝에 `CUDA available: True` 가 떠야 정상.

### 2. 데이터 준비 — `01_prepare_data.sh`
```bash
# data/nuscenes/ 아래에 v1.0-trainval 데이터를 먼저 올려둔 뒤:
bash runbook/01_prepare_data.sh
```
- 이미 info .pkl + gt_database를 보유했다면 `SKIP_INFO=1 bash runbook/01_prepare_data.sh`
  로 검증만 수행.
- 데이터 전송 팁: 오브젝트 스토리지(S3/GCS/R2)에 올려두고 `rclone copy` 가 가장 빠름.

### 3. 스모크 테스트 — `02_smoke_test.sh` (학습 전 필수)
```bash
bash runbook/02_smoke_test.sh
```
공개 `radar_distill.pth` 로 val 평가 → **≈20.5 mAP / 43.7 NDS** 면 데이터·환경 정상.
여기서 어긋나면 학습으로 넘어가지 말고 데이터/전처리부터 디버그.

### 4. 전체 학습 — `03_train.sh`
```bash
tmux new -s train      # 세션 끊김 대비
bash runbook/03_train.sh
```
단일 A100 기준 epoch당 ~15-25분, 40 epoch ≈ 10-17시간.
OOM 나면 `BATCH_SIZE=8 LR=0.0005 bash runbook/03_train.sh`.

### 5. 평가 — `04_eval.sh`
```bash
bash runbook/04_eval.sh                 # epoch_40 평가
EVAL_ALL=1 bash runbook/04_eval.sh      # 전체 epoch 스윕
```
직접 학습한 epoch_40이 목표 수치(±0.5 mAP) 안이면 재현 성공.

## Spot / interruptible 인스턴스 (체크포인트 & 자동 재개)
RadarDistill(OpenPCDet)에는 spot용 기능이 이미 내장되어 `03_train.sh`가 그대로 spot-safe다.
- **자동 재개**: `--ckpt` 미지정 시 `ckpt_dir/*.pth` 중 최신을 찾아 재개(`accumulated_iter`·`start_epoch` 복원).
  `03_train.sh`는 기존 체크포인트가 있으면 `--pretrained_model`을 자동으로 빼서 순수 재개로 동작.
- **상태 저장**: 체크포인트에 `model_state`+`optimizer_state`(Adam 모멘텀)+`epoch`+`it`가 모두 들어가
  onecycle LR 스케줄이 끊김 없이 이어진다.
- **시간 기반 중간 저장**: `CKPT_TIME_INTERVAL`(기본 600초)마다 `latest_model.pth` 저장 →
  epoch 도중 killed돼도 손실이 그 시간 이내.
- **필수 전제**: `output/`(=ckpt)가 **Network Volume**에 있어야 pod reclaim 후에도 보존된다(기본 충족).

운영 방법:
- 같은 pod에서 프로세스만 죽는 경우: `AUTO_RESTART=1 bash runbook/03_train.sh` (until 루프로 재개).
- pod 자체가 reclaim된 경우: 같은 볼륨에 새 pod를 붙이고 `bash runbook/03_train.sh` 재실행 → 최신 ckpt에서 자동 재개.

**결과에 영향?** → 사실상 없음(무시 가능). 가중치·옵티마이저·iter·LR 스케줄이 모두 복원되므로
학습 궤적은 그대로 이어진다. 단, 데이터 셔플/augmentation의 RNG 상태까지 mid-epoch로 복원되진
않아 재개 후 증강 시퀀스가 미세하게 달라진다 → 체계적 편향이 아니라 **run-to-run 변동(±0.5 mAP)**
범위의 잡음. 비트 단위 동일 재현이 필요한 게 아니라 논문 수치 도달이 목적이면 spot으로 충분하다.
(spot 가격은 on-demand 대비 대략 절반 → 1회 재현 비용도 그만큼 절감.)

## wandb 연동 (선택)
기본 코드는 TensorBoard만 쓴다(wandb 내장 없음). 두 가지 방법:
- **옵션 A — 코드 수정 없음(권장, 재현 충실)**: 학습은 그대로 두고 `05_wandb_sync.sh`로 tfevents를 업로드.
  ```bash
  wandb login                       # 또는 export WANDB_API_KEY=...
  bash runbook/05_wandb_sync.sh     # 학습 중/후 아무 때나, 반복 실행 가능
  ```
- **옵션 B — 라이브 스트리밍(3줄 패치)**: `tools/train.py`에서 `tb_log = SummaryWriter(...)` 줄 **직후**에 추가:
  ```python
  if cfg.LOCAL_RANK == 0:
      import wandb, os
      wandb.init(project=os.environ.get("WANDB_PROJECT", "radardistill"),
                 name=args.extra_tag, sync_tensorboard=True)
  ```
  `sync_tensorboard=True`가 SummaryWriter scalar를 자동으로 wandb에 실시간 미러링한다.
  (학습 로직은 안 바꾸므로 수치 재현에는 영향 없음.)

## 비용/운영 메모
- 학습/평가 안 할 때 **pod stop** → GPU 과금 중단, Network Volume(데이터·ckpt)만 보존·소액 과금.
- 1회 재현 대략 $30-60 + 스토리지(600GB ~$30-45/월). 작업 끝나면 볼륨 삭제. spot이면 GPU분 절반 수준.

## 성공 판정
1. 00: `CUDA available: True`
2. 01: info .pkl 4종 + `gt_database_10sweeps_with_radar_withvelo/` 존재
3. 02: 공개 ckpt 평가 ≈20.5/43.7
4. 04: 자가 학습 epoch_40 평가 목표 수치 ±0.5 mAP 이내

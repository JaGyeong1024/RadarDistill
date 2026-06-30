# RadarDistill 재현 — 운영/핸드오프 문서

> 목적: RadarDistill(CVPR2024) **20.5 mAP / 43.7 NDS** 를 RunPod A100에서 재현.
> 이 문서는 어디서(로컬 노트북 / claude.ai/code 웹 / 폰)든 작업을 이어받기 위한 운영 가이드.
> 비밀키는 여기 적지 않음 — 위치만 표시. (작성/갱신: Claude, 진행 중)

---

## 0. 라이브 상태 (2026-06-30, 웹 인수인계 시점) ★먼저 읽기★
- **현재 pod: `ykzc2lfgb3w5gu` (RadarDistillPod-migration, A100 SXM 80GB, US-WA-1, RUNNING).** (옛 pod n48o1hc5ajmf7a 는 GPU 못잡아 EXITED 방치 → terminate 가능)
- SSH: `ssh ykzc2lfgb3w5gu-64411258@ssh.runpod.io -i ~/.ssh/id_ed25519` (프록시, §4 방식).
- 데이터 242GB(15 parts)는 볼륨 `/workspace/RadarDistill/data/_parts/*.tar` 에 있음. 환경 재구축 완료(`import pcdet` OK).
- **지금 pod tmux 세션 `full` 에서 전체 체인 실행 중** (`/workspace/run_full.sh`): `06_extract(--no-same-owner) → 01_prepare → 02_smoke → (07 wandb sync &) → 03_train → 04_eval`. 로그 `/workspace/full.log` (`tmux attach -t full`). 06 ownership 이슈 해결(ERRC=0). 결과분기 없음(robust run) — 스모크 수치는 Claude가 wandb/로그로 사후 확인.
- 로컬 모니터: `scratchpad/poll_full.sh` — smoke완료(train진입)/체인종료/tmux사망 시 알림. 수동점검 `cmd_step_check.sh`.
- **다음**: smoke 완료되면 mAP≈20.5/NDS≈43.7 확인(이상하면 학습 끊고 재시도) → 학습 ~10-17h → eval → 결과 보고 → **사용자/Claude가 RunPod앱/CLI로 pod 정지**.
- ⚠️ 웹(claude.ai/code) 인수인계 불가 = 웹 샌드박스가 RunPod egress 차단. **pod 제어는 로컬 CLI에서만.** 모니터링은 wandb(폰)+RunPod앱 가능.
- ⚠️ 네트워크FS(mfs) 소형파일 쓰기 느림 → 추출+gt_database 몇 시간(일회성).

---

## 1. 리소스 좌표

| 항목 | 값 |
|---|---|
| RunPod Pod 이름 | `RadarDistillPod` |
| **Pod ID** | `n48o1hc5ajmf7a` |
| GPU / 위치 | A100 SXM 80GB ×1 / **US-WA-1** (Secure cloud) |
| 컨테이너 이미지 | `pytorch/pytorch:1.10.0-cuda11.3-cudnn8-devel` |
| 컨테이너 start command | `sleep infinity` (없으면 컨테이너 즉시 종료) |
| **Network Volume** | 이름 `RadarDistill`, **ID `trh40ewpoq`**, 600GB, US-WA-1 → `/workspace` 마운트 |
| 레포 경로(pod 내) | `/workspace/RadarDistill` (REPO_ROOT) |

---

## 2. 비밀키 위치 (값은 파일 안에, 절대 커밋 금지)
- **`~/.config/radardistill/secrets.env`** (권한 600) — `source` 해서 사용:
  - `WANDB_API_KEY`, `WANDB_PROJECT=radardistill`, `WANDB_ENTITY`(빈값=계정 기본)
  - `RUNPOD_API_KEY` (rpa_…)
  - `RUNPOD_S3_ACCESS` (user_…), `RUNPOD_S3_SECRET`
- runpodctl 설정: **`~/.runpod.yaml`** (apiKey 들어있음)
- SSH 키: `~/.ssh/id_ed25519` (RunPod 계정에 공개키 등록됨)
- gitignore 처리됨: `.wandb_api.md`, `*.wandb_api*`, `.netrc`, `3skey.txt`, `runpod_api.txt`, `runpodctl.tar.gz`

> 웹(claude.ai/code) 등 새 환경에서 이어받을 땐 이 키들을 그 환경에 다시 넣어야 함(커밋 안 되어 있으므로).

---

## 3. Pod 제어 (runpodctl)
`runpodctl`은 로컬 `/usr/local/bin`에 설치됨. (deprecated 경고는 무시)
```bash
runpodctl get pod n48o1hc5ajmf7a      # 상태 확인 (RUNNING/EXITED)
runpodctl start pod n48o1hc5ajmf7a    # 켜기  (이후 컨테이너 뜨고 SSH까지 ~30-60s)
runpodctl stop  pod n48o1hc5ajmf7a    # 끄기  (과금 중단; /workspace 볼륨은 보존)
```
- ⚠️ **stop 시 container disk(설치 환경)는 호스트가 바뀌면 날아갈 수 있음.** start 직후 `python -c "import pcdet"` 로 환경 생존 확인. 날아갔으면 `bash runbook/00_setup_env.sh` 재실행(~15분).
- 폰/웹: RunPod 콘솔(console.runpod.io) 또는 RunPod 앱에서도 동일하게 start/stop/상태 확인 가능.

---

## 4. Pod 내부 명령 실행 (프록시 SSH)
프록시 SSH는 **scp/sftp 불가 + PTY 필수 + 인자 명령 무시(대화형 쉘만 줌)**. 그래서 명령을 파일에 적고 stdin으로 흘려넣음:
```bash
# 헬퍼: scratchpad/rpx.sh  (script로 PTY 감싸고 명령파일을 ssh stdin으로)
ssh -tt -o StrictHostKeyChecking=accept-new n48o1hc5ajmf7a-64411391@ssh.runpod.io \
    -i ~/.ssh/id_ed25519 < <명령파일>
# (접미사 64411391은 재시작 시 Connect 탭에서 재확인)
```
- 출력엔 pty echo/프롬프트가 섞이니 `===END===` 같은 마커 + ANSI strip으로 파싱.
- apt 명령엔 반드시 `</dev/null` (안 그러면 stdin 먹어 다음 명령 유실).
- 긴 작업은 pod에서 `nohup ... </dev/null > /workspace/X.log 2>&1 &` 로 띄우고 로그 폴링.

---

## 5. wandb 확인 방법
- 학습 시 메트릭이 wandb(클라우드)에 쌓임 → **로컬 없이 폰/웹에서 확인 가능**.
- 웹: https://wandb.ai → 프로젝트 **`radardistill`** (entity = secrets의 계정 기본).
- 폰: wandb 앱 로그인 → radardistill 프로젝트.
- 연동 방식(아직 미적용, 학습 직전 적용): **Option A 고정 — 코드 0수정**. train.py가 만드는 tfevents를 `wandb sync --sync-tensorboard --project radardistill <tensorboard_dir>` 로 push (`05_wandb_sync.sh`). 라이브는 pod에서 주기적 wandb-sync 루프(스캐폴딩)로. pod에선 `export WANDB_API_KEY=…`(secrets 값) 필요.
- ⚠️ **비침투 원칙**: 원본 실험 코드(`pcdet/`,`tools/`,`cfgs/`)는 수정 금지(재현 충실도). Option B(train.py 3줄 패치)는 **쓰지 않음**. 학습/평가 제어는 커맨드라인 인자만.

---

## 6. 데이터 업로드 (현재 진행 중)
- 로컬 원본: `/home/a/nuScenes` (풀셋 398GB). **카메라 제외 LiDAR+Radar만 242GB** 업로드.
- 방식: **boto3 병렬 chunked-tar → RunPod 볼륨 S3** (rclone 1.53은 PUT 버그로 못 씀).
  - 엔드포인트 `https://s3api-us-wa-1.runpod.io`, 버킷=볼륨ID `trh40ewpoq`.
  - 업로더: `scratchpad/par_uploader.py` (16GB청크×15, 6동시, 청크별 재개 `parts_done.txt`).
  - 청크는 `RadarDistill/data/_parts/part_NNN.tar` 로 적재.
  - 진행률: `scratchpad/par_status.txt` (청크 단위라 lag 있음) + 실시간은 `wlo1` tx_bytes로 측정(~12MB/s).
  - 재개: 끊기면 `source ~/.config/radardistill/secrets.env && nohup python3 scratchpad/par_uploader.py …` 재실행 → 완료 청크 건너뜀.
- ⚠️ **업로드는 로컬 프로세스** → 노트북 절전/네트워크 끊기면 멈춤. 업로드 동안은 노트북 켜둬야 함.

---

## 7. 업로드 후 데이터 배치 (중요 — 정적분석으로 확정)
코드가 `root_path = DATA_PATH(../data/nuscenes) / VERSION(v1.0-trainval)` 로 경로를 만듦.
→ 데이터는 반드시 **`/workspace/RadarDistill/data/nuscenes/v1.0-trainval/{samples,sweeps,maps,v1.0-trainval}`** 에 있어야 함.
- pod 켠 뒤, `_parts/*.tar` 를 **`data/nuscenes/v1.0-trainval/` 로 한 개씩 풀고 즉시 삭제**(볼륨 600GB, tar 242G+추출 242G 동시 회피):
```bash
mkdir -p /workspace/RadarDistill/data/nuscenes/v1.0-trainval
for p in /workspace/RadarDistill/data/_parts/part_*.tar; do
  tar xf "$p" -C /workspace/RadarDistill/data/nuscenes/v1.0-trainval/ && rm -f "$p"
done
```
(tar 내부 경로가 samples/…, sweeps/…, v1.0-trainval/…, maps/… 이므로 위 -C로 정확히 들어감)

---

## 8. 파이프라인 단계 + 재개 명령 (전부 idempotent/재개가능)
pod 안 `/workspace/RadarDistill` 에서, **tmux 세션** 권장.

| 단계 | 명령 | 재개성 |
|---|---|---|
| 데이터추출 | `bash runbook/01_prepare_data.sh` | info/gt_database 있으면 다시 만들지 않게(또는 SKIP_INFO=1로 검증만) |
| 스모크 | `bash runbook/02_smoke_test.sh` | 재실행 안전 (단 §9 수정 필요) |
| 학습 | `tmux new -s train; bash runbook/03_train.sh` | **최신 ckpt에서 자동 재개** (OpenPCDet 내장) |
| 평가 | `bash runbook/04_eval.sh` | 재실행 안전 (단 §9 수정 필요) |

설계 원칙(사용자 지침): **스크립트는 스스로 판단(중단/분기) 안 함. 견고+재개가능하게만. 문제 생기면 Claude가 보고 고쳐서 그 지점부터 재개.** 자동 타임아웃/self-stop 없음. 정지는 명시적으로만(완료 확인 후 또는 사용자가 RunPod 앱에서).

---

## 9. 정적분석 발견
1. **데이터 위치 (필수)**: §7 대로 `data/nuscenes/v1.0-trainval/` 아래. 코드가 `root_path = DATA_PATH/VERSION` (train=`NuScenesDataset_Distill`, val=`NuScenesDataset_radar_test`, 둘 다 동일). 추출 -C 경로를 그렇게.
2. **(수정완료 ✅) `01_prepare_data.sh` [3/3] 검증 경로 버그**: `data/nuscenes/*.pkl`를 보던 것 → 실제 산출물 위치 `data/nuscenes/v1.0-trainval/`(`OUT=$DATA/$NUSC_VERSION`)로 고침. (생성 자체는 원래 정상; 검증만 잘못이었음 → exit1 오류 제거). ⚠️ **pod의 runbook에도 이 수정본 반영 필요**(재전송 또는 pod에서 동일 수정).
3. **(오탐, 정상 ✅) 스모크/평가 config**: `radar_distill_val.yaml`이 base(`nuscenes_dataset_radar_test.yaml`, v1.0-test)를 **override** 함 → 실제로는 `VERSION: v1.0-trainval` + `INFO test: nuscenes_infos_6radar_10sweeps_val.pkl`(prep 산출물과 일치) + `DB_INFO: ..._with_radar_withvelo.pkl`. 클래스 `NuScenesDataset_radar_test` 존재·등록·경로처리 일치 확인. **문제 없음.**
4. **(확인됨, 문제없음)** gt_database = `create_groundtruth_database_w_radar`(`nuscenes_dataset.py`)가 `..._with_radar_withvelo` 생성 → config 일치. 릴리스 자산(`radar_distill.pth`,`pillarnet_fullset_lidar.pth`) HTTP 200. 환경 torch1.10/cu113, spconv2.3.6, import pcdet/spconv/torch_scatter OK.

→ **결론: 런북은 대체로 정상. 실행 전 필수 조치는 (1) 데이터를 v1.0-trainval/ 아래 배치, (2) 01 검증경로 수정본을 pod에 반영. 두 개뿐.**

---

## 10. 노트북 종속성 / 원격 이어가기
- **학습은 pod(클라우드)에서 도니 노트북 절전/출장과 무관하게 계속됨.** 영향받는 건 "Claude의 모니터링·pod제어"뿐(로컬 세션).
- **claude.ai/code(웹)** 에서 이어받기 가능: 이 repo를 열고, §2 키들을 그 환경에 넣고, 이 문서(§3~§9)대로 pod 제어/모니터링/재개. (웹도 대화형 세션이라 열어둔 동안 동작 — 학습 자체는 pod가 계속.)
- 가장 손 안 가는 모니터링: **wandb 앱(학습) + RunPod 앱(pod 상태/정지)**.

---

## 11. 메모리(로컬 전용, 참고)
`~/.claude/projects/-home-a-RadarDistill/memory/` 에 `runpod-repro-state.md`, `runpod-ops-procedure.md` 로 더 상세한 상태/지침 기록됨(로컬 Claude 세션용). 이 OPERATIONS.md 가 그 요약 + 핸드오프판.

---

## 12. 업로드 후 즉시 실행 순서 (준비됨)
runbook에 추가된 스캐폴딩: `06_extract_parts.sh`(parts→v1.0-trainval 추출), `07_wandb_sync_loop.sh`(wandb Option A 루프). 로컬 scratchpad엔 명령파일 준비됨(cmd_launch_prep.sh 등). 순서:
1. `runpodctl start pod n48o1hc5ajmf7a` → 켜지면 SSH로 `python -c "import pcdet"` (환경 생존 확인; 없으면 `bash runbook/00_setup_env.sh`).
2. **수정된 runbook 반영**: pod의 `/workspace/RadarDistill/runbook/` 을 수정본으로 덮어쓰기(01 검증경로 fix + 06/07 추가). (로컬 `runbook_v2.tgz` base64 전송 또는 git.)
3. **추출**: `nohup bash runbook/06_extract_parts.sh </dev/null >/workspace/extract.log 2>&1 &` → `data/nuscenes/v1.0-trainval/{samples,sweeps,maps,v1.0-trainval}` 생성. (⚠️ 네트워크FS에 1.45M 파일 쓰기라 느릴 수 있음 — 모니터)
4. **데이터 준비**: `nohup bash -c 'bash runbook/01_prepare_data.sh; echo PREP_EXIT=$?' </dev/null >/workspace/prep.log 2>&1 &` (~1.5-2.5h). 산출물: `v1.0-trainval/nuscenes_infos_6radar_10sweeps_{train,val}.pkl` + `nuscenes_dbinfos_10sweeps_with_radar_withvelo.pkl` + `gt_database_10sweeps_with_radar_withvelo/`.
5. **스모크**: `bash runbook/02_smoke_test.sh` → mAP≈20.5/NDS≈43.7 확인(공개 ckpt). Claude가 수치 보고 판단.
6. **wandb on**: `export WANDB_API_KEY=…; export WANDB_PROJECT=radardistill; nohup bash runbook/07_wandb_sync_loop.sh </dev/null >/workspace/wandb_sync.log 2>&1 &`
7. **학습**: `tmux new -s train; bash runbook/03_train.sh` (~10-17h, 자동재개 내장). OOM시 `BATCH_SIZE=8 LR=0.0005`.
8. **평가**: `bash runbook/04_eval.sh` → ±0.5 mAP 이내면 재현 성공.
9. **정지**: Claude(또는 RunPod앱)가 완료 확인 후 `runpodctl stop pod`.

## 13. 새 환경(웹/타 기기)에서 이어받기 — 부트스트랩 체크리스트
> 같은 노트북 새 세션이면 ↓ 다 이미 있으니 "OPERATIONS.md 읽고 이어가"만 하면 됨.
1. 이 repo(fork `JaGyeong1024/RadarDistill`) clone → OPERATIONS.md 읽기.
2. **비밀키 직접 입력**(pod/git엔 없음): `~/.config/radardistill/secrets.env` 재생성 — WANDB_API_KEY, WANDB_PROJECT=radardistill, RUNPOD_API_KEY, RUNPOD_S3_ACCESS/SECRET.
3. **SSH 개인키** `~/.ssh/id_ed25519` 그 환경에 넣기(RunPod 계정 등록된 키).
4. **runpodctl 설치** + `~/.runpod.yaml`(apiKey) 또는 `runpodctl config --apiKey`.
5. 이후 §3~§12 대로 pod 제어/모니터링/재개. pod의 `/workspace`에 코드·데이터·상태 다 있음.

---

## 14. 결정 로그 (왜 이렇게 진행하나)
1. **비침투 재현**: 원본 실험코드(`pcdet/`,`tools/`,`cfgs/`) 무수정. 수정은 우리 스캐폴딩(`runbook/`)에만. wandb=**Option A**(코드0수정 tfevents sync), Option B(train.py 패치) 안 씀.
2. **스크립트 자체판단 금지**: 결과(스모크 mAP 등)로 분기하지 않음. 단계는 `&&`로 "앞 단계 크래시 시 중단"만(의존성 정합). 수치 판단·복구는 **Claude가**.
3. **타임아웃·self-stop 자동화 없음**(사용자 지침). 정지는 명시적으로만(결과 확인 후 사용자/Claude가 RunPod앱/CLI).
4. **진행 방식**: "미리 문제 다 잡고 한 번에 쭉 결과까지 → 보고 이상하면 다시." → 전체 체인을 pod tmux에서 한 번에 실행, Claude 모니터, 끝나면 결과 보고.
5. **GPU 부족 대응**: 옛 pod(n48o1hc5ajmf7a) stop 후 호스트 A100 못잡음 → 사용자가 같은DC(US-WA-1)에 새 pod(ykzc2lfgb3w5gu) 마이그레이션 배포(같은 볼륨). (마이그레이션=새 pod 배포는 과금 가드레일이라 사용자 명시 승인 필요했음.) US-KS-2 이전은 볼륨 지역고정+재고없음으로 비채택.
6. **데이터 전송**: 로컬 nuScenes(LiDAR+Radar만, 카메라 제외 242GB) → **boto3 병렬 chunked-tar로 RunPod 볼륨 S3 업로드**(rclone1.53은 PUT 버그). 배치는 `data/nuscenes/v1.0-trainval/`(코드가 DATA_PATH/VERSION).
7. **비밀키 일원화**: `~/.config/radardistill/secrets.env`(권한600)에 WANDB/RUNPOD/S3 키. 중복 파일(.wandb_api.md, runpod_api.txt, 3skey.txt)·runpodctl.tar.gz 삭제 정리됨. pod/git엔 키 안 둠(wandb 키만 로깅용으로 pod env).
8. **정적분석 결과**: 크리티컬 패스 green. 수정=runbook 3곳(00 nvidia repo 제거, 01 검증경로, 06 --no-same-owner). 실험코드 무수정.

## 16. 로그 위치 (전부 /workspace = 영구 볼륨, pod stop에도 보존)
- **마스터 체인 로그**: `/workspace/full.log` — 06추출/01준비/02스모크/03학습(AUTO_RESTART 메시지 포함)/04평가 전부. (`tmux attach -t full` 로 실시간)
- **학습 상세 로그**: `/workspace/RadarDistill/output/radar_distill/radar_distill_train/repro/train_<timestamp>.log` (OpenPCDet, 재시작마다 새 파일 → 이력 보존) + 같은 폴더 `tensorboard/`(tfevents).
- **wandb sync 로그**: `/workspace/wandb_sync.log`. wandb 클라우드(project `radardistill`)에도 메트릭 적재.
- **평가 로그**: `output/.../eval/` 아래.
- ⚠️ full.log는 overwrite — 체인 **재시작 전엔 백업**(`cp full.log full.log.bak.$(date)`). 학습 상세는 timestamp별이라 자동 보존.

## 17. AUTO_RESTART (capped) — 03_train.sh
- `AUTO_RESTART=1` 시 학습 크래시하면 최신 ckpt에서 재개. **단 최대 `MAX_RESTART`(기본 3)회만**, 초과하면 `exit 1`로 **중단**(결정적 장애 무한루프 방지). 중단되면 full.log/output 로그 보고 사람이 판단.
- 일시 장애(CUDA/IO 글리치)=재개로 회복 / 결정적 장애(버그·항상 OOM)=3회 후 멈춤.

## 15. 진행 현황 (체크포인트)
- [x] pod 부트스트랩(apt/git/clone/runbook)  [x] 환경구축(00, torch1.10/cu113, import OK)
- [x] 데이터 업로드(242GB/15parts, S3검증)  [~] 추출→준비→스모크(tmux full 진행중)
- [ ] 학습(03)  [ ] 평가(04)  [ ] pod 정지+결과보고

# Project Status

> Persistent development memory. **Read this file first at the start of every session**, together with
> `README.md` and `docs/reference/MASTER_SPEC.md`, then resume from "Next Task" below.
> Do not restart the project or recreate completed work.

**Project:** Scan4Disease — AI-Assisted Dermatology Screening
**Student:** Rajrup Roy Chowdhury (23BAI10213), B.Tech AI, VIT Bhopal
**Last updated:** 2026-08-08

---

## Current Phase

**Phase 1 complete (repository audit + restructure). Phases 2–9 scaffolded in code; blocked on dataset download and dependency install.**

---

## Technical Assessment (Phase 1 deliverable)

### Existing System — what was actually here

The directory contained **no source code**. Inventory before restructure:

| Item | Type | Verdict |
|---|---|---|
| `START HERE - Simple Plan.md` | Planning doc | Keep — reference |
| `Scan4Disease - Project Plan & Roadmap.md` | Planning doc | Keep — reference |
| `Zero-Cost Setup.md` | Planning doc | Keep — reference |
| Form 1 / Form 2 (filled, .docx) | Admin paperwork | Keep — reference |
| 2 × prior-batch PDF reports | Prior MP online (21BSA) output | Keep — literature/template |
| `app-release.apk` (23 MB) | Inherited Flutter build, prior batch | Keep as artifact, **not** a codebase |
| `github links.txt` | Two third-party repo URLs | Repos **not cloned**; nothing local to reuse |

Both referenced repos have since been **cloned into `upstream/`** (git-ignored, reference only) and read.
Full findings: `docs/reference/upstream_audit.md`. Summary:

- `HarshSahu23/EPICS_Demo` @ `ddf8909` — Flutter client. **No local model anywhere.** It posts the image to
  `http://10.0.2.2:3000/analyze` and carries a hardcoded **RapidAPI key** for
  `detect-skin-disease.p.rapidapi.com`. The bundled `server/` is an Express+Mongo CRUD scaffold with
  **no `/analyze` route at all**. Reusable: project scaffold, `assets/*.png`, `theme.dart`, and the
  camera/gallery flow. Deletable: `DiagnoseAPI.dart`, `server/`, several `temp.dart` dead files.
- `qmh1234567/skin_disease_two_classification` @ `1cda14e` — third-party binary classifier. Its own README
  documents a **200-image dataset (128 train / 32 val / 40 test)**, not ISIC 2016's ~1,279. Code targets
  PyTorch ~0.3–0.4: `inputs.cuda(async=True)` is a **syntax error** on Python 3.7+, and it uses
  `torch.autograd.Variable`. Not portable; rewriting is cheaper.

So there is no existing backend, ML code, dataset, trained model, or test to reuse. The Flutter scaffold and
art assets are the only genuinely reusable inheritance.

### Problems / Risks

**Inherited-work problems (these define the contribution):**
1. **The project plan's description of the inherited system was inaccurate.** The prior app did not run its own
   model — it was a thin client over a **commercial RapidAPI service**. Corrected in the audit doc.
2. The referenced "~95% ResNet-50" figure comes from a **40-image balanced test set** in an unrelated
   third-party repo. One image is worth 2.5 percentage points there. It is also binary, so it cannot produce
   the 7-class output this project needs.
3. **Zero explainability** — the app returns a bare label.
4. **No evaluation rigour** — no per-class F1, no confusion matrix, no AUC, no external validation.
5. "AI dermatologist" naming is unearned: no reasoning, no triage, no conversation.
6. **Leaked secrets in the inherited public repos**: RapidAPI key in `DiagnoseAPI.dart`, MongoDB Atlas
   credentials in `server/config.env`. Must not be carried forward; flag to whoever owns those accounts.

**Environment problems found by inspection (2026-08-08):**
5. Default `python` on PATH is **3.14.6**. PyTorch publishes no wheels for 3.14 — training would fail at
   `pip install torch`. **Python 3.12** is installed at
   `C:\Users\RAJ\AppData\Local\Programs\Python\Python312\python.exe` and must be used for the venv.
6. GPU is an **RTX 5050 Laptop, 8 GB, driver 610.62** — Blackwell (`sm_120`). The default PyPI torch wheel
   (CUDA 12.4) has no `sm_120` kernels and will fail at runtime. Must install from the **cu128+ index**.
7. `flutter`, `dart`, `ollama` are **not installed**.
8. Only **68 GB free** on C:. HAM10000 (~2.6 GB) fits comfortably; ISIC 2019 (~25 GB) fits but is tight
   alongside checkpoints — plan storage before downloading ISIC.
9. No git repository existed (now initialised, no commits yet).

**Project risks:**
10. Class imbalance: NV is ~67% of HAM10000, DF ~1%. Bare accuracy will look fine while malignant recall is poor.
11. **Data leakage**: HAM10000 contains multiple images of the *same lesion* (`lesion_id`). A random split
    inflates test scores badly. Splitting must be grouped by `lesion_id`.
12. Domain gap: HAM10000 is dermoscopy; the app takes smartphone photos.
13. LLM hallucination in a medical context.

### Recommended Changes

**Required**
- Repository restructure per spec §31 (done).
- Python 3.12 venv + cu128 PyTorch (documented in `scripts/`, `docs/development.md`).
- 7-class mapping from HAM10000's actual `dx` labels, version-controlled in `ml/configs/class_mapping.json`.
- **Lesion-grouped, stratified** train/val/test split — no `lesion_id` may cross splits.
- Class-weighted loss; report macro-F1, balanced accuracy, per-class recall — never bare accuracy.
- Deterministic rule-based triage layer **before** the LLM; LLM explains, never decides urgency.
- App-level fixed dermatologist disclaimer, rendered by the app, not the LLM.

**Recommended**
- ResNet-50 vs EfficientNet-B0 comparison on the identical split (academic justification for deployment choice).
- Grad-CAM + manual heatmap inspection with documented failure cases.
- Confidence calibration (temperature scaling + ECE).
- Simple OpenCV image-quality gate (Laplacian variance + luminance) — not an ML model.
- Experiment log (CSV/JSON) with seed and full hyperparameters.

**Optional (only after core works)**
- ISIC 2019 scale-up / external validation; PAD-UFES-20 smartphone validation; Fitzpatrick17k fairness slice.
- ONNX export for CPU serving; offline TFLite mode; scan history; clinic map.

### Final Proposed Architecture

```
Flutter app ──HTTPS──> FastAPI backend
                          │
              ┌───────────┼────────────────┐
              ▼           ▼                ▼
      quality gate   preprocessing    questionnaire
              └───────────┤                │
                          ▼                │
                   CNN (EfficientNet-B0)   │
                     │      │      │       │
                  class  conf.  Grad-CAM   │
                     └──────┴──────┴───────┘
                                  ▼
                       DETERMINISTIC TRIAGE RULES   ← authoritative urgency
                                  ▼
                       LLM (Qwen3, local Ollama)    ← explanation + EN/HI only
                                  ▼
                    FIXED APP-LEVEL DISCLAIMER      ← hardcoded, always shown
```

### Implementation Plan

| Phase | Content | State |
|---|---|---|
| 1 | Repo audit + restructure + PROJECT_STATUS | **Done** |
| 2 | Dataset pipeline (mapping, validation, leakage-free split, transforms) | Code done + tested; needs data |
| 3 | ResNet-50 baseline training | Code done; **not run** (no data) |
| 4 | EfficientNet-B0 + model comparison | Code done; **not run** (no data) |
| 5 | Grad-CAM | **Done** — verified on real ISIC images, both architectures |
| 6 | FastAPI `/health` `/predict` | **Done** — verified with a real checkpoint |
| 7 | Questionnaire | **Done** |
| 8 | Deterministic triage layer | **Done** — 9 rules, 24 unit tests |
| 9 | LLM integration (Ollama/Qwen) | Code done; needs Ollama installed |
| 10 | Flutter app | Not started (correctly — it is Phase 10) |
| 11 | Full integration | Blocked on 3–4 |
| 12 | Final testing + documentation | Docs done; model report is a template awaiting real numbers |

---

## Completed

- Repository restructured into `app/ backend/ ml/ dotnet/ scripts/ docs/ assets/ tests/` (spec §31).
- Reference planning material kept under `docs/reference/`; superseded onboarding docs and legacy binaries removed during the GitHub cleanup pass.
- Git repository initialised on `main`; `.gitignore` covers datasets, weights, `.env`, Flutter and IDE noise.
- `PROJECT_STATUS.md`, root `README.md`, `.env.example` written.
- Both upstream repos cloned to `upstream/` (git-ignored) and audited → `docs/reference/upstream_audit.md`.
- `scripts/setup_env.ps1` (Python 3.12 venv + cu128 PyTorch) and `scripts/verify_env.py` (GPU kernel-launch
  check, not just `cuda.is_available()`) written. `docs/development.md` documents the full install order.
- ML pipeline: class mapping, training config, dataset validation, lesion-grouped split, dataset + transforms.
- Training/evaluation: shared utilities, transfer-learning trainer (freeze → fine-tune), evaluator with
  per-class metrics + confusion matrix, model comparison script, experiment log.
- Grad-CAM implemented from first principles (hooks, no external grad-cam dependency).
- FastAPI backend: config, schemas, routes, preprocessing, quality gate, inference, Grad-CAM service,
  deterministic triage, LLM service with guard-rails, temp-file janitor, error handling.
- **131 tests, all passing**, and `ruff check` clean:
  - `backend/tests/test_triage.py` — every rule plus the escalation-only / missing-is-not-no invariants
  - `backend/tests/test_safety.py` — output filter, disclaimers, confidence phrasing
  - `backend/tests/test_api.py` — all endpoints, every error path, path traversal, no internal leakage
  - `tests/test_parity.py` — `ml`↔`backend` agreement on preprocessing (bit-identical), model
    factory, Grad-CAM (numerically identical) and class mapping
  - `tests/test_ml_pipeline.py` — split leakage (both directions), class weighting, metrics
- Documentation: root `README.md`, `docs/{architecture,API,safety,dataset,gradcam,llm,development,model_report}.md`,
  plus `backend/README.md`, `ml/README.md`, `app/README.md`, `ml/datasets/README.md`.
- `LICENSE` (MIT + medical disclaimer + dataset licensing notice), `.github/workflows/ci.yml`,
  `scripts/run_backend.ps1`, `pyproject.toml` (pytest + ruff config).

### Bugs found and fixed during verification

1. **`setup_env.ps1` interpreter check was always failing.** `-notmatch` against a PowerShell
   *array* filters it rather than returning a boolean. Replaced with an actual launch attempt.
2. **A dark image was reported as "blurred".** A black frame has almost no gradient, so it
   trips the Laplacian check too — the user was told to steady the camera when the room was
   dark. Exposure is now checked first and suppresses the blur message.
3. **Pre-malignant probability mass made a confident `akiec` urgent**, contradicting rule R2.
   Malignant and pre-malignant mass are now tracked separately; pre-malignant can only reach
   PROMPT. *Found by a test, not by review.*
4. **Macro F1 averaged over only the classes present** while per-class metrics used all seven,
   making the number incomparable between two models predicting different subsets. `labels=`
   is now passed explicitly.

## Currently Working On

- Nothing in flight. Both ResNet-50 models trained (HAM10000 + PAD-UFES-20 separately) and
  evaluated; `scripts/demo_check.py` passes against the live backend (LLM path green via
  Ollama gemma2:9b). Demo-ready.

### Front-stage router (added 2026-08-10)

Replaces the binary lesion gate's bare "no lesion detected" with an informative outcome.
A multi-class softmax head on the ResNet-50's 2048-d features routes each photo:

    lesion  -> the 7-class disease model (unchanged)   healthy      -> "no concerning lesion detected"
    not_skin -> rejected (no_lesion_detected)           other_damage -> "other skin damage (e.g. a wound)"

- Trainer: `ml/ood/fit_lesion_router.py`; artifact `ml/checkpoints/lesion_router.npz` (4-way).
- Serving: `backend/app/services/lesion_router.py`; wired into `/predict` behind
  `LESION_ROUTER_ENABLED` (default true). When present it supersedes the binary gate; the
  Mahalanobis far-OOD check still runs. Falls back to the binary gate if the artifact is absent.
- SAFETY: the lesion route is high-recall (threshold calibrated to keep ~98% of real lesions
  going to the disease model), so a lesion is not siphoned into "healthy". Held-out val:
  lesion->healthy 0.3%, healthy->healthy 97.4%, not_skin 99.6%, other_damage->other_damage 96.8%.
  "healthy" is worded as "not a medical clearance"; healthy/other_damage skip the LLM and use
  fixed, application-owned advice (`safety/disclaimer.py`).
- Data: healthy = `data/ood_negatives_curated/Body_Parts_Dataset`; not_skin = faces/hands/scenes;
  other_damage = Kaggle `ibrahimfateen/wound-classification` (2740 wound imgs; its `Normal`
  folder was excluded to `data/router/_excluded_normal/`).
- App: `ResultData.dart` renders non-lesion outcomes (no class code / score bar / Grad-CAM /
  LLM; shows name + safe advice + disclaimer). APK rebuilt.
- App networking: backend URL is now runtime-configurable (login screen -> gear "Server
  settings", persisted via flutter_secure_storage) so DHCP IP changes no longer need an app
  rebuild. `config.dart` precedence: saved override -> `--dart-define=API_BASE_URL` ->
  platform default (currently `http://192.168.1.7:8000`). `main.dart` loads it before first frame.
- New enum `Outcome`, response fields `outcome` + `router_probabilities`, health field
  `lesion_router_available`. 7 unit tests in `backend/tests/test_lesion_router.py`. 144 tests pass.

Live-verified via `/predict`: lesion->BCC(urgent), wound->other_damage(0.92-1.0),
face/scene->no_lesion_detected. Healthy verified at router level (60/60 Body_Parts -> healthy);
the API healthy path shares the (proven) other_damage code path but needs a >=224px in-focus
photo to clear the quality gate first, which real phone captures are.

## Next Task

**The environment is set up and verified — that step is done.** Remaining:

1. Finish the HAM10000 download (Kaggle `kmader/skin-cancer-mnist-ham10000`, ~5.2 GB) and
   extract into `data/ham10000/`. Layout does not matter; `prepare_dataset.py` handles both
   the Kaggle and Dataverse shapes.
2. ```
   python -m ml.preprocessing.prepare_dataset
   python -m ml.preprocessing.validate_dataset
   python -m ml.preprocessing.split_dataset
   ```
   Record the measured imbalance ratio and leakage exposure — those two numbers belong in
   every review.
3. Train the ResNet-50 baseline, then EfficientNet-B0 on the same split.
4. Evaluate both, run `compare_models`, point `MODEL_CHECKPOINT`/`MODEL_ARCH` at the winner.
5. Install Ollama + `qwen3:8b` and test the LLM path (Phase 9).
6. Then, and only then, start the Flutter app (Phase 10).

## Known Bugs

- None known. Verified working end to end: environment check, class mapping, transforms,
  model factory, checkpoint round-trip, metrics, Grad-CAM (on real ISIC images, both
  architectures), and the full `/predict` path with a real checkpoint including Grad-CAM
  overlay generation, storage, retrieval and TTL purge.
- Untested paths: training loop (needs the dataset), evaluation/comparison scripts (need
  trained checkpoints), LLM service (needs Ollama).

## Verified Environment (2026-08-08)

```
Python 3.12.10  |  torch 2.11.0+cu128  |  CUDA 12.8
NVIDIA GeForce RTX 5050 Laptop, 8 GB, sm_120
GPU kernel launch verified (arch list includes sm_120)
ruff: clean       pytest: 131 passed
```

## Known Limitations

- No trained checkpoint exists — the backend runs in **stub mode** and returns clearly-labelled placeholder
  predictions with HTTP 503 semantics on `/predict` unless `ALLOW_STUB_MODEL=true`.
- HAM10000 is dermoscopy; smartphone-photo performance is unvalidated until PAD-UFES-20 is added.
- LLM path is untested — Ollama is not installed on this machine.
- Flutter app not started; only the inherited APK is present.

## Model Results

All from `ml/evaluation/evaluate.py` on held-out, lesion-grouped test splits (2026-08-09).
Full breakdown + per-class tables: `ml/results/RESULTS_SUMMARY.md`.

| Model (trained separately) | Test set | Macro-F1 | Bal-acc | Acc | ROC-AUC | Escalation sens | Missed serious |
|---|---|---:|---:|---:|---:|---:|---:|
| ResNet-50 / HAM10000 | HAM (1502) | 0.706 | 0.722 | 0.822 | 0.945 | 0.738 | 76 |
| ResNet-50 / HAM10000 | PAD (314) | 0.142 | 0.270 | 0.245 | — | 0.389 | 149 |
| ResNet-50 / PAD-UFES-20 | PAD (314) | 0.472 | 0.658 | 0.764 | — | 0.939 | 15 |

- HAM model = deployed 7-class checkpoint (`resnet50_best.pt` == `resnet50_best.HAM-only.pt`).
- PAD model = `resnet50_best.PAD-only.pt` (5 classes; `df`/`vasc` absent in PAD). On the 5
  shared classes, PAD-on-PAD macro-F1 = 0.661 vs HAM-on-PAD 0.199.
- Domain gap is the headline: a dermoscopy model on smartphone photos drops melanoma recall
  to 0.00 and escalation sensitivity to 0.39 — the concrete case for a PAD-specific model.
- Result dirs: `ml/results/eval_HAM-on-HAM/`, `eval_HAM-on-PAD/`, `eval_PAD-on-PAD/`.

## Files Changed

See `git status`. Everything under `backend/`, `ml/`, `scripts/`, `docs/`, `tests/` is new as of 2026-08-08.

## Dependencies Added

`backend/requirements.txt`, `ml/requirements.txt` (see files for pinned ranges). Nothing installed yet.

## Commands Used

```powershell
git init                                                    # repo on main, no commits yet
git clone --depth 50 <EPICS_Demo> upstream/EPICS_Demo
git clone --depth 50 <skin_disease_two_classification> upstream/
powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1
.\.venv\Scripts\python.exe scripts\verify_env.py
.\.venv\Scripts\python.exe -m pytest                        # 131 passed
.\.venv\Scripts\python.exe -m ruff check .                  # clean
```

## Important Decisions

| # | Decision | Reason |
|---|---|---|
| 1 | 7 classes from HAM10000 only for v1 | The 7 `dx` labels are real and self-consistent. ISIC 2019's SCC is added only if ISIC 2019 is actually ingested — no invented 8th class. |
| 2 | Split grouped by `lesion_id` | HAM10000 has multiple images per lesion; random splitting leaks and inflates results. |
| 3 | Triage is deterministic Python, not LLM output | Medical urgency must be reproducible and auditable. LLM only explains a category it is handed. |
| 4 | Disclaimer hardcoded in backend + app | Must not depend on the LLM generating it. |
| 5 | Grad-CAM written from scratch (~120 lines) | Removes a dependency, and it is a component the report must explain anyway. |
| 6 | Python 3.12, not the default 3.14 | No PyTorch wheels for 3.14. |
| 7 | cu128 PyTorch index | RTX 5050 is `sm_120`; default cu124 wheels lack kernels for it. |
| 8 | Confidence never described as disease probability | Spec §16 and basic medical-safety hygiene. |
| 9 | `upstream/` kept on disk but git-ignored | Needed for reading and citing; must never enter our history (nested `.git`, leaked secrets, 92 MB checkpoint). |
| 10 | Rewrite rather than port `skin_disease_two_classification` | `async=True` is a syntax error on modern Python; wrong task (binary); no pretrained-weights path. |
| 11 | Reuse the Flutter scaffold + assets, rewrite the networking | The scaffold saves real setup time; `DiagnoseAPI.dart` has both a leaked key and the wrong API contract. |

## Session Continuation Notes

- The master specification is `docs/reference/MASTER_SPEC.md`. It is the source of truth.
- Numbers in reports must come from `ml/results/`. Never fabricate metrics.
- Backend intentionally imports nothing from `ml/training` — training code stays out of the API server.
- If a session ends mid-task, the next session should read this file, then `git status`, then continue.

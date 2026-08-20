# AI-Assisted Dermatology Screening — Scan4Disease

> **This is a screening and educational decision-support system, not a medical diagnostic
> device.** It does not diagnose. Every result it produces recommends consulting a
> qualified dermatologist.

B.Tech MP online · Rajrup Roy Chowdhury (23BAI10213) · SCSAI, VIT Bhopal · 2026–2027

---

## Overview

A user photographs a skin lesion. A convolutional neural network classifies it into one of
seven dermatological categories and produces a Grad-CAM heatmap showing which regions drove
the prediction. A short symptom questionnaire is combined with that output by a
**deterministic rule layer**, which decides the urgency category. Only then does an
open-source language model turn the whole thing into plain English or Hindi.

The point of the separation is that the parts which matter medically are not generated text.

```
                        MOBILE APPLICATION
                                │  HTTPS
                                ▼
                        FASTAPI BACKEND
                                │
             ┌──────────────────┼──────────────────┐
             ▼                  ▼                  ▼
      IMAGE QUALITY GATE   PREPROCESSING      QUESTIONNAIRE
             │                  │                  │
             └──────────────────┤                  │
                                ▼                  │
                       CNN CLASSIFIER              │
                    (EfficientNet-B0 /             │
                        ResNet-50)                 │
                     │      │      │               │
                  class  confidence  Grad-CAM      │
                     └──────┴──────┬┘              │
                                   │               │
                                   └───────┬───────┘
                                           ▼
                            DETERMINISTIC TRIAGE RULES
                            (urgency decided HERE — auditable Python)
                                           │
                                           ▼
                              OPEN-SOURCE LLM (Qwen3)
                              (explanation + EN/HI only)
                                           │
                                           ▼
                          FIXED DERMATOLOGIST DISCLAIMER
                            (hardcoded, never generated)
```

## Key Features

- **7-class** lesion classification from HAM10000's actual label set — no invented classes.
- **Leakage-free evaluation**: the train/val/test split is grouped by `lesion_id`, so no
  lesion appears on both sides of the boundary, and this is asserted programmatically.
- **Grad-CAM** implemented from first principles, with a validation pass that flags
  heatmaps landing on the image border rather than the lesion.
- **ResNet-50 vs EfficientNet-B0** comparison on an identical split, with the deployment
  decision made by a rule stated before the results were seen.
- **Deterministic triage layer**: nine numbered rules, unit-tested, that decide urgency.
  The language model receives the category and explains it — it cannot change it.
- **Safety filter** on all generated text: blocks definitive diagnoses, false reassurance,
  drug recommendations, and "you have an 84% chance of melanoma" phrasing.
- **Bilingual** English/Hindi, with disease names, disclaimers and triage text translated
  in a version-controlled file rather than by the model at request time.
- **Privacy by default**: uploaded photographs are never written to disk; only the Grad-CAM
  overlay is stored, under an unguessable name, and deleted after a short TTL.
- **Free to run end to end**: local GPU training, local Qwen via Ollama, free hosting.
  No API keys, no credit card.

## Technology Stack

| Layer | Choice |
|---|---|
| Mobile | Flutter / Dart |
| Backend | FastAPI + Uvicorn (Python 3.12) |
| ML | PyTorch, torchvision, scikit-learn, OpenCV, Pillow |
| Models | ResNet-50, EfficientNet-B0 (ImageNet transfer learning) |
| Explainability | Grad-CAM (own implementation) |
| LLM | Qwen3 via Ollama, OpenAI-compatible endpoint |
| Datasets | HAM10000 (primary), ISIC 2019 / PAD-UFES-20 (planned) |

## Machine Learning Pipeline

```
raw download → prepare_dataset  → manifest.csv
             → validate_dataset → dataset_report.{json,md}   (corruption, duplicates, imbalance)
             → split_dataset    → split_v1.csv               (lesion-grouped, committed)
             → train            → checkpoints + history      (freeze head → fine-tune)
             → evaluate         → metrics, confusion matrix, calibration
             → compare_models   → deployment decision
             → generate_gradcam → heatmaps + focus audit
```

Transfer learning runs in two stages: the ImageNet backbone is frozen while the new 7-class
head trains, then everything is unfrozen and fine-tuned at a lower learning rate. Class
imbalance is handled with effective-number class weighting rather than raw inverse
frequency, which on HAM10000-like counts compresses the weight range from ~58× to ~9× and
trains far more stably.

## Dataset

HAM10000 — 10,015 dermoscopic images, 7 classes, with `lesion_id` metadata.

The dataset is **not** committed. See [`ml/datasets/README.md`](ml/datasets/README.md) for
download and setup. Two properties drive the whole design:

- **Severe imbalance.** `nv` is roughly two thirds of the data; `df` is about 1%. A model
  that answers "mole" every time scores ~67% accuracy and misses every melanoma. This is
  why accuracy is never the headline metric here.
- **Multiple images per lesion.** Around a fifth of images share a `lesion_id` with another.
  Splitting at random puts near-identical photographs in both train and test, and inflates
  the reported score for no reason other than a bug.

## Class Mapping

The seven classes are exactly the seven distinct values of HAM10000's `dx` column. No class
was invented, merged or split to hit a target count. Version-controlled in
[`ml/configs/class_mapping.json`](ml/configs/class_mapping.json).

| Code | Class | Tier |
|---|---|---|
| `mel` | Melanoma | malignant |
| `bcc` | Basal cell carcinoma | malignant |
| `akiec` | Actinic keratosis / intraepithelial carcinoma | pre-malignant |
| `nv` | Melanocytic nevus (mole) | benign |
| `bkl` | Benign keratosis-like lesion | benign |
| `df` | Dermatofibroma | benign |
| `vasc` | Vascular lesion | benign |

If ISIC 2019 is ingested later, SCC is added as a genuine 8th class — it is **not** folded
into `akiec`, because invasive squamous cell carcinoma and actinic keratosis are medically
distinct.

## Model Comparison

**No results yet — no model has been trained.** Once training runs,
`ml/results/comparison/comparison.md` is generated from measured numbers and linked here.
Nothing in this repository quotes a performance figure that was not produced by
`ml/evaluation/evaluate.py` on the held-out test split.

## Grad-CAM Explainability

Gradients of the predicted-class score with respect to the last convolutional block's
feature maps, averaged spatially into channel weights, used to weight and sum those maps,
ReLU'd, normalised and overlaid.

`generate_gradcam.py` additionally computes a `border_mass_fraction` per heatmap and flags
any above 50%. Lesions in this dataset are roughly centred, so a border-dominated heatmap
suggests the model is responding to vignetting, hairs or dermatoscope framing rather than
the lesion — which is worth knowing before claiming the model is explainable.

**Grad-CAM shows which regions influenced the score. It does not prove the model used
medically correct features.** See [`docs/gradcam.md`](docs/gradcam.md).

## LLM Integration

Qwen3 runs locally through Ollama on an OpenAI-compatible endpoint — no API key, no
account, no per-scan cost, and no skin photograph ever leaves the machine. That last point
is a genuine privacy argument for a medical application, not just a way to avoid a bill.

The model is given a structured JSON object containing the already-decided class,
confidence, triage category and reported symptoms, and is asked to write four fixed
sections. It is explicitly forbidden from inventing symptoms, naming drugs, converting
confidence into a disease probability, or changing the urgency.

If Ollama is not running, `/predict` still returns the classification, heatmap and triage
with `explanation_available: false`. The clinically meaningful part never depends on the
language model.

## Safety and Medical Disclaimer

Three independent layers:

1. **Deterministic triage** ([`backend/app/services/triage.py`](backend/app/services/triage.py))
   — urgency is computed by numbered rules before the LLM is called. Rules can only
   escalate; no answer can talk the system down from a malignant classification.
2. **Output filter** ([`backend/app/safety/filters.py`](backend/app/safety/filters.py)) —
   every generated response is checked. Definitive diagnoses, false reassurance and
   confidence-as-probability claims replace the whole response; drug mentions are redacted.
3. **Fixed disclaimer** ([`backend/app/safety/disclaimer.py`](backend/app/safety/disclaimer.py))
   — constant text in both languages, attached by the application to every result. It never
   passes through the model.

```
IMPORTANT

This result is generated by an AI screening system and is not a medical diagnosis.

Please consult a qualified dermatologist for professional evaluation, especially if
the lesion is new, changing, painful, bleeding, or otherwise concerning.
```

## Repository Structure

```
├── backend/            FastAPI application + tests
│   ├── app/
│   │   ├── routes/     /health /predict /chat /gradcam
│   │   ├── services/   preprocessing, quality, inference, gradcam, triage, llm, storage
│   │   ├── models/     runtime model + class-mapping loading
│   │   ├── schemas/    Pydantic API contract
│   │   └── safety/     disclaimers + output filter
│   └── tests/
├── ml/                 dataset pipeline, training, evaluation, explainability
│   ├── configs/        class_mapping.json, training_config.yaml, splits/
│   ├── preprocessing/  prepare, validate, split, transforms, dataset
│   ├── training/       transfer-learning trainer
│   ├── evaluation/     metrics, plots, evaluate, compare_models
│   └── explainability/ Grad-CAM
├── app/                Flutter application (screening client)
│   └── lib/
│       ├── Screens/    landing · auth · home · upload · reports · chat · doctors · guide
│       ├── services/   api client, auth, chat, localisation, doctor lookup
│       └── config.dart runtime-configurable backend base URL
├── dotnet/             optional .NET JWT gateway in front of the backend
├── docs/               architecture, API, dataset, gradcam, llm, safety, development
├── scripts/            environment setup and run helpers
├── tests/              cross-component parity and ML pipeline tests
├── PROJECT_STATUS.md   persistent development state — read this first
├── PROJECT_REPORT.md   consolidated MP online report
├── data/               datasets — never committed (git-ignored)
└── upstream/           inherited repos, reference only (git-ignored)
```

## Installation

Requires **Python 3.12** (PyTorch has no wheels for 3.14) and, for GPU training, a CUDA
build matching your card. See [`docs/development.md`](docs/development.md) for the details,
including the RTX 50-series `sm_120` gotcha.

```bash
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1
```

```bash
.venv/Scripts/python.exe scripts/verify_env.py
```

## Running the Backend

```bash
.venv/Scripts/python.exe -m uvicorn backend.app.main:app --reload --port 8000
```

Interactive API docs at `http://localhost:8000/docs`.

Without a trained checkpoint, `/predict` returns **503** by design. To build UI against it
before training finishes, set `ALLOW_STUB_MODEL=true` — responses are then flagged
`"stub": true` and must never be used for a demo.

## Running the Mobile App

The Flutter client lives in [`app/`](app/) and is integrated end to end with the backend.
See [`app/README.md`](app/README.md) for setup, the backend URL configuration, and the
client-side safety obligations.

```bash
cd app
flutter pub get
flutter run
```

On a physical phone, point the app at the laptop's LAN IP (or use
`adb reverse tcp:8000 tcp:8000` over USB); on the Android emulator the backend host is
`10.0.2.2`. The base URL is configurable at runtime in the app's "Server settings" dialog,
so no rebuild is needed when the laptop's Wi-Fi address changes.

## Training the Models

```bash
.venv/Scripts/python.exe -m ml.preprocessing.prepare_dataset
```

```bash
.venv/Scripts/python.exe -m ml.preprocessing.validate_dataset
```

```bash
.venv/Scripts/python.exe -m ml.preprocessing.split_dataset
```

```bash
.venv/Scripts/python.exe -m ml.training.train --arch resnet50
```

```bash
.venv/Scripts/python.exe -m ml.training.train --arch efficientnet_b0
```

Training is resumable — `--resume` continues from the last epoch checkpoint.

## Evaluation

```bash
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.pt --calibrate
```

```bash
.venv/Scripts/python.exe -m ml.evaluation.compare_models
```

Reported metrics: accuracy, balanced accuracy, macro/weighted F1, per-class
precision/recall/F1, confusion matrix, ROC-AUC, expected calibration error, sensitivity to
lesions needing escalation, and inference latency.

Run the test suite with:

```bash
.venv/Scripts/python.exe -m pytest
```

## Screenshots

App screenshots and demo media live under [`assets/screenshots/`](assets/screenshots/) and
[`assets/demo/`](assets/demo/) as they are captured.

## Limitations

State these plainly; they are not weaknesses in the write-up, they are the write-up.

- **Not a medical device.** It cannot replace a dermatologist and does not diagnose.
- **Domain gap.** HAM10000 is dermoscopy, captured with a contact lens and controlled
  lighting. The app takes smartphone photographs. Performance on phone images is
  **unvalidated** until PAD-UFES-20 is added.
- **Skin-tone representation.** HAM10000 is predominantly fair-skinned European patients.
  Performance across the full Fitzpatrick range is unmeasured.
- **Rare classes.** `df` and `vasc` have very few examples; their per-class metrics carry
  wide uncertainty.
- **Confidence is not clinical probability.** A high softmax score means the image resembled
  that category in training data. It is not the chance the user has the condition.
- **Grad-CAM is an interpretability aid**, computed at 7×7 and upsampled. Its apparent
  precision is interpolation, and a convincing heatmap on a wrong prediction is common.
- **The LLM can produce incorrect language**, which is why it sits behind a filter and has
  no authority over the triage category.
- **False positives and false negatives are both possible.**

## Future Work

- Train, evaluate and select the deployment model (Phases 3–5).
- External validation on PAD-UFES-20 smartphone images.
- Skin-tone fairness slice using Fitzpatrick17k.
- Device testing of the Flutter application across multiple phones and cameras.
- ONNX export for CPU serving; deployment to Hugging Face Spaces.
- Human evaluation of explanation quality (n≈100, 3 raters, Cohen's κ).

## Contributors

| Role | Owns |
|---|---|
| ML lead | Datasets, training, tuning, Grad-CAM, vision metrics |
| LLM + backend lead | Prompts, guard-rails, FastAPI, model serving |
| App lead | Flutter, localisation, device testing |
| Evaluation + docs lead | Literature review, human evaluation, reports |

## Acknowledgements

HAM10000: Tschandl, Rosendahl & Kittler, *Sci. Data* 5, 180161 (2018).
Grad-CAM: Selvaraju et al., ICCV 2017.
Class-balanced loss: Cui et al., CVPR 2019.
Temperature scaling: Guo et al., ICML 2017.

Prior-batch work (Scan4Disease / EPICS_Demo) is audited in
[`docs/reference/upstream_audit.md`](docs/reference/upstream_audit.md).

## License

See [`LICENSE`](LICENSE). Note that HAM10000 itself is CC BY-NC-SA 4.0 (non-commercial).

# AI-Assisted Dermatology Screening — Scan4Disease

> **This is a screening and educational decision-support system, not a medical diagnostic
> device.** It does not diagnose. Every result it produces recommends consulting a
> qualified dermatologist.

<p align="center">
  <img src="Demo_images/Home%20screen.jpeg" width="195" alt="Home screen">
  <img src="Demo_images/Mole%20identified.jpeg" width="195" alt="Screening result">
  <img src="Demo_images/Mole%20detection%20grad%20cam%20view.jpeg" width="195" alt="Grad-CAM view">
  <img src="Demo_images/Chatbot%20convo.jpeg" width="195" alt="Follow-up chat">
</p>

<p align="center"><a href="App%20Demo.md">Full app walkthrough, 28 screens</a></p>

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
- **Six architectures compared** on identical splits (ResNet-50, EfficientNet-B0 and B3,
  ConvNeXt-Tiny and Small, DenseNet-121), with the deployment rule fixed before the results
  were seen.
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

## Results

Every number below comes from `ml/evaluation/evaluate.py` on a held-out, lesion-grouped test
split. Nothing is hand-entered and no validation score is quoted as a test score.

### Deployed model: ResNet-50 on HAM10000, 1,502 test images

| Metric | Score |
|---|---:|
| Macro-F1 | 0.706 |
| Balanced accuracy | 0.722 |
| Accuracy | 0.822 |
| Macro ROC-AUC | 0.945 |
| Cohen's κ | 0.664 |
| Expected calibration error | 0.101 |

Accuracy is deliberately not the headline. `nv` is roughly two thirds of HAM10000, so a model
that always answered "mole" would score about 67% while missing every melanoma.

### The dermoscopy to smartphone domain gap

Two ResNet-50 models, identical code, schedule and seed, differing only in training data. The
dermoscopy model collapses when it is pointed at ordinary phone photographs.

| Model → test set | Macro-F1 | Escalation sensitivity |
|---|---:|---:|
| HAM → HAM (in-domain dermoscopy) | 0.706 | 0.738 |
| HAM → PAD (cross-domain phone photos) | 0.142 | 0.389 |
| PAD → PAD (in-domain phone photos) | 0.472 | 0.939 |

Melanoma recall for the dermoscopy model on phone photos is **0.00**. On the five classes the
two datasets share, macro-F1 is 0.199 for the dermoscopy model against 0.661 for the
smartphone-trained one. This is measured rather than assumed, and it is the reason the project
treats a dermoscopy-trained classifier as unsafe to deploy directly in a phone app.

Full breakdown, per-class tables and confusion matrices:
[`docs/model_report.md`](docs/model_report.md) ·
[`ml/results/RESULTS_SUMMARY.md`](ml/results/RESULTS_SUMMARY.md) ·
[`ml/results/CROSS_DATASET_COMPARISON.md`](ml/results/CROSS_DATASET_COMPARISON.md)

## Technology Stack

| Layer | Choice |
|---|---|
| Mobile | Flutter / Dart |
| Backend | FastAPI + Uvicorn (Python 3.12) |
| ML | PyTorch, torchvision, scikit-learn, OpenCV, Pillow |
| Models | ResNet-50 (deployed); EfficientNet-B0/B3, ConvNeXt-T/S, DenseNet-121 compared |
| Explainability | Grad-CAM (own implementation) |
| LLM | Qwen3 via Ollama, OpenAI-compatible endpoint |
| Datasets | HAM10000 (dermoscopy), PAD-UFES-20 (smartphone) |

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
├── docs/               architecture, API, dataset, gradcam, llm, safety, model report
├── scripts/            environment setup and run helpers
├── tests/              cross-component parity and ML pipeline tests
├── Demo_images/        app screenshots used by App Demo.md
├── PROJECT_REPORT.md   consolidated project report and change log
└── data/               datasets, never committed (git-ignored)
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

The trained checkpoint is not committed (it is too large for git), so a fresh clone needs one
in `ml/checkpoints/` before `/predict` will work. Without it the endpoint returns **503** by
design. Setting `ALLOW_STUB_MODEL=true` lets the UI be developed against a placeholder;
those responses carry `"stub": true` and are not valid for a demo.

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

## Limitations

State these plainly; they are not weaknesses in the write-up, they are the write-up.

- **Not a medical device.** It cannot replace a dermatologist and does not diagnose.
- **Domain gap, measured rather than hypothetical.** HAM10000 is dermoscopy, captured with a
  contact lens under controlled lighting, while the app takes smartphone photographs. The
  dermoscopy model scores 0.142 macro-F1 on phone images with 0.00 melanoma recall. The
  smartphone-trained model recovers most of that but is built on only 52 melanoma images.
- **Small melanoma sample on the smartphone side.** PAD-UFES-20 has 8 melanoma images in its
  test split, so that per-class figure moves by 0.125 with a single prediction.
- **Skin-tone representation.** HAM10000 is predominantly fair-skinned European patients.
  Performance across the full Fitzpatrick range is unmeasured. An ITA-based proxy was tried
  and found invalid on dermoscopy, so it is withdrawn rather than reported.
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

- Close the domain gap properly: fine-tune on combined HAM plus PAD data, or apply domain
  adaptation, instead of shipping two separate models.
- More melanoma examples on the smartphone side, since 52 images is too thin a base for the
  class that matters most.
- A valid skin-tone fairness slice, most likely on Fitzpatrick17k, after the ITA proxy failed.
- Device testing across more phones and cameras, and quantifying how much camera variance
  moves the prediction.
- ONNX export for CPU serving so the backend does not need a GPU host.
- Human evaluation of explanation quality with multiple raters and an agreement score.


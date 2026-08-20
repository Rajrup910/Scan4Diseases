# Development Setup

Everything here is free and needs no credit card. Times assume a decent connection.

**This machine, as detected on 2026-08-08:**

| | |
|---|---|
| OS | Windows 11 Home Single Language (26200) |
| GPU | NVIDIA GeForce RTX 5050 Laptop, 8 GB, driver 610.62 — Blackwell, **sm_120** |
| Python on PATH | 3.14.6 ← **unusable for PyTorch** |
| Python also installed | 3.12 ← **use this one** |
| Free disk | ~68 GB |
| Missing | Flutter, Dart, Ollama, Android Studio |

Two facts drive most of the setup below:

1. **PyTorch has no wheels for Python 3.14.** Use 3.12.
2. **The RTX 5050 is `sm_120`.** A plain `pip install torch` gives you a wheel built for
   older architectures. `torch.cuda.is_available()` will return `True` and then the first
   real matrix multiply will fail. Install from the **cu128 (or newer)** index.

---

## 1. Install order

Do these in order. Each is independent of the ones after it, so you can stop anywhere.

### 1.1 Python 3.12 — required, 5 min

Already installed at `C:\Users\RAJ\AppData\Local\Programs\Python\Python312\`. If you ever
need it again:

```bash
winget install --id Python.Python.3.12 --source winget
```

Do **not** uninstall 3.14 — just never use it for this project. The `py -3.12` launcher
selects the right one, and `scripts/setup_env.ps1` does that for you.

### 1.2 The Python environment — required, 10–15 min

```bash
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1
```

That creates `.venv` on Python 3.12, installs PyTorch from the CUDA index, installs
`ml/requirements.txt` and `backend/requirements.txt`, and runs the verifier.

If PyTorch has moved past cu128 by the time you read this (check
<https://pytorch.org/get-started/locally/>), pass the newer index:

```bash
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1 -CudaIndex cu129
```

Verify at any time:

```bash
.venv/Scripts/python.exe scripts/verify_env.py
```

The line that matters is `GPU kernel launch verified`. `CUDA available` alone is **not**
enough on a Blackwell card.

### 1.3 Git — installed already

`C:\Program Files\Git`. The repo is initialised on `main` with no commits yet.

### 1.4 CUDA toolkit — **not needed**

The PyTorch wheels bundle their own CUDA runtime. Driver 610.62 is far newer than the
12.8 runtime requires. Do not install the standalone CUDA Toolkit; it only creates
version confusion.

### 1.5 Ollama + Qwen — required for the LLM phase (Phase 9), ~15 min + 5 GB

Not needed until the classifier works, but the download is large — start it early.

```bash
winget install --id Ollama.Ollama --source winget
```

Then, in a new terminal:

```bash
ollama pull qwen3:8b
```

Test it, **including Hindi**, before you promise bilingual support in the report:

```bash
ollama run qwen3:8b "एक तिल और मेलेनोमा में क्या अंतर है? दो वाक्यों में बताइए।"
```

8 GB of VRAM holds a 4-bit 8B model (~5.2 GB) comfortably — but **not while training**.
Never train and run the LLM at the same time. If you hit VRAM pressure during
development, use `ollama pull qwen3:4b` and switch to 8B for the demo.

Ollama serves an OpenAI-compatible API at `http://localhost:11434/v1`, which is what
`backend/app/services/llm.py` targets. No API key, no account, unlimited calls.

### 1.6 Flutter + Android Studio — required for Phase 10 only, ~1 hour + ~15 GB

**Do not install these yet if disk is tight.** The Flutter app is Phase 10; the classifier
and backend are Phases 2–9. With ~68 GB free and ISIC 2019 at ~25 GB, you want to sequence
these rather than have both at once.

When you do get there:

```bash
winget install --id Google.AndroidStudio --source winget
```

Then Flutter — use the official installer or:

```bash
winget install --id Flutter.Flutter --source winget
```

Then:

```bash
flutter doctor
```

Resolve everything it flags, especially `Android licenses` (`flutter doctor --android-licenses`).
Use the **stable** channel; `flutter upgrade` gets you the current release.

### 1.7 WSL2 — optional

The planning docs recommend it. My advice: **skip it for now.** Your CUDA GPU works
natively on Windows, and putting the dataset inside WSL costs you disk and adds a
filesystem boundary between the training code and the Flutter tooling. Revisit only if
you hit a Linux-only dependency, which this stack does not have.

---

## 2. Datasets

Nothing is committed to git. Download into `data/` at the repo root (git-ignored).

### HAM10000 — required, ~2.6 GB

Primary training set: 10,015 dermoscopic images, 7 classes, with `lesion_id` metadata
(essential — it is what makes a leakage-free split possible).

Source: Harvard Dataverse, DOI `10.7910/DVN/DBW86T`, or the Kaggle mirror.

Target layout — the pipeline expects exactly this:

```
data/ham10000/
├── HAM10000_metadata.csv
└── images/
    ├── ISIC_0024306.jpg
    └── ...
```

The Dataverse download splits images across `HAM10000_images_part_1.zip` and
`part_2.zip`; extract **both into the same `images/` folder**.

Validate before training:

```bash
.venv/Scripts/python.exe -m ml.preprocessing.validate_dataset
```

### ISIC 2019 — optional, ~25 GB

Only after HAM10000 works end-to-end, and only if you have the disk. See
`ml/datasets/README.md`.

### PAD-UFES-20 — recommended later, ~3.5 GB

2,298 **smartphone** photos. This is the dataset that answers the examiner's sharpest
question: "your app takes phone photos but you trained on dermoscopy — does it work?"
Use it as an external validation set, never for training.

---

## 3. Running things

```bash
# Environment check
.venv/Scripts/python.exe scripts/verify_env.py

# Dataset validation and split (Phase 2)
.venv/Scripts/python.exe -m ml.preprocessing.validate_dataset
.venv/Scripts/python.exe -m ml.preprocessing.split_dataset

# Training (Phases 3-4)
.venv/Scripts/python.exe -m ml.training.train --arch resnet50
.venv/Scripts/python.exe -m ml.training.train --arch efficientnet_b0

# Evaluation and comparison
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.pt
.venv/Scripts/python.exe -m ml.evaluation.compare_models

# Backend
.venv/Scripts/python.exe -m uvicorn backend.app.main:app --reload --port 8000
# → http://localhost:8000/docs

# Tests
.venv/Scripts/python.exe -m pytest
```

---

## 4. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No matching distribution found for torch` | Running Python 3.14 | Use `py -3.12`, or re-run `scripts/setup_env.ps1` |
| `CUDA available: True` but ops crash with `no kernel image is available` | Wheel lacks sm_120 | Reinstall from `--index-url https://download.pytorch.org/whl/cu128` |
| `CUDA out of memory` during training | Batch too large for 8 GB | Drop `batch_size` 32 → 16 → 8 in `ml/configs/training_config.yaml` |
| OOM the moment training starts, GPU looks busy | Ollama is holding VRAM | `ollama stop qwen3:8b`, or close the Ollama tray app |
| Validation accuracy stuck near 67% | Model predicts `nv` every time | Class weighting is off — check `class_weights` in the config |
| Backend returns 503 on `/predict` | No trained checkpoint yet | Expected. Train first, or set `ALLOW_STUB_MODEL=true` for UI work |
| Phone cannot reach the laptop backend | Firewall / different subnet | Same WiFi, use the laptop's LAN IP, allow port 8000 through Windows Firewall |

---

## 5. Accounts worth creating early

| Account | Why | Card? |
|---|---|---|
| Kaggle | 30 free GPU-hours/week — your insurance if the laptop dies in November | No |
| Hugging Face | Free CPU Spaces for Phase-2 deployment | No |
| ISIC Archive | Required to download ISIC datasets | No |
| GitHub | Repo + collaborators (add your guide) | No |

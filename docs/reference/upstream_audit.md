# Upstream Repository Audit

**Date:** 2026-08-08
**Repos inspected:** cloned into `upstream/` (git-ignored — reference only, never vendored in).

| Repo | Commit inspected | Role claimed in project plan |
|---|---|---|
| [HarshSahu23/EPICS_Demo](https://github.com/HarshSahu23/EPICS_Demo) | `ddf8909` | "Flutter app, model wired in, real-time inference works" |
| [qmh1234567/skin_disease_two_classification](https://github.com/qmh1234567/skin_disease_two_classification) | `1cda14e` | "ResNet-50 on ISIC 2016, ~95% accuracy" |

---

## Headline finding — the project plan's description of the inherited system is wrong

Two claims in `docs/reference/Scan4Disease - Project Plan & Roadmap.md` do not survive contact with the code:

### 1. The app never ran a local model. It called a paid third-party API.

`lib/Screens/Upload/DiagnoseAPI.dart` posts the image as multipart to
`http://10.0.2.2:3000/analyze` (`10.0.2.2` is the Android emulator's alias for the host machine),
and the file carries a hardcoded **RapidAPI key and host** for
`detect-skin-disease.p.rapidapi.com`.

`lib/Screens/Upload/ResultData.dart` renders exactly that vendor's response shape:

```dart
diagnosisData['data']['image_quality']
diagnosisData['data']['body_part']
diagnosisData['data']['results_english']   // {label: probability, ...}
```

So the previous batch's "AI dermatologist" was a **thin client over a commercial
skin-disease API**. There is no ResNet, no TFLite model, and no on-device inference
anywhere in the repository.

### 2. The bundled Node server has no `/analyze` route at all.

`server/` is an Express + Mongoose CRUD scaffold. Its only controller
(`controller/modelController.js`) exposes `getInfo` / `createInfo` against a Mongo
collection. Nothing handles images. The endpoint the Flutter app calls **does not
exist in this repository** — it was either a local proxy that was never committed, or
the app talked to RapidAPI directly at some point.

### 3. The "~95% accuracy ResNet-50" traces to a 40-image test set.

`qmh1234567/skin_disease_two_classification` is an unrelated third-party
教学-style project (Chinese-language README). Its own documentation states the dataset:

| Split | benign | malignant | total |
|---|---|---|---|
| train | 64 | 64 | **128** |
| val | 16 | 16 | **32** |
| test | 20 | 20 | **40** |

200 images total. Not ISIC 2016's ~1,279. Any accuracy figure from this repo is
computed on **40 images**, where a single image is worth 2.5 percentage points.
It is a binary benign/malignant classifier, so it cannot produce the 7-class output
this project requires.

**This is a genuinely useful finding for the report.** The honest framing is:
*prior work reported a headline number from a 40-image balanced test set with no
per-class analysis; we replace it with a 7-class model evaluated on a lesion-grouped
held-out split with per-class recall and a confusion matrix.* That is a real,
defensible contribution rather than a vague "we improved it".

---

## Security issues in the inherited code

These are in **public** repositories belonging to the previous batch. Do not carry any
of it forward; if any of these accounts are yours or your seniors', have them rotated.

| # | Issue | Location |
|---|---|---|
| 1 | RapidAPI key committed in source | `lib/Screens/Upload/DiagnoseAPI.dart` (`const apiKey = ...`) |
| 2 | MongoDB Atlas credentials committed | `server/config.env` — `USERNAME`, `PASSWORD`, `DATABASE`, `DATABASE_PASSWORD` |
| 3 | Trained weights committed (92 MB) | `skin_two_classification/checkpoints/model_16_7165_10000.pth` |
| 4 | Compiled `.pyc` caches committed | `skin_two_classification/**/__pycache__/` |

Our `.gitignore` blocks all four categories (`.env`, `*.pth`, `__pycache__/`, `upstream/`),
and the backend reads every secret from environment variables.

---

## What is technically reusable

### From `EPICS_Demo` (Flutter)

| Asset | Verdict |
|---|---|
| Project scaffold (android/ios/web/desktop targets, gradle config) | **Reuse** — saves a day of Flutter setup |
| `assets/*.png` (body-part icons, doctor, no-image placeholder) | **Reuse** — decent, on-theme, already wired |
| `Screens/theme.dart` | **Reuse** — small colour/typography theme |
| `Screens/Upload/uploadScreen.dart` (camera + gallery + preview + retake) | **Refactor** — the camera/picker flow is sound; the networking and result handling must be rewritten |
| `Screens/Upload/widgets/SymptomsList.dart` | **Refactor** — becomes the structured questionnaire |
| `Screens/Reports/*` (28 KB + 15 KB of screens) | **Evaluate** — heavy, hardcoded demo data; likely rewrite |
| `Screens/Upload/DiagnoseAPI.dart` | **Delete and rewrite** — carries the leaked key and the wrong API contract |
| `server/` (Node + Mongo) | **Delete** — replaced by our FastAPI backend |
| `temp.dart`, `Screens/Reports/temp.dart`, `temp.txt`, empty `serviceScreen.dart` / `youScreen.dart` | **Delete** — dead files |

**Dependency state is stale and partly broken.** `pubspec.yaml` pins
`environment: sdk >=3.1.2`, `flutter_lints: ^2.0.0`, `image_picker: 1.0.8`,
`camera: ^0.10.5+4`, and several deps with no version constraint at all
(`google_fonts:`, `date_picker_timeline:`). Critically, `DiagnoseAPI.dart` imports
`package:http` but `http` appears in `pubspec.lock` only as a **transitive**
dependency — it is not declared in `pubspec.yaml`. That is a latent build failure.
Plan on `flutter pub upgrade --major-versions` plus a manual dependency pass.

### From `skin_disease_two_classification` (PyTorch)

| Asset | Verdict |
|---|---|
| `models/Res.py`, `main.py`, `data_gen.py`, `transform.py` | **Do not reuse** — see below |
| `used_dataset/` (200 ISIC jpgs) | Useful only as **smoke-test fixtures** for the inference pipeline |
| `checkpoints/*.pth` | **Do not use** — binary classifier, wrong task, unknown provenance |
| `README.md` results table | **Cite in the report** as the prior-work baseline being replaced |

The code will not run on modern PyTorch without edits. It targets roughly PyTorch 0.3–0.4:

- `inputs.cuda(async=True)` — `async` became a reserved keyword in Python 3.7; this is a **syntax error** on any current interpreter.
- `torch.autograd.Variable` — merged into `Tensor` since 0.4, deprecated.
- `torchnet`'s `meter.ConfusionMeter` — an extra unmaintained dependency.
- Hand-rewritten ResNet in `models/Res.py` instead of `torchvision`/`timm` pretrained weights.

Rewriting this is strictly less work than porting it, and our version needs
7-class output, class weighting, lesion-grouped splits, and Grad-CAM regardless —
none of which exist here.

---

## Decision

Build `backend/` and `ml/` fresh (already underway). For `mobile/`, copy the
`EPICS_Demo` scaffold and assets into `mobile/flutter_app/`, then rewrite the
networking, questionnaire and results layers against our API contract. Keep
`upstream/` on disk, git-ignored, purely to read from and to cite.

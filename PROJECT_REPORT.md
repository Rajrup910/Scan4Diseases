# Scan4Disease — Project Report & Change Log

**AI-Assisted Dermatology Screening**

> This is a **screening and educational decision-support system, not a medical diagnostic
> device.** It does not diagnose. Every result recommends consulting a qualified dermatologist.

This document is a single-file reference: what the project is, why it is novel, every model
that was trained and its measured scores, and the full change log. **Every performance number
here comes from
`ml/evaluation/evaluate.py` on a held-out, lesion-grouped test split** (source files cited per
table); none is hand-entered or quoted from validation as if it were a test number.

---

## 1. What the project is (in one paragraph)

A user photographs a skin lesion. A convolutional neural network classifies it into one of
seven dermatological categories and produces a Grad-CAM heatmap of the regions that drove the
prediction. A short symptom questionnaire is combined with that output by a **deterministic
rule layer**, which alone decides medical urgency. Only then does a local open-source language
model turn the result into plain-English or Hindi explanation. A front-stage router first
decides whether the photo is even a lesion (vs. healthy skin, a wound, or a non-skin image).
The whole stack runs at **zero marginal cost and with no third-party API keys**.

---

## 2. Novelty & contributions

The prior/inherited work was a thin mobile client posting images to a **commercial RapidAPI
service** (with a leaked key), returning a bare label, binary, with no evaluation rigour and no
explainability. This project replaces that with an auditable, self-hosted system whose
contributions are:

1. **Separation of authority across three components.** Most "AI doctor" apps hand an image or
   label to an LLM and ask how worried to be — producing urgency judgements that vary between
   runs and cannot be tested. Here:
   | Component | Decides | Auditable? |
   |---|---|---|
   | CNN | which category the lesion resembles (+ confidence) | via held-out metrics |
   | Rule layer | medical **urgency** | yes — 9 numbered rules, unit-tested |
   | LLM | wording and language only | it decides nothing |
   The triage runs **before** the LLM is ever called, so no generated text can influence urgency.

2. **Leakage-free evaluation as a first-class concern.** HAM10000 has multiple photographs of
   the same physical lesion; the train/val/test split is grouped by `lesion_id` and verified
   programmatically (`assert_no_leakage`), so the test score measures generalisation, not
   memorisation. ~44.9% of images belong to multi-image lesions — a random split would inflate
   scores materially.

3. **Quantified dermoscopy→smartphone domain gap.** The project trained the *same* architecture
   on dermoscopy (HAM10000) and on smartphone photos (PAD-UFES-20) and measured the collapse
   when a dermoscopy model is pointed at phone photos (melanoma recall → 0.00). This is a
   concrete, measured argument — not an assumption — for a domain-specific model before any
   smartphone deployment. (See §5.)

4. **Front-stage router + OOD lesion gate.** Rather than a bare "no lesion detected", a 4-way
   router (`lesion / healthy / not_skin / other_damage`) on the CNN's 2048-d features gives an
   informative outcome, backed by a Mahalanobis far-OOD check and a lesion-gate calibrated to
   keep ~98% of real lesions. Non-lesion outcomes skip the LLM and use fixed, app-owned advice.

5. **Grad-CAM from first principles with a self-audit.** Grad-CAM is implemented directly
   (~120 lines, no dependency) and every heatmap gets a `border_mass_fraction`; maps whose heat
   sits on the image border (vignetting, hair, dermatoscope framing) rather than the lesion are
   flagged, because those do not demonstrate medically meaningful attention.

6. **Multi-layer text safety.** A deterministic triage floor (rules can only escalate), an
   output filter that blocks definitive diagnoses / false reassurance / confidence-as-probability
   phrasing / drug names, and a fixed disclaimer rendered by the app, never by the model.

7. **Zero-cost, key-free, privacy-preserving by construction.** Local GPU training; local Qwen
   via Ollama (no API key, no per-scan cost, photos never leave the machine); the uploaded photo
   is **never written to disk** — only the Grad-CAM overlay is stored, under an unguessable name,
   deleted after a short TTL. The mobile "find a dermatologist" feature uses **keyless
   OpenStreetMap services** (see §7).

8. **Honest reporting, including a withdrawn result.** The skin-tone fairness slice was found to
   be invalid (the ITA proxy mis-measures skin tone on dermoscopy due to vignetting/erythema)
   and is explicitly **withdrawn and labelled unmeasured** rather than quoted — see
   `ml/results/skin_tone_slice.md`.

---

## 3. System architecture

```
                        MOBILE APPLICATION (Flutter)
                                │  HTTPS
                                ▼
                        FASTAPI BACKEND (Python 3.12)
                                │
             ┌──────────────────┼──────────────────┐
             ▼                  ▼                  ▼
      IMAGE QUALITY GATE   PREPROCESSING      QUESTIONNAIRE
             │                  │                  │
             └──────────────────┤                  │
                                ▼                  │
                    FRONT-STAGE ROUTER             │
              lesion / healthy / not_skin / other_damage
                                │ (lesion)         │
                                ▼                  │
                          CNN CLASSIFIER           │
                        (ResNet-50, 7-class)       │
                     class │ confidence │ Grad-CAM │
                          └──────┴──────┬──────────┘
                                        ▼
                          DETERMINISTIC TRIAGE RULES  ◄── urgency decided HERE
                                        │
                                        ▼
                          OPEN-SOURCE LLM (Qwen3, local Ollama)
                                (explanation + EN/HI only)
                                        │
                                        ▼
                          FIXED DERMATOLOGIST DISCLAIMER (hardcoded)
```

- The **backend never imports `ml`** — it duplicates three small things (model factory, eval
  transform, Grad-CAM) so the API can deploy without the training stack; `tests/test_parity.py`
  asserts the duplicates stay bit-identical.
- `class_mapping.json` is the single version-controlled source of truth; a checkpoint records
  the class codes it was trained on and loading refuses on mismatch.

**Technology stack**

| Layer | Choice |
|---|---|
| Mobile | Flutter / Dart |
| Backend | FastAPI + Uvicorn (Python 3.12) |
| ML | PyTorch (2.11.0+cu128), torchvision, scikit-learn, OpenCV, Pillow |
| Models | ResNet-50 (deployed); EfficientNet-B0/B3, ConvNeXt-T/S, DenseNet-121 (compared) |
| Explainability | Grad-CAM (own implementation) |
| LLM | Qwen3 via Ollama, OpenAI-compatible endpoint (gemma2:9b used in demo) |
| Datasets | HAM10000 (primary), PAD-UFES-20 (smartphone validation) |
| Maps (mobile) | OpenStreetMap Nominatim + geo/navigation intents (keyless) |

---

## 4. Datasets

### HAM10000 (primary — dermoscopy)
Source: Kaggle `kmader/skin-cancer-mnist-ham10000`. From `ml/results/dataset_report.md`:

- Images: **10,015** · Lesions: **7,470** · Classes: **7 / 7** · Corrupt: 0 · Exact dupes: 2
- Imbalance ratio (largest:smallest): **58.3 : 1**
- Multi-image lesions: 1,956 lesions → **4,501 images (44.9%)** — the reason for lesion-grouped splitting
- Single resolution 600×450, all RGB

| Class | Malignancy | Images | Share |
|---|---|---:|---:|
| `nv` Mole | benign | 6,705 | 66.9% |
| `mel` Melanoma | malignant | 1,113 | 11.1% |
| `bkl` Benign keratosis | benign | 1,099 | 11.0% |
| `bcc` Basal cell carcinoma | malignant | 514 | 5.1% |
| `akiec` Actinic keratosis | premalignant | 327 | 3.3% |
| `vasc` Vascular lesion | benign | 142 | 1.4% |
| `df` Dermatofibroma | benign | 115 | 1.1% |

### PAD-UFES-20 (smartphone validation)
Source: Mendeley `zr7vgbcyr2`. From `ml/results/RESULTS_SUMMARY.md`:

- 2,298 metadata rows → **2,106 usable** (dropped 192 `SCC` — no honest HAM equivalent)
- Class map: `BCC→bcc, MEL→mel, NEV→nv, ACK→akiec, SEK→bkl` (5 classes; `df`/`vasc` absent)
- Lesion-grouped 70/15/15 → **1,474 / 318 / 314** images; leakage check passed
- Per class: `bcc` 845, `akiec` 730, `nv` 244, `bkl` 235, `mel` 52

### OOD negative set (for the lesion gate)
From `ml/results/ood_negatives_report.md`: 14,249 usable photographs curated → **3,676 selected**
(near-OOD 3,076 / far-OOD 600). COCO capped 11,065→600 so easy far-OOD cannot dominate; FASSEG
segmentation masks dropped so the gate does not learn "cartoon colour blocks ≠ lesion".

---

## 5. Trainings committed & their scores

### 5.1 Training runs (from `ml/results/experiments.csv`)

Two ResNet-50 models were trained **independently** with identical code, a two-stage transfer
schedule (frozen head → fine-tune), seed 42, and identical augmentation.

| Run | Date | Train data | Classes | Epochs | Best val macro-F1 | Train time | Checkpoint |
|---|---|---|---:|---:|---:|---:|---|
| `resnet50_seed42` | 2026-08-08 | HAM10000 (dermoscopy) | 7 | 24 | **0.7401** (epoch 16) | 2,145 s (~35.8 min) | `resnet50_best.pt` (= `.HAM-only.pt`) — **deployed** |
| `resnet50_pad_seed42` | 2026-08-09 | PAD-UFES-20 (smartphone) | 5 | 24 | **0.5752** | 391 s (~6.5 min) | `resnet50_best.PAD-only.pt` |

**Shared hyperparameters:** arch ResNet-50 · image 224 · optimizer AdamW · head LR 1e-3 ·
fine-tune LR 1e-4 · batch 32 · weight decay 1e-4 · class weighting `effective_number` · seed 42 ·
monitor `macro_f1`. Augmentation: random-resized-crop scale [0.8,1.0], H/V flip 0.5, rotation
±20°, brightness/contrast 0.15, saturation 0.1, hue 0.02. Params **23,522,375** · model **~89.9 MB**
· inference **~5 ms/image** on CUDA (RTX 5050 Laptop, sm_120).

> Effective-number class weighting is used instead of raw inverse frequency: on HAM10000 counts
> it compresses the weight range from ~58× to ~9×, which trains far more stably.

### 5.2 Headline evaluation — the domain gap

From `ml/results/RESULTS_SUMMARY.md`. Macro-F1 is over all 7 class slots (PAD lacks `df`/`vasc`,
which caps its 7-slot number at 5/7).

| Evaluation | Test set | Macro-F1 | Bal-acc | Accuracy | Escalation sens. | Missed serious |
|---|---:|---:|---:|---:|---:|---:|
| HAM model on **HAM** (in-domain, deployed) | 1,502 | **0.706** | 0.722 | 0.822 | 0.738 | 76 |
| HAM model on **PAD** (cross-domain) | 314 | **0.142** | 0.270 | 0.245 | 0.389 | 149 |
| PAD model on **PAD** (in-domain) | 314 | **0.472** | 0.658 | 0.764 | **0.939** | 15 |

On the **5 classes both datasets share**: HAM-on-PAD macro-F1 **0.199** vs PAD-on-PAD **0.661**.
**Takeaway:** a dermoscopy-trained classifier is not safe on phone photos — melanoma recall on
PAD drops to 0.00 and escalation sensitivity to 0.39.

### 5.3 Deployed model — HAM-on-HAM (in-domain)

Source: `ml/results/eval_HAM-on-HAM/metrics.md` — 1,502 images, all 7 classes; selected on val
macro-F1 0.7401 (epoch 16); temperature 1.000 (uncalibrated).

| Metric | Value |
|---|---:|
| Macro F1 | **0.7058** |
| Balanced accuracy | 0.7217 |
| Accuracy | 0.8216 |
| Weighted F1 | 0.8228 |
| Cohen's κ | 0.6636 |
| Macro ROC-AUC (OvR) | 0.9452 |
| Expected calibration error | 0.1010 |

| Class | Precision | Recall | F1 | Support |
|---|---:|---:|---:|---:|
| `akiec` | 0.4815 | 0.7500 | 0.5865 | 52 |
| `bcc` | 0.7089 | 0.7887 | 0.7467 | 71 |
| `bkl` | 0.6892 | 0.6108 | 0.6476 | 167 |
| `df` | 0.7619 | 0.8000 | 0.7805 | 20 |
| `mel` | 0.5890 | 0.5749 | 0.5818 | 167 |
| `nv` | 0.9184 | 0.9084 | 0.9134 | 1,004 |
| `vasc` | 0.7647 | 0.6190 | 0.6842 | 21 |

**Screening view** (escalation = `akiec`/`bcc`/`mel` vs not): sensitivity **0.7379**,
specificity 0.9101, **76 missed serious**, 109 false alarms.

### 5.4 PAD-on-PAD (in-domain smartphone)

Source: `ml/results/eval_PAD-on-PAD/metrics.md` — 314 images, 5 classes present; val macro-F1 0.5752.

| Metric | Value |
|---|---:|
| Macro F1 (7-slot) | 0.4722 |
| Macro F1 (5 present) | **0.661** |
| Balanced accuracy | 0.6582 |
| Accuracy | 0.7643 |
| Cohen's κ | 0.6601 |
| ECE | 0.0832 |
| Escalation sensitivity | **0.9385** |

| Class | Precision | Recall | F1 | Support |
|---|---:|---:|---:|---:|
| `akiec` | 0.7768 | 0.8131 | 0.7945 | 107 |
| `bcc` | 0.8333 | 0.7752 | 0.8032 | 129 |
| `bkl` | 0.6875 | 0.6471 | 0.6667 | 34 |
| `mel` | 0.5000 | 0.2500 | 0.3333 | 8 |
| `nv` | 0.6304 | 0.8056 | 0.7073 | 36 |

**Screening view:** sensitivity 0.9385, specificity 0.9000, **15 missed serious**, 7 false alarms.
*Caveat:* only 8 melanoma in test, so `mel` recall (0.25 = 2/8) has very wide uncertainty; the
pooled escalation sensitivity (0.939) is the more meaningful safety figure.

### 5.5 HAM-on-PAD (cross-domain — the failure case)

Source: `ml/results/eval_HAM-on-PAD/metrics.md` — 314 images. Macro-F1 **0.1419**, accuracy 0.2452,
ECE 0.3857; `mel` precision/recall/F1 all **0.000** (8 support); escalation sensitivity 0.389,
**149 missed serious**. This is the measured evidence that motivates a domain-specific model.

### 5.6 Non-CNN "trainings" (fitted feature-space heads)

| Artifact | What it is | Key numbers | Source |
|---|---|---|---|
| `lesion_gate.npz` | OOD gate on 2048-d features (from `resnet50_best.pt`, epoch 16) | Threshold 0.996; **98.0% real lesions kept**, **100% held-out negatives rejected**; source-holdout (never-seen faces) 681/681 rejected; 800/800 COCO scenes rejected | `ml/results/ood_negatives_report.md` |
| `lesion_router.npz` | 4-way front-stage router (added 2026-08-10) | Held-out val: lesion→healthy **0.3%**, healthy→healthy **97.4%**, not_skin **99.6%**, other_damage→other_damage **96.8%** | `ml/results/` |

Router training data: healthy = curated Body-Parts images; not_skin = faces/hands/scenes;
other_damage = Kaggle `ibrahimfateen/wound-classification` (2,740 wound images).

### 5.7 Reproduce
```bash
.venv/Scripts/python.exe -m ml.preprocessing.prepare_pad_ufes
.venv/Scripts/python.exe -m ml.preprocessing.split_dataset --manifest ml/data/manifest_pad.csv --out ml/configs/splits/split_pad_only.csv
.venv/Scripts/python.exe -m ml.training.train --arch resnet50 --manifest ml/data/manifest_pad.csv --splits ml/configs/splits/split_pad_only.csv --run-name resnet50_pad_seed42
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.HAM-only.pt --manifest ml/data/manifest.csv --splits ml/configs/splits/split_v1.csv --out-dir ml/results/eval_HAM-on-HAM
```

---

## 6. Backend & safety

- **Endpoints:** `/health`, `/predict`, `/chat`, `/gradcam`. `/predict` takes a multipart image +
  questionnaire JSON + language and returns class, probabilities, confidence, triage, Grad-CAM
  URL, outcome, router probabilities, explanation and disclaimer.
- **Request flow:** decode → quality gate (Laplacian blur + luminance) → front-stage router →
  CNN + Grad-CAM (same pass) → **triage** → store overlay only → LLM → filter → fixed disclaimer.
- **Three safety layers:** deterministic triage (rules can only escalate) · output filter
  (blocks definitive diagnoses, false reassurance, confidence-as-probability, redacts drug names)
  · fixed bilingual disclaimer attached by the app.
- **Degradation:** no model → 503 (never a fabricated prediction); Ollama down →
  `explanation_available: false` with everything clinically meaningful still returned.
- **Tests:** grew to **144 passing** (triage rules & invariants, safety filter, all API error
  paths incl. path-traversal, `ml`↔`backend` parity incl. bit-identical preprocessing, ML
  pipeline leakage both directions, lesion-router 7 tests). `ruff` clean.

### Bugs found and fixed during verification
1. `setup_env.ps1` interpreter check always failed (`-notmatch` on an array filters, not booleans).
2. A dark image was misreported as "blurred" (black frame has no gradient → trips Laplacian);
   exposure is now checked first.
3. Pre-malignant mass could make a confident `akiec` "urgent", contradicting rule R2; malignant
   and pre-malignant mass now tracked separately (found by a test).
4. Macro-F1 averaged over only present classes, making two models incomparable; `labels=` now explicit.

---

## 7. Mobile application 

### 7.1 Find a dermatologist — reliability rewrite + inline dropdown
- **Problem fixed:** the feature always errored with *"Could not reach the map service"* because
  it used the **Overpass API**, whose public mirrors chronically time out (measured 20–30 s).
- **Fix:** migrated `NearbyDoctors` to **OpenStreetMap Nominatim** (keyless, ~0.5 s responses),
  with a bounded viewbox around the user, dermatology-first term widening
  (`dermatologist → skin clinic → clinic → hospital`) and a growing radius. Network-down vs.
  empty-result are now distinguished. Files: `lib/services/nearby_doctors.dart`.
- **New UX:** the result-screen card is now an **inline expandable dropdown** listing clinics
  with distance, proximity, specialty, open-hours and phone; tapping one opens turn-by-turn
  directions (native `geo:`/`google.navigation:` intents — still no Google API key). Files:
  `lib/services/find_doctor.dart`, `lib/Screens/Doctors/nearbyDoctorsScreen.dart`.
- *Note:* OpenStreetMap carries no crowd ratings for clinics, so a rating chip shows only where
  the data actually has one (rare) — ratings are not fabricated.

### 7.2 Skin health guide (new, content-rich, interactive)
New screen `lib/Screens/Guide/skinGuideScreen.dart` (fully offline; illustrations drawn with
`CustomPaint`, no image assets), with 10 expandable sections:
1. **Photograph a lesion properly** — tappable checklist with progress bar.
2. **ABCDE rule** — each letter with hand-drawn benign→concerning illustrations + "ugly duckling" note.
3. **Red flags** — clinical warning signs + direct find-a-dermatologist button.
4. **Sun protection & UV** — SPF-effectiveness stat cards (93/97/98%), application quantities,
   colour-coded UV-index scale, cloud/glass/snow reflection facts.
5. **Monthly self-exam** — 10-area head-to-toe tickable checklist + reminder toggle.
6. **Understanding your result** — five detailed explainers.
7. **Common skin conditions** — tap-a-chip explorer, 9 conditions with urgency badges.
8. **Myths vs. evidence** — 7 tap-to-reveal MYTH/FACT cards.
9. **Glossary** — 23 terms with live search.
10. **Know your skin type** — full **12-question Fitzpatrick questionnaire** (stepper with
    progress, back/restart, scored 0–48 → Type I–VI with tailored UV advice and burn-time).

### 7.3 Self-exam reminder (in-app, persisted)
`lib/services/self_exam_reminder.dart` — an **honest in-app reminder** (no OS-push plugin exists
in the project), persisted via `flutter_secure_storage`; loaded in `main.dart`; when due it
surfaces a prompt on app open (`landingPage.dart`) and rolls the next date forward.

### 7.4 "Understand this result" bar (per-result, on the result screen)
`UnderstandResultBar` in `lib/Screens/Upload/ResultData.dart` — an expandable, **context-aware**
explainer at the foot of every screening result. It quotes the actual score, writes a different
explanation per triage band (urgent/prompt/routine), shows a low-confidence warning only when
flagged, explains the heatmap only when one exists, gives lesion-vs-wound next steps, and links
into the guide with its results section pre-opened.

### 7.5 Home screen & navigation
- `lib/Screens/Home/homeScreen.dart` quick actions became a 2×2 grid:
  New screening · My screenings · **Skin care guide** · **Find a doctor**.
- Fixed a real bug: "Past reports" was wired to a no-op `Navigator.maybePop()`; it now switches
  to the Reports tab via an `onOpenReports` callback (`landingPage.dart`).

### 7.6 Delete screenings
`lib/Screens/Reports/reportScreen.dart` — swipe-to-delete, a per-card trash button, and a
header **"Clear all"**, each with a confirmation dialog, wired through the existing
`AppData.deleteReport()` (deletes on the backend for saved reports, from the list for local ones).

### 7.7 UI fixes
- Removed the "From OpenStreetMap…" helper text from the doctors list and result dropdown.
- Fixed **double titles** in the tab shell (`landingPage.dart`): the app-bar title is blanked for
  Reports / New Screening / Care & Tools, which each render their own large in-body header.
- Fixed a **20 px bottom overflow** in the "Server settings" dialog by wrapping its content in a
  `SingleChildScrollView` (`loginScreen.dart`).
- Fixed a layout bug where short content rows self-centred (glossary "Dermatologist"): content
  columns now pin to `CrossAxisAlignment.start`.


---

## 8. Implementation phases (project-wide status)

| Phase | Content | State |
|---|---|---|
| 1 | Repository audit and restructure | Done |
| 2 | Dataset pipeline (mapping, validation, leakage-free split, transforms) | Done |
| 3 | ResNet-50 baseline training (HAM10000) | **Done — trained & evaluated** |
| 4 | EfficientNet-B0 + model comparison | Code done; not run |
| 5 | Grad-CAM | Done — verified on real images |
| 6 | FastAPI `/health` `/predict` | Done — verified with real checkpoint |
| 7 | Questionnaire | Done |
| 8 | Deterministic triage layer | Done — 9 rules, unit-tested |
| 9 | LLM integration (Ollama/Qwen) | Done — demo path green (gemma2:9b) |
| — | PAD-UFES-20 smartphone model + domain-gap study | **Done — trained & evaluated** |
| — | Front-stage router + OOD lesion gate | **Done** |
| 10 | Flutter app | **In active development** (this session's work) |

---

## 9. Known limitations

- Deployed model is **dermoscopy-trained**; smartphone performance is quantified as poor (§5.5) —
  a PAD-specific model or domain adaptation is needed before real phone deployment.
- Melanoma support in PAD test is tiny (8 images); `mel` recall there is high-variance.
- Model is **uncalibrated** (temperature 1.0); HAM-on-HAM ECE 0.101.
- **Skin-tone fairness is unmeasured** — the ITA proxy was invalid on this data and its numbers
  were withdrawn (`ml/results/skin_tone_slice.md`).
- OpenStreetMap has thin coverage in some areas and no clinic ratings; a Google Maps fallback is
  always offered.
- The self-exam reminder is **in-app** (shown on open), not a background OS notification.

---

## 10. Artifact & source reference

| Area | Path |
|---|---|
| Results summary + per-eval metrics | `ml/results/RESULTS_SUMMARY.md`, `ml/results/eval_*/metrics.md` |
| Experiment log (hyperparameters, timings) | `ml/results/experiments.csv`, `experiments.jsonl` |
| Dataset / split / OOD reports | `ml/results/dataset_report.md`, `split_report.md`, `ood_negatives_report.md` |
| Deployed checkpoint | `ml/checkpoints/resnet50_best.pt` (= `.HAM-only.pt`) |
| PAD checkpoint / gate / router | `resnet50_best.PAD-only.pt`, `lesion_gate.npz`, `lesion_router.npz` |
| Architecture / safety docs | `docs/architecture.md`, `docs/safety.md`, `docs/gradcam.md`, `docs/llm.md` |
| Backend | `backend/app/` (routes, services, safety, schemas) |
| Mobile app | `app/lib/` |
| Persistent dev memory | `ml/results/` |

*All figures in this report were transcribed from the cited result files on 2026-08-10. Where a
number is a validation metric it is labelled as such; every other performance number is a
held-out test-split result.*

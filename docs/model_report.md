# Model Report

> **STATUS: NO MODEL HAS BEEN TRAINED YET.**
>
> This file is a template. Every `___` is filled from generated artefacts, never by hand and
> never from memory:
>
> | Section | Source |
> |---|---|
> | dataset numbers | `ml/results/dataset_report.md` |
> | split composition | `ml/results/split_report.md` |
> | per-model metrics | `ml/results/<arch>/metrics.md` |
> | comparison + decision | `ml/results/comparison/comparison.md` |
> | Grad-CAM audit | `ml/results/<arch>/gradcam/gradcam_report.md` |
> | hyperparameters | `ml/results/experiments.csv` |
>
> If the model achieves 82%, report 82%. If it achieves 91%, report 91%. Do not round
> upward, do not quote validation numbers as test numbers, and do not quote a figure that
> no artefact contains.

---

## 1. Experimental setup

| | |
|---|---|
| Dataset | HAM10000 |
| Images / lesions | ___ / ___ |
| Classes | 7 (`ml/configs/class_mapping.json` v___) |
| Split | lesion-grouped, stratified, 70/15/15, seed ___ |
| Leakage exposure | ___% of images share a lesion with another image |
| Input resolution | 224 × 224 |
| Hardware | NVIDIA RTX 5050 Laptop, 8 GB (sm_120) |
| Software | Python 3.12.10, PyTorch ___ + cu128 |

### Split composition

| Split | Lesions | Images | Share |
|---|---:|---:|---:|
| train | ___ | ___ | ___ |
| val | ___ | ___ | ___ |
| test | ___ | ___ | ___ |

### Class distribution

| Class | Tier | Total | train | val | test |
|---|---|---:|---:|---:|---:|
| `akiec` | pre-malignant | ___ | ___ | ___ | ___ |
| `bcc` | malignant | ___ | ___ | ___ | ___ |
| `bkl` | benign | ___ | ___ | ___ | ___ |
| `df` | benign | ___ | ___ | ___ | ___ |
| `mel` | malignant | ___ | ___ | ___ | ___ |
| `nv` | benign | ___ | ___ | ___ | ___ |
| `vasc` | benign | ___ | ___ | ___ | ___ |

---

## 2. Training procedure

Two-stage transfer learning from ImageNet weights:

```
stage 1   backbone frozen, train the new 7-class head      lr 1e-3, 3 epochs
stage 2   unfreeze everything, fine-tune                   lr 1e-4, cosine schedule
```

| Hyperparameter | Value |
|---|---|
| Optimizer | AdamW |
| Weight decay | 1e-4 |
| Batch size | ___ |
| Epochs run | ___ (early stopping patience 8) |
| Label smoothing | 0.05 |
| Class weighting | effective number, β = 0.999 |
| Gradient clipping | 5.0 |
| Mixed precision | enabled |
| **Selection metric** | **validation macro F1** — chosen before any test evaluation |
| Seed | ___ |

Augmentation: random resized crop (0.8–1.0), horizontal + vertical flip, ±20° rotation,
mild colour jitter. Evaluation uses resize-256 → centre-crop-224 with no augmentation.

---

## 3. Results — ResNet-50

*(from `ml/results/resnet50/metrics.md`)*

| Metric | Test |
|---|---:|
| Macro F1 | ___ |
| Balanced accuracy | ___ |
| Weighted F1 | ___ |
| Accuracy | ___ |
| Cohen's κ | ___ |
| Macro ROC-AUC | ___ |
| Expected calibration error | ___ |

| Class | Precision | Recall | F1 | Support |
|---|---:|---:|---:|---:|
| `akiec` | ___ | ___ | ___ | ___ |
| `bcc` | ___ | ___ | ___ | ___ |
| `bkl` | ___ | ___ | ___ | ___ |
| `df` | ___ | ___ | ___ | ___ |
| `mel` | ___ | ___ | ___ | ___ |
| `nv` | ___ | ___ | ___ | ___ |
| `vasc` | ___ | ___ | ___ | ___ |

Confusion matrix: `ml/results/resnet50/confusion_matrix.png`

---

## 4. Results — EfficientNet-B0

*(same tables, from `ml/results/efficientnet_b0/metrics.md`)*

---

## 5. Model comparison

*(from `ml/results/comparison/comparison.md`)*

Both models were trained and evaluated on the **identical split with identical code**.

The decision rule, stated before the results were seen:

> If the smaller model's macro F1 is within 0.01 of the larger model's, and its sensitivity
> to escalating classes is not worse by more than the same margin, deploy the smaller model
> and keep the larger one as the reported baseline. Otherwise deploy whichever has the
> higher macro F1.

| | ResNet-50 | EfficientNet-B0 |
|---|---:|---:|
| Macro F1 | ___ | ___ |
| Balanced accuracy | ___ | ___ |
| Sensitivity (escalating classes) | ___ | ___ |
| Missed serious cases | ___ | ___ |
| Parameters | 23.5 M | 4.0 M |
| Model size | 89.9 MB | 15.5 MB |
| Latency (mean, GPU) | ___ ms | ___ ms |

**Deployed: ___. Baseline: ___.**

Reason: ___

---

## 6. Screening-oriented analysis

Medical screening is asymmetric: a missed melanoma is materially worse than an unnecessary
referral. Collapsing the seven classes into "needs escalation" vs not:

| Metric | ResNet-50 | EfficientNet-B0 |
|---|---:|---:|
| Sensitivity | ___ | ___ |
| Specificity | ___ | ___ |
| **Missed serious cases** | ___ | ___ |
| False alarms | ___ | ___ |

Discuss the asymmetry rather than averaging it away. Report the melanoma recall explicitly.

---

## 7. Calibration

| | Before | After temperature scaling |
|---|---:|---:|
| Expected calibration error | ___ | ___ |
| Mean confidence | ___ | ___ |
| Mean accuracy | ___ | ___ |
| Fitted temperature | — | ___ |

Temperature is fitted on **validation**, never on test. It cannot change which class wins,
so accuracy and F1 are unaffected — it only makes the confidence number honest, which
matters because the app shows that number to a user.

Reliability diagram: `ml/results/<arch>/reliability_diagram.png`

---

## 8. Grad-CAM audit

*(from `ml/results/<arch>/gradcam/gradcam_report.md`)*

| Statistic | Value |
|---|---:|
| Images inspected | ___ |
| Mean border-mass fraction | ___ |
| Flagged (border mass > 50%) | ___ / ___ |

Findings from manual inspection: ___

Do not claim Grad-CAM proves the model reasons correctly. See [`docs/gradcam.md`](gradcam.md).

---

## 9. Comparison with prior work

The inherited 2024–25 project reported ~95% accuracy. That figure traces to
`qmh1234567/skin_disease_two_classification`, whose own README documents a **200-image
dataset with a 40-image test set** — one image is worth 2.5 percentage points there — and
which performs **binary** benign/malignant classification with no per-class analysis,
no confusion matrix, and no leakage-aware split.

The comparison is therefore not like-for-like, and the report should say so plainly rather
than implying an improvement from ~95% to some other number. The contribution is the
methodology: 7 classes, lesion-grouped split, per-class recall, calibration, explainability
audit, and a deterministic safety layer. See
[`docs/reference/upstream_audit.md`](reference/upstream_audit.md).

---

## 10. Limitations

- Not a medical device; does not diagnose.
- Trained on dermoscopy; the app takes smartphone photographs. Unvalidated until
  PAD-UFES-20 is added.
- HAM10000 is predominantly fair-skinned European patients; performance across the
  Fitzpatrick range is unmeasured.
- `df` and `vasc` have very few test examples; their metrics carry wide uncertainty.
- Model confidence is not clinical probability.
- Grad-CAM is computed at 7×7 and upsampled.
- Single split, single seed. Repeating across seeds would give error bars — worth doing if
  time allows, and worth stating as a limitation if not.

---

## 11. Reproducing these numbers

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

```bash
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.pt --calibrate
```

```bash
.venv/Scripts/python.exe -m ml.evaluation.compare_models
```

Full hyperparameters, seeds, timings and checkpoint paths for every run are appended to
`ml/results/experiments.csv`.

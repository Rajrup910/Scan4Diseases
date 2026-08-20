# Model Report

Every number in this file was produced by `ml/evaluation/evaluate.py` on a held-out,
lesion-grouped test split. None of it is hand-entered, and no validation score is quoted
as a test score. Source artefacts are cited per section.

---

## 1. Experimental setup

| | |
|---|---|
| Primary dataset | HAM10000 (dermoscopy), 10,015 images / 7,470 lesions |
| Secondary dataset | PAD-UFES-20 (smartphone), 2,106 usable images / 1,746 lesions |
| Classes | 7, from HAM10000's `dx` column (`ml/configs/class_mapping.json`) |
| Split | lesion-grouped, stratified, 70/15/15, seed 42 |
| Leakage check | asserted programmatically; no `lesion_id` crosses a split boundary |
| Backbone | ResNet-50, ImageNet weights |
| Schedule | two-stage transfer: frozen backbone → full fine-tune at lower LR |
| Loss | cross-entropy with effective-number class weighting |
| Software | Python 3.12.10, PyTorch 2.11.0 + cu128 |
| Hardware | RTX 5050 Laptop (Blackwell, sm_120), 8 GB |

Hyperparameters, seeds and timings for every run: `ml/results/experiments.csv`.

---

## 2. Deployed model — ResNet-50 trained and tested on HAM10000

`ml/results/eval_HAM-on-HAM/` — 1,502 test images, all 7 classes.
Checkpoint: `ml/checkpoints/resnet50_best.HAM-only.pt` (served as `resnet50_best.pt`).

| Metric | Test |
|---|---:|
| Macro-F1 | 0.706 |
| Balanced accuracy | 0.722 |
| Accuracy | 0.822 |
| Weighted F1 | 0.823 |
| Cohen's κ | 0.664 |
| Macro ROC-AUC | 0.945 |
| Expected calibration error | 0.101 |

Per class:

| Class | Precision | Recall | F1 | Support |
|---|---:|---:|---:|---:|
| `akiec` | 0.481 | 0.750 | 0.587 | 52 |
| `bcc`   | 0.709 | 0.789 | 0.747 | 71 |
| `bkl`   | 0.689 | 0.611 | 0.648 | 167 |
| `df`    | 0.762 | 0.800 | 0.780 | 20 |
| `mel`   | 0.589 | 0.575 | 0.582 | 167 |
| `nv`    | 0.918 | 0.908 | 0.913 | 1004 |
| `vasc`  | 0.765 | 0.619 | 0.684 | 21 |

Confusion matrix: `ml/results/eval_HAM-on-HAM/confusion_matrix.png`.

Accuracy is not the headline metric here. `nv` alone is roughly two thirds of HAM10000, so a
model that always answered "mole" would score about 67% accuracy while missing every
melanoma. Macro-F1 and per-class recall are the numbers that matter.

---

## 3. The dermoscopy → smartphone domain gap

Two ResNet-50 models were trained independently with identical code, schedule, seed and
augmentation, differing only in training data.

| Evaluation | Test set | Macro-F1 | Balanced acc | Accuracy | Escalation sensitivity |
|---|---|---:|---:|---:|---:|
| HAM model on HAM (in-domain) | 1,502 img | 0.706 | 0.722 | 0.822 | 0.738 |
| HAM model on PAD (cross-domain) | 314 img | 0.142 | 0.270 | 0.245 | 0.389 |
| PAD model on PAD (in-domain) | 314 img | 0.472 | 0.658 | 0.764 | 0.939 |

Macro-F1 above is computed over all 7 class slots. PAD contains no `df` or `vasc`, so those
count as zero and mechanically cap the PAD model at 5/7. Restricted to the five classes both
datasets share:

| On the 5 shared classes | Macro-F1 |
|---|---:|
| HAM model on PAD | 0.199 |
| PAD model on PAD | 0.661 |

Melanoma recall for the HAM model on PAD images is **0.00**. A dermoscopy-trained classifier
is therefore not safe to point at smartphone photographs, which is the argument for training
a domain-specific model before any phone deployment rather than reusing the dermoscopy one.

---

## 4. PAD model on PAD test (in-domain smartphone)

`ml/results/eval_PAD-on-PAD/` — 314 images, 5 classes present.

| Metric | Test |
|---|---:|
| Macro-F1 (7-slot) | 0.472 |
| Macro-F1 (5 present classes) | 0.661 |
| Balanced accuracy | 0.658 |
| Accuracy | 0.764 |
| Weighted F1 | 0.762 |
| Cohen's κ | 0.660 |
| Expected calibration error | 0.083 |
| Escalation sensitivity | 0.939 |

| Class | Precision | Recall | F1 | Support |
|---|---:|---:|---:|---:|
| `akiec` | 0.777 | 0.813 | 0.795 | 107 |
| `bcc`   | 0.833 | 0.775 | 0.803 | 129 |
| `bkl`   | 0.688 | 0.647 | 0.667 | 34 |
| `mel`   | 0.500 | 0.250 | 0.333 | 8 |
| `nv`    | 0.630 | 0.806 | 0.707 | 36 |

PAD holds only 52 melanoma images in total and 8 in the test split, so a `mel` recall of
0.250 represents 2 images out of 8 and carries very wide uncertainty. Escalation
sensitivity (0.939) pools all malignant and pre-malignant classes and is the more meaningful
safety figure at this sample size.

---

## 5. Dataset ingestion notes

PAD-UFES-20, from Mendeley `zr7vgbcyr2` (all three image parts plus `metadata.csv`):

- 2,298 metadata rows reduced to 2,106 usable after dropping 192 `SCC` images, which have no
  honest equivalent in the HAM10000 label space.
- Label map: `BCC→bcc`, `MEL→mel`, `NEV→nv`, `ACK→akiec`, `SEK→bkl`.
- Grouped by lesion (`padles_<patient>_<lesion>`), 1,746 groups, leakage check passed.
- Split 70/15/15 into 1,474 / 318 / 314 images.
- Class counts: `bcc` 845, `akiec` 730, `nv` 244, `bkl` 235, `mel` 52.
- Manifests: `ml/data/manifest_pad.csv`, `ml/data/manifest_combined.csv` (12,121 rows).

---

## 6. Reproducing these numbers

```bash
.venv/Scripts/python.exe -m ml.preprocessing.prepare_pad_ufes
.venv/Scripts/python.exe -m ml.preprocessing.split_dataset --manifest ml/data/manifest_pad.csv --out ml/configs/splits/split_pad_only.csv
.venv/Scripts/python.exe -m ml.training.train --arch resnet50 --manifest ml/data/manifest_pad.csv --splits ml/configs/splits/split_pad_only.csv --run-name resnet50_pad_seed42
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.PAD-only.pt --manifest ml/data/manifest_pad.csv --splits ml/configs/splits/split_pad_only.csv --out-dir ml/results/eval_PAD-on-PAD
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.HAM-only.pt --manifest ml/data/manifest.csv --splits ml/configs/splits/split_v1.csv --out-dir ml/results/eval_HAM-on-HAM
.venv/Scripts/python.exe -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.HAM-only.pt --manifest ml/data/manifest_pad.csv --splits ml/configs/splits/split_pad_only.csv --out-dir ml/results/eval_HAM-on-PAD
```

---

## 7. Known limitations of these results

- HAM10000 is predominantly fair-skinned European patients. Performance across the full
  Fitzpatrick range is unmeasured. An earlier attempt at a skin-tone slice using an ITA proxy
  was found to be invalid on dermoscopy and is withdrawn rather than reported; see
  `ml/results/skin_tone_slice.md`.
- `df` and `vasc` have 20 and 21 test images respectively, so their per-class figures move
  substantially with a handful of predictions.
- Expected calibration error is reported after temperature scaling on the validation split.
- Inference latency was measured on the training GPU, not on a phone or a CPU-only host.

Broader write-ups: `ml/results/RESULTS_SUMMARY.md` and
`ml/results/CROSS_DATASET_COMPARISON.md`.

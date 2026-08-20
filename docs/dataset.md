# Dataset and Split Methodology

Download and setup instructions live in [`ml/datasets/README.md`](../ml/datasets/README.md).
This document covers the part that determines whether the reported numbers mean anything.

---

## The pipeline

```
data/ham10000/  (any layout)
      │
      ├─ prepare_dataset.py   → ml/data/manifest.csv          image_id → path + label
      ├─ validate_dataset.py  → ml/results/dataset_report.*    corruption, duplicates, imbalance
      └─ split_dataset.py     → ml/configs/splits/split_v1.csv  COMMITTED
```

`prepare_dataset.py` searches recursively for the metadata file and every image, so the
Kaggle layout (`HAM10000_images_part_1/` + `part_2/`) and the Dataverse layout both work
without reorganising 10,000 files by hand.

The split file is **committed to version control**. Training reads it rather than
re-deriving the split, so a future scikit-learn release cannot silently change which images
are in the test set. Reproducibility here is a property of the repository, not of a seed.

---

## Data leakage — the decisive issue

HAM10000 contains **multiple photographs of the same physical lesion**, identified by
`lesion_id`. They are near-duplicates: same patient, same lesion, same session, slightly
different angle or magnification.

Split those at random and the test set contains images whose twins the model memorised
during training. The reported accuracy goes up by several points for no reason other than a
bug, and every downstream claim inherits the error.

### What this project does instead

```
1. reduce the manifest to one row per lesion_id     (each lesion has one diagnosis)
2. stratify those LESIONS by diagnosis
3. split the lesions 70 / 15 / 15
4. every image inherits its lesion's split
5. assert afterwards that no lesion_id appears in two splits
```

Step 5 is not decoration. `assert_no_leakage()` raises if any lesion spans a boundary, and
it runs every time the split is regenerated.

The property is also tested two ways, which matters more than it sounds:

```python
test_no_lesion_crosses_a_split_boundary      # the property holds
test_leakage_check_actually_catches_leakage  # the check fails when it should
```

A test that can only ever pass proves nothing. The second test constructs a deliberately
leaking split and asserts the guard raises.

### Consequences to expect

Image shares deviate slightly from the requested 70/15/15, because lesions contribute
different numbers of images. That is correct. Forcing exact image proportions would require
breaking lesion groups, which is the whole thing being avoided.

**Grouped-split scores are lower than random-split scores on this dataset.** That is the
point. If a comparison figure is useful for the report, run both and show the gap — the
difference is a direct measure of how much a random split would have inflated the result.

---

## Class imbalance

HAM10000 is severely imbalanced: `nv` is roughly two thirds of the data, `df` about 1%.
`validate_dataset.py` prints the measured ratio — quote that, not an approximation.

Three consequences shape the whole project:

**1. Accuracy is a misleading metric here.** A model that answers "mole" for every image
scores about 67% and misses every melanoma. So accuracy is reported but never as the
headline; macro F1, balanced accuracy and per-class recall are.

**2. Checkpoints are selected on validation macro F1**, chosen before any test-set
evaluation, so the selection metric cannot be tuned against the test set.

**3. Loss is class-weighted using effective number of samples**
(Cui et al., CVPR 2019) rather than inverse frequency:

```
w_i ∝ (1 - β) / (1 - β^{n_i})        β = 0.999
```

On HAM10000-like counts the weight ranges compare as:

| Scheme | Range | Ratio |
|---|---|---|
| inverse frequency | 0.046 – 2.68 | ~58× |
| effective number | 0.261 – 2.40 | ~9× |

Inverse frequency weights the rarest class so heavily that training becomes unstable and the
model starts over-predicting rare classes. Effective number interpolates between no
weighting and inverse frequency and behaves far better in practice. `--class-weighting` lets
you run the ablation; it is a good result to report either way.

---

## Validation checks

`validate_dataset.py` blocks training on problems that would invalidate the results, and
warns about the rest:

| Check | Blocking? |
|---|---|
| Corrupt / unreadable / missing images | yes |
| Lesions carrying more than one diagnosis | yes |
| A declared class with no images | yes |
| Exact duplicate files (byte hash) | reported |
| Images below the training resolution | reported |
| Resolution and colour-mode distribution | reported |
| Metadata completeness | reported |
| Fraction of images sharing a lesion | reported — this is the leakage exposure |

---

## Preprocessing

Training and evaluation transforms are strictly separated. Augmentation exists to make
training harder; applying it at evaluation time makes results non-deterministic.

**Evaluation / serving** — resize to 256, centre-crop 224, ImageNet normalisation. Identical
in `ml/` and `backend/`, asserted bit-for-bit by `tests/test_parity.py`.

**Training** — random resized crop (scale 0.8–1.0), horizontal and vertical flip, ±20°
rotation, and mild colour jitter.

Flips and rotations are safe because dermoscopic images have no canonical orientation.
Colour jitter is kept deliberately small (hue ±0.02): pigmentation and vascular patterns are
diagnostic signal, and aggressive colour distortion would teach the model to ignore exactly
the feature a dermatologist uses.

---

## Reporting checklist

- [ ] Dataset name, version, source, citation, licence
- [ ] Measured class distribution — from `dataset_report.md`, not from memory
- [ ] Imbalance ratio and how it was handled
- [ ] **Split strategy, stated explicitly as lesion-grouped**, with the leakage exposure figure
- [ ] Split sizes in both lesions and images
- [ ] Per-class counts per split
- [ ] Random seed
- [ ] Preprocessing and augmentation, with train/eval separation stated
- [ ] Known limitations: dermoscopy vs smartphone, skin-tone representation, rare classes

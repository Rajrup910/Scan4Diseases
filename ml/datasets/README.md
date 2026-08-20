# Datasets

**No image data is committed to this repository.** This folder holds download and setup
instructions only. Datasets live under `data/` at the repository root, which is git-ignored.

---

## HAM10000 — primary training set

10,015 dermoscopic images across the 7 classes in `ml/configs/class_mapping.json`.
Crucially, its metadata includes `lesion_id`, which is what makes a leakage-free split
possible — see `ml/preprocessing/split_dataset.py`.

**Citation (required in the report):**

> Tschandl, P., Rosendahl, C. & Kittler, H. *The HAM10000 dataset, a large collection of
> multi-source dermatoscopic images of common pigmented skin lesions.* Sci. Data 5, 180161 (2018).
> DOI: [10.1038/sdata.2018.161](https://doi.org/10.1038/sdata.2018.161)

**License:** CC BY-NC-SA 4.0 — non-commercial, share-alike. Fine for a MP online; note it
in the report.

### Where to get it

| Source | Notes |
|---|---|
| [Harvard Dataverse](https://doi.org/10.7910/DVN/DBW86T) | Canonical source. Metadata + two image zips. |
| [Kaggle: `kmader/skin-cancer-mnist-ham10000`](https://www.kaggle.com/datasets/kmader/skin-cancer-mnist-ham10000) | Mirror, ~5.2 GB. Also contains `hmnist_*.csv` 28×28 downsamples — **ignore those**, they are not usable for transfer learning. |

### Where to put it

Extract into `data/ham10000/`. **The exact folder layout does not matter.**
`prepare_dataset.py` searches recursively for the metadata file and for every image, so
both of these work as-is:

```
data/ham10000/                      data/ham10000/
├── HAM10000_metadata.csv           ├── HAM10000_metadata.csv
├── HAM10000_images_part_1/         └── images/
│   └── ISIC_0024306.jpg                ├── ISIC_0024306.jpg
└── HAM10000_images_part_2/             └── ...
    └── ISIC_0029306.jpg
```

Just make sure **both** image archives are extracted — the dataset is split across two,
and a run with only `part_1` will silently train on half the data.

### Then run

```bash
python -m ml.preprocessing.prepare_dataset
python -m ml.preprocessing.validate_dataset
python -m ml.preprocessing.split_dataset
```

Outputs:

| File | Committed? | Purpose |
|---|---|---|
| `ml/data/manifest.csv` | No — machine-specific paths | image_id → file path + label |
| `ml/results/dataset_report.{json,md}` | No | validation findings |
| `ml/configs/splits/split_v1.csv` | **Yes** | the reproducible split |
| `ml/results/split_report.md` | No | split composition + method |

### What to expect

HAM10000 is severely imbalanced — `nv` is roughly two thirds of the dataset and `df` is
about 1%. Roughly a fifth of the images share a `lesion_id` with another image. Both facts
are printed by `validate_dataset.py`; quote the measured numbers in your report rather
than these approximations.

---

## ISIC 2019 — optional scale-up

25,331 images, 8 classes (adds SCC). ~25 GB.

**Only attempt this after HAM10000 works end to end**, and check your disk first. Note
that ISIC 2019 *includes* the HAM10000 images, so naively concatenating the two datasets
duplicates a third of your data and will leak across splits unless deduplicated by
image_id first.

If ingested, SCC becomes a genuine 8th class — see `planned_extension` in
`ml/configs/class_mapping.json`. Do **not** merge SCC into `akiec`.

Source: <https://challenge.isic-archive.com/data/#2019> (free ISIC Archive account required).

---

## PAD-UFES-20 — recommended external validation

2,298 **smartphone** photographs of skin lesions, with clinical metadata.

This is the dataset that answers the sharpest question an examiner can ask: *your app
takes phone photos, but you trained on dermoscopy — does it actually work?* Use it as a
held-out external validation set. **Never train on it.** Reporting a lower score here than
on HAM10000 is a strong result, not a weak one: it is an honest measurement of the domain
gap, and almost no student project does it.

> Pacheco, A. G. C. et al. *PAD-UFES-20: A skin lesion dataset composed of patient data and
> clinical images collected from smartphones.* Data in Brief 32, 106221 (2020).

---

## Fitzpatrick17k — optional fairness analysis

16,577 images annotated with Fitzpatrick skin-type. Enables a skin-tone fairness slice —
per-skin-type recall — which is an easy, high-value differentiator and directly addresses
the "dataset populations may not represent all skin tones" limitation the report must state.

---

## Rules

1. Never commit images. `.gitignore` blocks `data/` and `ml/data/`.
2. Never commit patient photographs of any kind to `assets/`.
3. Record which dataset version each experiment used — `ml/results/experiments.csv` has a
   column for it.
4. Cite every dataset in the report. All of the above are free and citable.

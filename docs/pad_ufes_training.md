# Adding PAD-UFES-20: combined training and fine-tuning

PAD-UFES-20 (~2,300 smartphone lesion photos) is the deployment domain HAM10000's
dermoscopy does not represent. This runbook adds it as either a **pooled** dataset or a
**fine-tune** target, measures the domain gap, and keeps the deployed model safe until the
new one is proven. Everything below is "run the commands and read the scores."

Label mapping (fixed in `prepare_pad_ufes.py`): BCC→bcc, MEL→mel, NEV→nv, ACK→akiec,
SEK→bkl. **SCC is dropped** (no honest HAM10000 equivalent). PAD has no `df`/`vasc`, so
those two classes stay HAM-only.

## 0. Back up (rollback safety)
```bash
Copy-Item ml\checkpoints\resnet50_best.pt ml\checkpoints\resnet50_best.HAM-only.pt
Copy-Item ml\checkpoints\ood_mahalanobis.npz ml\checkpoints\ood_mahalanobis.HAM-only.npz
Copy-Item ml\checkpoints\lesion_gate.npz ml\checkpoints\lesion_gate.HAM-only.npz
```

## 1. Extract + ingest
Extract the Mendeley download to `data/pad_ufes_20/` (so `metadata.csv` and the image
folders sit under it), then:
```bash
python -m ml.preprocessing.prepare_pad_ufes
```
Writes `ml/data/manifest_pad.csv` (PAD only) and `ml/data/manifest_combined.csv`
(HAM + PAD). Read the printed per-class counts and the SCC/missing drops.

## 2. Domain-gap baseline — do this BEFORE retraining
First build the split + domain views, then score the current model on the PAD slice:
```bash
python -m ml.preprocessing.split_dataset --manifest ml/data/manifest_combined.csv --out ml/configs/splits/split_combined.csv --source-views
python -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.HAM-only.pt --manifest ml/data/manifest_combined.csv --splits ml/configs/splits/split_combined.pad_ufes.csv --out-dir ml/results/eval_HAM-on-PAD
```
The macro-F1 here is your headline "dermoscopy→phone" gap. Record it.

## 3a. Option A — pooled (train on both together)
```bash
python -m ml.training.train --arch resnet50 --manifest ml/data/manifest_combined.csv --splits ml/configs/splits/split_combined.csv
```

## 3b. Option B — fine-tune only (warm-start from HAM, adapt on PAD)
```bash
python -m ml.preprocessing.split_dataset --manifest ml/data/manifest_pad.csv --out ml/configs/splits/split_pad_only.csv
python -m ml.training.train --arch resnet50 --init-weights ml/checkpoints/resnet50_best.HAM-only.pt --manifest ml/data/manifest_pad.csv --splits ml/configs/splits/split_pad_only.csv --epochs 15
```
Run whichever you're testing (or both, comparing the numbers in step 4).

## 4. Evaluate on BOTH domains — the decision gate
```bash
python -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.pt --manifest ml/data/manifest_combined.csv --splits ml/configs/splits/split_combined.pad_ufes.csv --out-dir ml/results/eval_new-on-PAD
python -m ml.evaluation.evaluate --checkpoint ml/checkpoints/resnet50_best.pt --manifest ml/data/manifest_combined.csv --splits ml/configs/splits/split_combined.ham10000.csv --out-dir ml/results/eval_new-on-HAM
```
**Keep the new model only if BOTH hold:**
- PAD macro-F1 improved meaningfully vs the step-2 baseline (the whole point), and
- HAM `df` + `vasc` recall did not collapse (check `per_class` in `eval_new-on-HAM/metrics.md`).

If PAD improved but df/vasc cratered under fine-tune-only → prefer pooled (3a), or add a
small HAM replay set to the fine-tune. If neither wins, roll back:
```bash
Copy-Item ml\checkpoints\resnet50_best.HAM-only.pt ml\checkpoints\resnet50_best.pt
```

## 5. If you keep the new model — REFIT the OOD + gate (mandatory)
They were fit to the old feature space; a new checkpoint makes them stale.
```bash
python -m ml.ood.fit_mahalanobis
python -m ml.ood.fit_lesion_gate --negatives data/ood_negatives_curated --neg-views 2
```

## 6. Validate, then swap into the backend
```bash
.\.venv\Scripts\python.exe scripts\demo_check.py
```
Only point the backend at the new checkpoint once `demo_check` is green. Restart it with
`scripts\run_backend.ps1`.

## What each new capability is
- `ml/preprocessing/prepare_pad_ufes.py` — ingests PAD to the manifest schema, patient-grouped, SCC dropped.
- `split_dataset.py --source-views` — writes per-dataset view files so one model can be scored per domain.
- `train.py --init-weights / --manifest / --splits` — warm-start + dataset overrides.
- `evaluate.py --manifest / --splits` — score any split, including a single-domain view.

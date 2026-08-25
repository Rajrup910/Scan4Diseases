"""Build the demo verification dataset and a 10-image composite grid.

Selects a representative photograph for five distinct HAM10000 lesion classes
(mel, bcc, akiec, nv, bkl) and five distinct PAD-UFES-20 lesion classes
(MEL, BCC, ACK, NEV, SCC), copies each into ``demo_test_samples/manual_verification/``,
and renders a single labelled 2x5 verification grid at
``demo_test_samples/demo_verification_grid.png`` (HAM10000 on the top row,
PAD-UFES-20 on the bottom row).

If the inference stack (torch / FastAPI) is importable it then runs each selected
image through the in-process ``POST /predict`` endpoint and logs the confidence,
triage level, and Grad-CAM activation status. When the model stack is not
installed the grid is still produced and the API step is skipped gracefully, so
this script is safe to run in a lightweight environment.

Usage:
    python scripts/prepare_demo_dataset_grid.py
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pandas as pd
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

HAM_META = REPO_ROOT / "data" / "ham10000" / "HAM10000_metadata.csv"
HAM_IMG_DIRS = [
    REPO_ROOT / "data" / "ham10000" / "HAM10000_images_part_1",
    REPO_ROOT / "data" / "ham10000" / "HAM10000_images_part_2",
]
PAD_META = REPO_ROOT / "data" / "pad_ufes_20" / "metadata.csv"
PAD_IMG_ROOT = REPO_ROOT / "data" / "pad_ufes_20" / "images"

OUT_DIR = REPO_ROOT / "demo_test_samples"
SELECT_DIR = OUT_DIR / "manual_verification"
GRID_PATH = OUT_DIR / "demo_verification_grid.png"

# Five distinct HAM10000 classes -> (human name, clinical note).
HAM_CLASSES = {
    "mel": ("Melanoma", "Malignant"),
    "bcc": ("Basal Cell Carcinoma", "Malignant"),
    "akiec": ("Actinic Keratosis / IEC", "Pre-malignant"),
    "nv": ("Melanocytic Nevus", "Benign"),
    "bkl": ("Benign Keratosis", "Benign"),
}
# Five distinct PAD-UFES-20 classes -> (human name, clinical note).
PAD_CLASSES = {
    "MEL": ("Melanoma", "Malignant"),
    "BCC": ("Basal Cell Carcinoma", "Malignant"),
    "ACK": ("Actinic Keratosis", "Pre-malignant"),
    "NEV": ("Nevus", "Benign"),
    "SCC": ("Squamous Cell Carcinoma", "Malignant"),
}


def _index_ham_images() -> dict[str, Path]:
    index: dict[str, Path] = {}
    for d in HAM_IMG_DIRS:
        if d.is_dir():
            for p in d.glob("*.jpg"):
                index[p.stem] = p
    return index


def _index_pad_images() -> dict[str, Path]:
    index: dict[str, Path] = {}
    if PAD_IMG_ROOT.is_dir():
        for p in PAD_IMG_ROOT.rglob("*.png"):
            index[p.name] = p
    return index


def select_ham() -> list[dict]:
    df = pd.read_csv(HAM_META)
    images = _index_ham_images()
    picks: list[dict] = []
    for code, (name, note) in HAM_CLASSES.items():
        rows = df[df["dx"] == code].sort_values("image_id")
        chosen = None
        for _, row in rows.iterrows():
            img_id = str(row["image_id"])
            if img_id in images:
                chosen = images[img_id]
                break
        if chosen is None:
            print(f"  [WARN] HAM10000: no on-disk image found for class '{code}'")
            continue
        picks.append(
            {
                "dataset": "HAM10000",
                "code": code,
                "name": name,
                "note": note,
                "src": chosen,
                "dst_name": f"ham_{code}_{chosen.stem}.jpg",
            }
        )
    return picks


def select_pad() -> list[dict]:
    df = pd.read_csv(PAD_META)
    images = _index_pad_images()
    picks: list[dict] = []
    for code, (name, note) in PAD_CLASSES.items():
        rows = df[df["diagnostic"] == code].sort_values("img_id")
        chosen = None
        for _, row in rows.iterrows():
            fname = str(row["img_id"])
            if fname in images:
                chosen = images[fname]
                break
        if chosen is None:
            print(f"  [WARN] PAD-UFES-20: no on-disk image found for class '{code}'")
            continue
        picks.append(
            {
                "dataset": "PAD-UFES-20",
                "code": code,
                "name": name,
                "note": note,
                "src": chosen,
                "dst_name": f"pad_{code}_{Path(chosen).stem}.png",
            }
        )
    return picks


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                pass
    return ImageFont.load_default()


# Clinical palette matching the app / portal (emerald + triage tones).
NOTE_COLORS = {
    "Malignant": (205, 43, 49),
    "Pre-malignant": (148, 104, 0),
    "Benign": (13, 110, 91),
}
CANVAS = (15, 17, 23)        # #0F1117 dark canvas
CARD = (22, 25, 32)          # #161920 dark glass card
ACCENT = (45, 212, 191)      # #2DD4BF electric teal
INK = (232, 233, 236)
INK_SOFT = (155, 161, 173)


def build_grid(picks: list[dict]) -> None:
    cell_w, cell_h = 340, 340
    pad = 22
    label_h = 84
    header_h = 96
    row_label_h = 34
    cols = 5
    rows = 2

    grid_w = pad + cols * (cell_w + pad)
    grid_h = header_h + rows * (row_label_h + cell_h + label_h + pad) + pad

    canvas = Image.new("RGB", (grid_w, grid_h), CANVAS)
    draw = ImageDraw.Draw(canvas)

    f_title = _font(34)
    f_sub = _font(18)
    f_row = _font(20)
    f_name = _font(21)
    f_meta = _font(17)

    draw.text((pad + 4, 24), "Scan4Disease · Demo Verification Grid", font=f_title, fill=INK)
    draw.text(
        (pad + 6, 64),
        "10 lesions · 5 HAM10000 classes + 5 PAD-UFES-20 classes",
        font=f_sub,
        fill=ACCENT,
    )

    ham = [p for p in picks if p["dataset"] == "HAM10000"]
    pad_rows = [p for p in picks if p["dataset"] == "PAD-UFES-20"]

    for r, (label, row_picks) in enumerate(
        [("HAM10000 — dermatoscopic", ham), ("PAD-UFES-20 — clinical (smartphone)", pad_rows)]
    ):
        row_top = header_h + r * (row_label_h + cell_h + label_h + pad) + pad
        draw.text((pad + 4, row_top), label, font=f_row, fill=INK_SOFT)
        cell_top = row_top + row_label_h
        for c, p in enumerate(row_picks):
            x = pad + c * (cell_w + pad)
            # Card background
            draw.rounded_rectangle(
                [x, cell_top, x + cell_w, cell_top + cell_h + label_h],
                radius=18,
                fill=CARD,
                outline=(38, 42, 51),
                width=1,
            )
            # Image (cover-fit into the cell)
            try:
                im = Image.open(p["src"]).convert("RGB")
            except Exception as exc:  # noqa: BLE001
                print(f"  [WARN] could not open {p['src']}: {exc}")
                continue
            im = _cover_fit(im, cell_w - 24, cell_h - 24)
            canvas.paste(im, (x + 12, cell_top + 12))
            # Labels
            ty = cell_top + cell_h + 4
            draw.text((x + 16, ty), p["name"], font=f_name, fill=INK)
            note_color = NOTE_COLORS.get(p["note"], INK_SOFT)
            draw.text((x + 16, ty + 30), f"{p['code']} · {p['note']}", font=f_meta, fill=note_color)

    canvas.save(GRID_PATH)
    print(f"\n  Saved verification grid -> {GRID_PATH.relative_to(REPO_ROOT)} ({grid_w}x{grid_h})")


def _cover_fit(im: Image.Image, w: int, h: int) -> Image.Image:
    src_ratio = im.width / im.height
    dst_ratio = w / h
    if src_ratio > dst_ratio:
        new_h = h
        new_w = int(h * src_ratio)
    else:
        new_w = w
        new_h = int(w / src_ratio)
    im = im.resize((new_w, new_h), Image.LANCZOS)
    left = (new_w - w) // 2
    top = (new_h - h) // 2
    return im.crop((left, top, left + w, top + h))


def copy_selected(picks: list[dict]) -> None:
    SELECT_DIR.mkdir(parents=True, exist_ok=True)
    for p in picks:
        dst = SELECT_DIR / p["dst_name"]
        shutil.copyfile(p["src"], dst)
    print(f"  Copied {len(picks)} source images -> {SELECT_DIR.relative_to(REPO_ROOT)}/")


def run_api_verification(picks: list[dict]) -> None:
    """Best-effort in-process /predict verification. Skipped if torch/FastAPI absent."""
    try:
        from fastapi.testclient import TestClient  # noqa: PLC0415

        from backend.app.main import app  # noqa: PLC0415
    except Exception as exc:  # noqa: BLE001
        print("\n  [SKIP] API verification — inference stack not importable in this "
              f"environment ({type(exc).__name__}: {exc}).")
        print("         Run inside the backend venv (with torch installed) to log "
              "confidence / triage / Grad-CAM.")
        return

    print("\n  Running /predict verification on all 10 selected images:")
    print("  " + "-" * 92)
    print(f"  {'Dataset':<12}{'Class':<7}{'HTTP':<6}{'Outcome':<11}{'Predicted':<26}{'Conf':<8}{'Triage':<10}{'GradCAM'}")
    print("  " + "-" * 92)
    with TestClient(app) as client:
        for p in picks:
            with open(p["src"], "rb") as f:
                img_bytes = f.read()
            mime = "image/png" if p["src"].suffix.lower() == ".png" else "image/jpeg"
            res = client.post(
                "/predict",
                files={"image": (p["src"].name, img_bytes, mime)},
                data={"language": "en", "include_explanation": "false"},
            )
            if res.status_code == 200:
                data = res.json()
                outcome = data.get("outcome", "lesion")
                pred = data.get("predicted_name") or "-"
                conf = f"{(data.get('confidence') or 0.0) * 100:.1f}%"
                triage = (data.get("triage") or {}).get("category") or "-"
                gradcam = "YES" if data.get("gradcam_url") else "no"
                print(f"  {p['dataset']:<12}{p['code']:<7}{res.status_code:<6}{outcome:<11}{pred[:24]:<26}{conf:<8}{triage:<10}{gradcam}")
            else:
                print(f"  {p['dataset']:<12}{p['code']:<7}{res.status_code:<6}(see body: {res.text[:60]})")
    print("  " + "-" * 92)


def main() -> None:
    print("=" * 70)
    print("PREPARING DEMO VERIFICATION DATASET & 10-IMAGE GRID")
    print("=" * 70)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("\n[1/4] Selecting 5 HAM10000 + 5 PAD-UFES-20 lesion images ...")
    picks = select_ham() + select_pad()
    for p in picks:
        print(f"    {p['dataset']:<12} {p['code']:<6} {p['name']:<28} <- {p['src'].name}")
    if len(picks) < 10:
        print(f"\n  [WARN] only {len(picks)}/10 images selected; grid will show what was found.")

    print("\n[2/4] Copying selected source images ...")
    copy_selected(picks)

    print("\n[3/4] Rendering composite verification grid ...")
    build_grid(picks)

    print("\n[4/4] API verification against /predict ...")
    run_api_verification(picks)

    print("\n" + "=" * 70)
    print(f"DONE — {len(picks)} images, grid at demo_test_samples/demo_verification_grid.png")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    main()

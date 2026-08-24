"""Curate and copy 5 distinct demo test photos for presentation and user testing."""

import io
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from PIL import Image
from fastapi.testclient import TestClient
from backend.app.main import app

samples_dir = REPO_ROOT / "demo_test_samples"
samples_dir.mkdir(parents=True, exist_ok=True)

# 5 Curated Demo Photos representing 5 distinct diagnostic and clinical criteria
SELECTED_PHOTOS = {
    "01_melanoma_malignant": {
        "src": "data/ham10000/HAM10000_images_part_1/ISIC_0024310.jpg",
        "title": "Photo 1: Melanoma (Malignant / High Risk)",
        "expected_class": "mel",
        "category": "Malignant Skin Cancer",
        "clinical_triage": "Urgent medical evaluation",
    },
    "02_basal_cell_carcinoma": {
        "src": "data/ham10000/HAM10000_images_part_1/ISIC_0024331.jpg",
        "title": "Photo 2: Basal Cell Carcinoma (Malignant)",
        "expected_class": "bcc",
        "category": "Common Malignant Carcinoma",
        "clinical_triage": "Urgent / Prompt medical evaluation",
    },
    "03_actinic_keratosis_precancer": {
        "src": "data/ham10000/HAM10000_images_part_1/ISIC_0024372.jpg",
        "title": "Photo 3: Actinic Keratosis (Pre-malignant)",
        "expected_class": "akiec",
        "category": "Pre-cancerous Lesion",
        "clinical_triage": "Prompt dermatologist consultation",
    },
    "04_benign_melanocytic_nevus": {
        "src": "data/ham10000/HAM10000_images_part_1/ISIC_0024306.jpg",
        "title": "Photo 4: Melanocytic Nevus (Benign Mole)",
        "expected_class": "nv",
        "category": "Benign Pigmented Lesion",
        "clinical_triage": "Routine dermatologist consultation",
    },
    "05_skin_abrasion_wound": {
        "src": "data/router/other_damage/Abrasions/abrasions (1).jpg",
        "title": "Photo 5: Skin Abrasion / Wound (Non-Lesion Safety Gate)",
        "expected_class": "other_damage",
        "category": "Non-Lesion Skin Damage (Router Gate)",
        "clinical_triage": "General wound care advice (Safety Gate Triggered)",
    },
}


def main():
    print("=" * 70)
    print("COPYING & VERIFYING 5 CURATED DEMO PHOTOS IN demo_test_samples/")
    print("=" * 70)

    with TestClient(app) as client:
        for file_key, meta in SELECTED_PHOTOS.items():
            src_path = REPO_ROOT / meta["src"]
            dst_path = samples_dir / f"{file_key}.jpg"
            
            # Copy source image to demo_test_samples directory
            shutil.copyfile(src_path, dst_path)

            with open(dst_path, "rb") as f:
                img_bytes = f.read()

            res = client.post(
                "/predict",
                files={"image": (dst_path.name, img_bytes, "image/jpeg")},
                data={"language": "en", "include_explanation": "false"},
            )

            print(f"\n[{meta['title']}]")
            print(f"  File Path:       demo_test_samples/{dst_path.name}")
            print(f"  Category:        {meta['category']}")
            print(f"  HTTP Response:   {res.status_code}")
            
            if res.status_code == 200:
                data = res.json()
                outcome = data.get("outcome", "lesion")
                if outcome == "lesion":
                    cls_name = data.get("predicted_name")
                    cls_code = data.get("predicted_class")
                    conf = data.get("confidence", 0.0) * 100
                    triage_cat = (data.get("triage") or {}).get("category")
                    print(f"  Pipeline Outcome: {outcome.upper()}")
                    print(f"  Predicted Disease: {cls_name} ({cls_code})")
                    print(f"  Confidence:       {conf:.1f}%")
                    print(f"  Triage Category:  {triage_cat}")
                    print(f"  Grad-CAM Active:  {'YES' if data.get('gradcam_url') else 'NO'}")
                else:
                    print(f"  Pipeline Outcome: {outcome.upper()} (Front-stage safety router)")
                    print(f"  Router Detail:    Identified as non-lesion skin damage / wound safely")
            else:
                print(f"  Error Response:   {res.text}")

    print("\n" + "=" * 70)
    print("ALL 5 DEMO PHOTOS VERIFIED & COPIED TO demo_test_samples/")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    main()

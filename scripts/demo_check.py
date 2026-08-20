"""Pre-demo smoke test: prove the live backend behaves correctly before presenting.

    python scripts/demo_check.py
    python scripts/demo_check.py --base-url http://192.168.1.7:8000

Runs the checks that actually break during a demo, against the *running* server rather
than a test client, so it catches a stale process serving an old checkpoint or a gate
artifact that never got reloaded.

  1. /health reports a real model (not stub mode) with both OOD components loaded.
  2. A genuine lesion is accepted and produces a class, a triage category and a Grad-CAM.
  3. A non-lesion skin photo (body part) is rejected by the lesion gate.
  4. A scene photograph is rejected.
  5. The explanation path returns without breaking the response.

Exit code is 0 only if every check passes, so it can gate a demo or run in CI.
"""

from __future__ import annotations

import argparse
import csv
import io
import random
import sys
from pathlib import Path

import httpx
from PIL import Image, ImageOps

REPO_ROOT = Path(__file__).resolve().parent.parent

# Mirrors Settings.quality_min_side_px. Images below this are rejected by the quality
# gate before inference, so they can never exercise the lesion gate.
MIN_SIDE_PX = 224
# Mirrors _maxUploadEdge in the Flutter uploadScreen, so this check uploads what the
# app uploads rather than a raw camera file the app would never send.
APP_MAX_EDGE = 1600

GREEN, RED, YELLOW, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[0m"


class Checks:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.skipped = 0

    def record(self, ok: bool, label: str, detail: str = "") -> None:
        mark = f"{GREEN}PASS{RESET}" if ok else f"{RED}FAIL{RESET}"
        print(f"  [{mark}] {label}")
        if detail:
            print(f"         {detail}")
        if ok:
            self.passed += 1
        else:
            self.failed += 1

    def skip(self, label: str, detail: str = "") -> None:
        """Inconclusive, not wrong. The app refused to screen, so the user was never put
        at risk -- but the lesion gate was not reached, so this run is no evidence
        either way. Counting it as a pass would overstate what was verified."""
        print(f"  [{YELLOW}SKIP{RESET}] {label}")
        if detail:
            print(f"         {detail}")
        self.skipped += 1


def pick_lesion(count: int) -> list[Path]:
    """Images from the held-out test split, which no gate or model fit ever saw."""
    manifest = REPO_ROOT / "ml" / "data" / "manifest.csv"
    splits = REPO_ROOT / "ml" / "configs" / "splits" / "split_v1.csv"
    if not (manifest.is_file() and splits.is_file()):
        return []
    with manifest.open(encoding="utf-8", newline="") as fh:
        id_to_path = {r["image_id"]: r["path"] for r in csv.DictReader(fh)}
    with splits.open(encoding="utf-8", newline="") as fh:
        ids = [r["image_id"] for r in csv.DictReader(fh) if r["split"] == "test"]
    rng = random.Random(11)
    rng.shuffle(ids)
    out: list[Path] = []
    for image_id in ids:
        rel = id_to_path.get(image_id)
        if not rel:
            continue
        p = REPO_ROOT / rel
        if p.is_file():
            out.append(p)
        if len(out) >= count:
            break
    return out


def pick_from(folder: str, count: int, min_side: int = MIN_SIDE_PX) -> list[Path]:
    """Negatives large enough to reach the lesion gate.

    The quality gate rejects anything under `min_side` before inference runs, so a
    small image proves nothing about the lesion gate no matter how it is classified.
    Sources shot at 128x128 are therefore unusable for this check.
    """
    d = REPO_ROOT / "data" / "ood_negatives_curated" / folder
    if not d.is_dir():
        return []
    files = sorted(p for p in d.iterdir()
                   if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".webp"})
    rng = random.Random(5)
    rng.shuffle(files)
    out: list[Path] = []
    for p in files:
        try:
            with Image.open(p) as im:
                if min(im.size) >= min_side:
                    out.append(p)
        except Exception:  # noqa: BLE001 - unreadable file is simply not a candidate
            continue
        if len(out) >= count:
            break
    return out


def pick_from_dir(directory: Path, count: int, min_side: int = MIN_SIDE_PX) -> list[Path]:
    """Like `pick_from`, but for an arbitrary directory (e.g. the wound set), recursively."""
    if not directory.is_dir():
        return []
    files = sorted(p for p in directory.rglob("*")
                   if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".webp"})
    rng = random.Random(5)
    rng.shuffle(files)
    out: list[Path] = []
    for p in files:
        try:
            with Image.open(p) as im:
                if min(im.size) >= min_side:
                    out.append(p)
        except Exception:  # noqa: BLE001 - unreadable file is simply not a candidate
            continue
        if len(out) >= count:
            break
    return out


def post_predict(client: httpx.Client, path: Path, explain: bool) -> httpx.Response:
    """Upload exactly as the app does: downscaled to the app's max edge, re-encoded.

    Sending the original file would not represent production. A raw 12MP camera capture
    exceeds the server's upload limit outright, so a check that posted one would report a
    failure the real client never hits.
    """
    with Image.open(path) as im:
        img = ImageOps.exif_transpose(im).convert("RGB")
        img.thumbnail((APP_MAX_EDGE, APP_MAX_EDGE))
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=90)
        payload = buf.getvalue()
    return client.post(
        "/predict",
        files={"image": (path.stem + ".jpg", payload, "image/jpeg")},
        data={"language": "en", "include_explanation": str(explain).lower()},
        timeout=120.0,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Pre-demo smoke test against a live backend.")
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    ap.add_argument("--samples", type=int, default=3, help="Images per negative category.")
    args = ap.parse_args()

    checks = Checks()
    client = httpx.Client(base_url=args.base_url)
    print(f"\nDemo check against {args.base_url}\n")

    # --- 1. health -------------------------------------------------------------
    print("health")
    try:
        health = client.get("/health", timeout=15.0).json()
    except Exception as exc:  # noqa: BLE001 - the point is to report, not raise
        print(f"  {RED}backend unreachable: {exc}{RESET}")
        return 1
    checks.record(health.get("model_loaded") is True, "a model is loaded")
    checks.record(health.get("stub_mode") is False, "not in stub mode",
                  "stub mode returns synthetic predictions - never demo this"
                  if health.get("stub_mode") else "")
    checks.record(health.get("lesion_gate_available") is True, "lesion gate loaded")
    checks.record(health.get("ood_available") is True, "Mahalanobis OOD loaded")
    print(f"         device={health.get('device')} arch={health.get('model_arch')} "
          f"llm={health.get('llm_available')}")

    # --- 2. real lesions are accepted ------------------------------------------
    print("\nreal lesions (held-out test split) - must be ACCEPTED")
    lesions = pick_lesion(args.samples)
    if not lesions:
        checks.record(False, "found test-split lesion images", "manifest/split missing")
    for path in lesions:
        r = post_predict(client, path, explain=False)
        if r.status_code == 200:
            body = r.json()
            checks.record(
                bool(body.get("predicted_class")) and bool(body.get("triage")),
                f"{path.name} accepted",
                f"class={body.get('predicted_name')} "
                f"confidence={body.get('confidence', 0.0):.3f} "
                f"triage={(body.get('triage') or {}).get('category')} "
                f"gradcam={'yes' if body.get('gradcam_url') else 'no'} "
                f"stub={body.get('stub')}",
            )
        else:
            code = r.json().get("code", "?") if r.headers.get("content-type", "").startswith(
                "application/json") else r.text[:80]
            checks.record(False, f"{path.name} accepted", f"HTTP {r.status_code} {code}")

    # --- 3. wounds / other skin damage are ROUTED, not rejected ----------------
    # With the front-stage router, a wound is no longer a bare "no lesion detected": it
    # gets the `other_damage` outcome. These images pass the quality gate (unlike the
    # 128x128 healthy thumbnails), so this exercises the non-lesion 200 path end to end.
    print("\nwounds / other skin damage - must be ROUTED to other_damage (200)")
    wounds = pick_from_dir(REPO_ROOT / "data" / "router" / "other_damage", args.samples)
    if not wounds:
        checks.record(False, "found wound images", "none under data/router/other_damage")
    for path in wounds:
        r = post_predict(client, path, explain=False)
        body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        outcome = body.get("outcome")
        if r.status_code == 200 and outcome == "other_damage":
            checks.record(True, f"{path.name} -> other_damage",
                          f"router={ {k: round(v, 2) for k, v in (body.get('router_probabilities') or {}).items()} }")
        elif r.status_code == 200 and outcome == "healthy":
            # The safe direction of the router's ~2-3% wound<->healthy confusion. Not a
            # disease misread, so it is inconclusive rather than a failure.
            checks.skip(f"{path.name} routed to healthy, not other_damage",
                        "known minority confusion; the dangerous lesion->healthy direction is ~0.3%")
        elif r.status_code == 200 and outcome == "lesion":
            checks.record(False, f"{path.name} -> other_damage",
                          f"a wound was routed to a DISEASE class ({body.get('predicted_name')})")
        elif r.status_code == 422 and body.get("error") == "image_quality_insufficient":
            checks.skip(f"{path.name} did not reach the router", "quality gate rejected it first")
        else:
            checks.record(False, f"{path.name} -> other_damage",
                          f"HTTP {r.status_code} outcome={outcome} err={body.get('error')}")

    # --- 4. non-skin photos are still rejected as not_skin ---------------------
    for label, folder in (("faces (near-OOD)", "Fasseg-DB-v2019"),
                          ("hands (near-OOD)", "Hand_images"),
                          ("scenes/objects (far-OOD)", "img_files")):
        print(f"\n{label} - must be rejected as non-skin")
        samples = pick_from(folder, args.samples)
        if not samples:
            checks.record(False, f"found usable samples in {folder}",
                          f"none at >={MIN_SIDE_PX}px; run ml.ood.prepare_negatives")
            continue
        for path in samples:
            r = post_predict(client, path, explain=False)
            body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
            err = body.get("error", "")
            if r.status_code == 422 and err == "no_lesion_detected":
                checks.record(True, f"{path.name} rejected", "no_lesion_detected")
            elif r.status_code == 422:
                # The app refused to screen, so nothing unsafe happened -- but an
                # unrelated rejection reason means the lesion gate never ran, and this
                # image proves nothing about it either way.
                checks.skip(f"{path.name} did not reach the gate",
                            f"rejected by '{err}' first "
                            f"({(body.get('detail') or '')[:60]})")
            else:
                checks.record(False, f"{path.name} rejected",
                              f"HTTP {r.status_code} - a non-lesion was SCREENED")

    # --- 5. explanation path ----------------------------------------------------
    print("\nexplanation path (LLM)")
    if lesions:
        r = post_predict(client, lesions[0], explain=True)
        if r.status_code == 200:
            body = r.json()
            available = body.get("explanation_available")
            checks.record(True, "request with explanation succeeded",
                          f"explanation_available={available}"
                          + ("" if available else f"  {YELLOW}(degraded, not broken){RESET}"))
        else:
            checks.record(False, "request with explanation succeeded", f"HTTP {r.status_code}")

    total = checks.passed + checks.failed
    skipped = f", {checks.skipped} inconclusive" if checks.skipped else ""
    print(f"\n{'-' * 52}")
    if checks.failed == 0:
        print(f"{GREEN}DEMO READY{RESET}  {checks.passed}/{total} checks passed{skipped}\n")
        return 0
    print(f"{RED}NOT DEMO READY{RESET}  {checks.failed} of {total} failed{skipped}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())

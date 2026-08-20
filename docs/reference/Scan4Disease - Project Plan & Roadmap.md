# Scan4Disease — MP online Project Plan

**Student:** Rajrup Roy Chowdhury (23BAI10213) · B.Tech AI · SCSAI, VIT Bhopal
**Academic Year:** 2026–2027 · MP online Phase-1 (Fall) → Phase-2 (Winter)
**Prepared:** 5 August 2026

---

## 1. Where the project currently stands

You have inherited a completed 2024–25 MP online ("Scan4Disease / AI Dermatologist", batch 21BSA). What exists:

| Asset | State |
|---|---|
| Flutter Android app (`app-release.apk`) | Built, UI complete, working |
| App source — [EPICS_Demo](https://github.com/HarshSahu23/EPICS_Demo) | Available |
| ML model — [skin_disease_two_classification](https://github.com/qmh1234567/skin_disease_two_classification) | Third-party repo, **binary** classifier |
| ResNet-50 trained on ISIC 2016 | ~95% claimed accuracy, **melanoma vs non-melanoma only** |
| Integration | Model wired into the app, real-time inference works |
| Two full reports + deck | Reusable for literature review and figures |

**Honest assessment of what is weak** — and therefore what your contribution should fix:

1. **Binary classification is not clinically useful.** "Cancer / not cancer" on ISIC 2016 (~1,279 images, heavily imbalanced) is a toy result. The 95% figure is almost certainly accuracy on an imbalanced test set, not sensitivity on melanoma — the metric that actually matters.
2. **Zero explainability.** The app returns a label. A user in a village given the word "melanoma" with no explanation is worse off than before.
3. **No evaluation rigour.** No per-class F1, no AUC-ROC, no confusion matrix, no external validation.
4. **The "AI dermatologist" name is unearned** — there is no reasoning, no conversation, no triage.

Point 4 is exactly the gap the Qwen model fills, which makes it a defensible research contribution rather than a bolted-on feature.

---

## 2. What you are proposing (Scan4Disease)

**Title:** *Scan4Disease — An AI Dermatologist Mobile System combining Multi-Class Skin Lesion Classification with an LLM-based Explanation and Triage Assistant*

**One-line thesis:** A CNN tells you *what* the lesion probably is; an 8B language model tells you *what that means and what to do*, in your own language, without ever pretending to be a doctor.

### The two-model pipeline

```
 [ Phone camera ]
        │
        ▼
 ┌──────────────────────┐
 │ 1. Image QC gate     │  blur / lighting / "is this even skin?" check
 └──────────┬───────────┘
            ▼
 ┌──────────────────────┐
 │ 2. Vision model      │  ResNet-50 / EfficientNet-B0
 │    (fine-tuned)      │  → 7–8 classes + calibrated confidence
 │                      │  → Grad-CAM heat-map
 └──────────┬───────────┘
            │  {class, confidence, top-3, heatmap summary}
            ▼
 ┌──────────────────────┐      ┌───────────────────────────┐
 │ 3. Symptom form      │─────▶│ 4. Qwen3-8B (local/Ollama)│
 │    duration, itch,   │      │    system-prompted +      │
 │    bleeding, change  │      │    guard-railed           │
 └──────────────────────┘      └────────────┬──────────────┘
                                            ▼
                        explanation · urgency triage · self-care
                        · EN/HI · follow-up Q&A · "see a doctor"
```

### Target classes (HAM10000 / ISIC 2019)

| Code | Class | Malignant? |
|---|---|---|
| MEL | Melanoma | Yes |
| BCC | Basal cell carcinoma | Yes |
| AKIEC | Actinic keratosis / intraepithelial carcinoma | Pre-malignant |
| NV | Melanocytic nevi (mole) | No |
| BKL | Benign keratosis-like lesions | No |
| DF | Dermatofibroma | No |
| VASC | Vascular lesions | No |
| *(opt.)* SCC | Squamous cell carcinoma | Yes |

### Exactly what Qwen3-8B does

**Input to the model** (structured JSON, not free text):
```json
{
  "top_prediction": "BCC", "confidence": 0.81,
  "runner_ups": [["AKIEC", 0.09], ["BKL", 0.05]],
  "gradcam_region": "central raised area, irregular border",
  "symptoms": {"duration_months": 8, "itching": false,
               "bleeding": true, "size_change": "growing"},
  "user_language": "hi", "age_band": "45-60"
}
```

**Output:** a structured response with four fixed sections — *What the scan found* / *What this could mean* / *How urgent* (Red / Amber / Green) / *What to do now* — plus a conversational follow-up channel.

**Guard-rails (this is what makes it defensible and safe):**
- System prompt forbids the model from inventing a diagnosis, naming drugs, or contradicting the classifier.
- If CNN confidence < 0.60 → forced "uncertain, please see a dermatologist" template; the LLM only writes the explanation of *why* it's uncertain.
- Any malignant class → urgency is hard-coded to Red regardless of what the LLM says.
- Every response ends with a non-removable disclaimer.
- A regex/keyword post-filter blocks prescription-like output.

> **Why an 8B and not a 70B?** Cost, latency, and the fact that this task is explanation-and-formatting, not medical reasoning. The medical reasoning lives in the CNN and in the guard-rails. Say this in your review — examiners will ask.

---

## 3. Timeline — how long this actually takes

**Total: ~10 months across two semesters. Roughly 380–450 person-hours for a 4-member team (~95–110 h each, ~5–6 h/week).** That is a realistic, non-heroic load.

### Phase 1 — Fall 2026 (Aug → Dec) · *Design, data, models*

| Weeks | Dates (approx.) | Milestone | Review |
|---|---|---|---|
| 1–2 | Aug 5–18 | Team formed, Forms 1 & 2 submitted, guide approval, repos forked & running locally | **Review 0** |
| 3–5 | Aug 19 – Sep 8 | Literature review (25–30 papers, 2019–2026), dataset acquisition (HAM10000 + ISIC 2019), EDA, class-imbalance analysis | |
| 6–8 | Sep 9 – Sep 29 | Preprocessing pipeline, augmentation, baseline ResNet-50 multi-class trained, first confusion matrix | **Review 1** |
| 9–12 | Sep 30 – Oct 27 | EfficientNet-B0 comparison, hyperparameter tuning, confidence calibration, Grad-CAM working | |
| 13–15 | Oct 28 – Nov 17 | Qwen3-8B prompt engineering + guard-rail layer, standalone Python prototype (image in → full advice out) | **Review 2** |
| 16–18 | Nov 18 – Dec 8 | Phase-1 report, results tables, demo video | **Phase-1 Final** |

**Phase-1 deliverable:** *the pipeline works on a laptop.* Not the app. Do not let scope creep pull app work into Phase 1.

### Phase 2 — Winter 2027 (Jan → May) · *Product, evaluation, paper*

| Weeks | Milestone | Review |
|---|---|---|
| 1–3 | FastAPI backend, model served (TorchServe/ONNX), Qwen API integration, auth | |
| 4–6 | Flutter app rewired to new backend, new result UI with heat-map + explanation card | **Review 1** |
| 7–9 | Bilingual (EN/HI) support, offline/low-bandwidth mode, Maps + scan history | |
| 10–12 | Full evaluation: per-class F1, AUC-ROC, malignant sensitivity, latency; human rubric evaluation of 100 LLM explanations (3 raters) | **Review 2** |
| 13–16 | Paper draft + submission, final report, thesis defence | **Final** |

### Time breakdown by activity

| Activity | Hours |
|---|---|
| Literature review + report writing | 90 |
| Data collection, cleaning, EDA | 45 |
| Model training + tuning (the GPU waits are long, the work is short) | 80 |
| LLM prompt engineering + guard-rails | 55 |
| Backend + API | 50 |
| Flutter app modification | 60 |
| Evaluation study + paper | 60 |

---

## 4. What to do *right now* (next 14 days)

Ordered. Do them in this order.

**Week 1 — administrative & setup**
1. **Finalise the team** (4 members recommended, 5 max) and fill the blanks in Form 1 & Form 2 — the placeholder fields are marked `<Member 2 Name>` etc.
2. **Get a guide.** Approach a faculty member working in medical imaging / deep learning. Take the filled Form 1 with you. Their signature is what unblocks everything else.
3. **Register on the ISIC Archive** and start the **HAM10000** download (Harvard Dataverse, ~2.6 GB, free) and **ISIC 2019** (~25 GB). Downloads are slow — start them today, they are not blocking work but they gate week 3.
4. **Fork and run both inherited repos.** Confirm the APK builds and the existing model actually loads. If the ML repo is unusable, you need to know in week 1, not week 6.
5. **Create a shared GitHub org** with two repos: `scan4disease-ml`, `scan4disease-app`. Add your guide as a collaborator.

**Week 2 — technical de-risking**
6. **Install Ollama and run `ollama pull qwen3:8b`**, then test 10 hand-written prompts locally. Verify Hindi output quality before you commit to it in the report. No API key, no card, unlimited calls. *(Newer Qwen 3.6/3.8 small models exist — try them if the 8B disappoints, but 8B is the safe default that fits your VRAM.)*
7. **Train a throwaway baseline** — ResNet-50, HAM10000, 10 epochs, no tuning. Whatever accuracy you get is your floor. This single number makes Review 0/1 go smoothly.
8. **Write the Review 0 deck** (12–15 slides): problem, gap in prior work, proposed 2-model architecture, datasets, timeline, expected outcome.
9. **Book GPU access** with the AI lab — find out the queue policy now, not in October.

**Two things not to do:** don't touch the Flutter app before December, and don't try to fine-tune Qwen. Prompt engineering will get you 90% of the value at 2% of the cost, and fine-tuning an 8B model is a separate MP online by itself.

---

## 5. Hardware requirements

### A. Development / training (what *you* need)

| Component | Minimum | Recommended | Notes |
|---|---|---|---|
| GPU (training) | Kaggle Notebooks — 30 GPU-h/week free | **Your ASUS ROG Strix G16 (RTX 40/50-series)** | ResNet-50 @ 224×224, batch 32 fits in 8 GB. EfficientNet-B0 fits in 6 GB. A 30-epoch HAM10000 run: ~25–50 min on your laptop, ~2.5 h on a free T4, ~8 h on CPU. |
| CPU | 4-core i5 / Ryzen 5 | 8-core i7 / Ryzen 7 | Data loading is the bottleneck on Colab |
| RAM | 8 GB | 16–32 GB | ISIC 2019 augmentation pipelines are memory-hungry |
| Storage | 60 GB free | 250 GB SSD | HAM10000 2.6 GB + ISIC 2019 ~25 GB + checkpoints (~100 MB each × many) |
| Android test device | Any Android 8+ phone | Android 11+, 4 GB RAM, 8 MP AF camera | You need at least two different phones to test camera variance |
| Internet | 10 Mbps | 50 Mbps | Dataset downloads |

**Qwen3-8B runs locally on the same GPU**, 4-bit quantised via Ollama (~5.2 GB VRAM). An 8 GB card runs it alongside development comfortably; a 6 GB RTX 4050 should use `qwen3:4b` while developing and switch to 8B for the demo. Do not train and run the LLM simultaneously — you'll run out of VRAM.

### B. End-user device (goes in your report's requirements chapter)

| Component | Minimum | Recommended |
|---|---|---|
| Android | 8.0 (API 26) | 11.0+ |
| RAM | 3 GB | 4 GB+ |
| Storage | 150 MB | 250 MB |
| Camera | 8 MP autofocus | 12 MP + flash + AF |
| Network | 3G (results in ~8–15 s) | 4G/WiFi (~2–4 s) |
| Offline mode | On-device TFLite classifier only, no LLM explanation | — |

### C. Server / cloud (Phase 2)

| Resource | Free option | Purpose |
|---|---|---|
| Backend | **Hugging Face Spaces** — free CPU, 2 vCPU / 16 GB, always on, no card | FastAPI, image handling, orchestration |
| Inference | Same Space, CPU-only, ONNX Runtime | ResNet-50 CPU inference ≈ 200–400 ms — no GPU needed in production |
| Object storage | On-device only (free + privacy win); Firebase Storage 5 GB free if cloud is required | User images |
| Database | Firebase Spark plan (free) or Supabase free tier | Users, scan history |
| LLM | **Ollama + Qwen3-8B on your laptop**, exposed via free Cloudflare Tunnel for demos | Explanation layer |
| Maps | OpenStreetMap + `flutter_map` + Overpass API — keyless, quota-free | Nearest clinic |

---

## 6. Software requirements

### Training & ML

```
Python 3.11
PyTorch 2.x + torchvision        # primary framework
timm                             # pretrained ResNet/EfficientNet backbones
albumentations                   # augmentation (blur, rotation, colour jitter)
scikit-learn                     # metrics, calibration, stratified splits
pytorch-grad-cam                 # explainability heat-maps
numpy · pandas · matplotlib · seaborn
opencv-python                    # image QC gate
onnx · onnxruntime               # export for CPU serving
tensorflow + tflite (optional)   # only if you do on-device offline mode
Weights & Biases or TensorBoard  # experiment tracking — use one, examiners love the plots
```

### LLM layer

```
ollama                # runs Qwen3-8B locally, free, unlimited  →  ollama pull qwen3:8b
openai (SDK)          # Ollama exposes an OpenAI-compatible endpoint at localhost:11434/v1
pydantic              # enforce structured LLM output schema
tenacity              # retries/backoff
```

### Backend

```
FastAPI + Uvicorn
Pillow
python-jose / firebase-admin     # auth
redis (optional)                 # response caching
```

### Mobile

```
Flutter 3.x + Dart
camera · image_picker · dio (HTTP)
firebase_auth · firebase_storage
flutter_map + latlong2          # OpenStreetMap — free, keyless (avoid google_maps_flutter, needs billing)
flutter_localizations            # EN/HI
tflite_flutter                   # offline mode only
```

### Tooling

Git + GitHub · VS Code / Android Studio · Jupyter, Kaggle or Colab · Postman · Overleaf (paper) · Figma (UI mockups) — **all used on free tiers, no card required.** Full free-replacement table in `Zero-Cost Setup.md`.

### Datasets (all free, all citable)

| Dataset | Size | Use |
|---|---|---|
| **HAM10000** | 10,015 images, 7 classes | Primary training set |
| **ISIC 2019** | 25,331 images, 8 classes | Scale-up + external validation |
| ISIC 2016/2017 | small | Held-out test (prior work used this — good for direct comparison) |
| PAD-UFES-20 | 2,298 smartphone images | **Important** — real phone photos, not dermoscopy. Your app takes phone photos; validating only on dermoscopy is the #1 criticism examiners raise. |
| Fitzpatrick17k | 16,577 images | Skin-tone fairness analysis — a strong, easy differentiator |

### Cost: ₹0

Qwen3-8B runs **locally via Ollama** on your RTX GPU (4-bit, ~5.2 GB VRAM) — unlimited calls, no API key, no credit card. Hosting is Hugging Face Spaces (free CPU), auth is Firebase Spark (free), maps are OpenStreetMap (free, keyless), datasets are free. See `Zero-Cost Setup.md` for the full free-replacement table and the Ollama commands.

Running locally is also a *stronger* design choice than a paid API — patient images never leave the device, there is no per-scan cost for a free app, and it works without reliable internet. Argue it that way in the report.

*(For reference only, if you ever needed the paid route: Qwen3-8B on OpenRouter is ~$0.117/M input and $0.455/M output tokens ≈ $0.00025 per scan. You don't need it.)*

---

## 7. Risks and how to kill them early

| Risk | Likelihood | Mitigation |
|---|---|---|
| Class imbalance destroys malignant recall (NV is 67% of HAM10000) | High | Class-weighted loss + focal loss + oversampling; **report per-class recall, never bare accuracy** |
| Dermoscopy-trained model fails on phone photos | High | Validate on PAD-UFES-20; add an image-quality gate; state the limitation honestly |
| LLM hallucinates medical advice | Medium | Structured output schema + guard-rail post-filter + human rubric evaluation (this evaluation *is* a paper contribution) |
| Team member drops off | Medium | Assign clearly separable ownership: ML / LLM+backend / app / eval+writing |
| Ethics or data-privacy objection at review | Medium | Write a one-page ethics note now: no PII, on-device deletion option, explicit "not a medical device" positioning |
| Laptop GPU unavailable or fails | Medium | Kaggle Notebooks give 30 free GPU-hours/week — set up the account in week 2 as insurance, don't wait until it breaks |

---

## 8. Expected deliverables

1. Working Android app (APK) with multi-class classification + LLM explanation
2. Trained model weights + reproducible training code (GitHub)
3. Evaluation report: per-class F1, AUC-ROC, malignant sensitivity, confusion matrices, ablation (with vs without LLM layer)
4. Human evaluation study of explanation quality (n≈100, 3 raters, Cohen's κ)
5. Phase-1 and Phase-2 reports + review decks
6. Conference paper draft (target: an IEEE conference on computing/healthcare informatics)

---

## 9. Suggested role split (4 members)

| Role | Owns |
|---|---|
| **ML lead** | Datasets, training, tuning, Grad-CAM, all vision metrics |
| **LLM + backend lead** | Prompt design, guard-rails, FastAPI, model serving, API integration |
| **App lead** | Flutter rewiring, new UI, localisation, offline mode, device testing |
| **Evaluation + docs lead** | Literature review, human eval study, reports, decks, paper |

Everyone reviews everyone's code. The evaluation lead should be involved from week 1, not bolted on at the end — that is the most common failure mode in MP online projects.

---

*Sources for API pricing: [OpenRouter — Qwen3 8B](https://openrouter.ai/qwen/qwen3-8b), [Qwen3 8B API Pricing 2026](https://pricepertoken.com/pricing-page/model/qwen-qwen3-8b)*

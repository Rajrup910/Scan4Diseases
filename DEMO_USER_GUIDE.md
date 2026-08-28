<div align="center">

# Scan4Disease — System Showcase, Testing & Presentation Guide
### *AI-Assisted Dermatology Screening & Clinician Decision-Support Platform*

[![FastAPI](https://img.shields.io/badge/FastAPI-0.111.0-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.3.0-EE4C2C?style=flat-square&logo=pytorch&logoColor=white)](https://pytorch.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.19.0-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Render Cloud](https://img.shields.io/badge/Render-Cloud%20Deployed-46E3B7?style=flat-square&logo=render&logoColor=white)](https://render.com)
[![Zero-Knowledge Encryption](https://img.shields.io/badge/Security-Fernet%20Encrypted-blueviolet?style=flat-square)](#data-privacy-and-encryption-architecture)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

<br/>

**Scan4Disease** is an end-to-end dermatological screening system that bridges patient-centric mobile triage with a specialist web portal. Powered by deep convolutional neural networks (ResNet-50 / EfficientNet-B0), deterministic clinical safety rules, Explainable AI (Grad-CAM), and cloud LLM services (Groq API: `openai/gpt-oss-120b`), it offers safe, auditable, and bilingual early detection support.

---

[Project Overview](#1-project-overview--multi-stage-safety-architecture) • [ML Architecture & Benchmarks](#2-machine-learning-architecture-classification-taxonomy--empirical-benchmarks) • [Cloud Deployment & Access](#3-cloud-backend-deployment--live-access) • [Download Android App](#4-official-android-application-distribution--apk-downloads-github-releases) • [Credentials Directory](#5-demo-credentials--access-directory) • [Benchmark Test Cases](#6-five-curated-test-photos-across-lesion-criteria) • [Technical Reference](#7-technical-reference--troubleshooting) • [Web Portal Showcase](#8-clinician-web-portal---visual-showcase-light--dark-mode) • [Mobile App Showcase](#9-mobile-application---visual-showcase-light--dark-mode)

---

</div>

> [!IMPORTANT]
> **Clinical Safety & Regulatory Notice**: Scan4Disease is an educational screening and decision-support platform, **not an autonomous diagnostic medical device**. It strictly decouples visual feature extraction from clinical urgency determination and never provides an unreviewed final medical diagnosis. Every screening result recommends consultation with a licensed dermatologist.

---

## 1. Project Overview & Multi-Stage Safety Architecture

Cutaneous malignancies (Melanoma, Basal Cell Carcinoma, Squamous Cell Carcinoma) represent a severe global health burden where early intervention drastically alters patient survival rates. Scan4Disease implements a **Five-Stage Tripartite Defense Architecture** ensuring that non-deterministic language models never modify medical urgency.

```
                           ┌──────────────────────────────┐
                           │   PATIENT MOBILE APP / WEB   │
                           └──────────────┬───────────────┘
                                          │ HTTPS (Cloud on Render)
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          FASTAPI BACKEND ARCHITECTURE                           │
│                                                                                 │
│   1. FRONT-STAGE ROUTER & OOD GATE (Mahalanobis Distance)                       │
│      Rejects non-skin objects, healthy skin & abrasions (OTHER_DAMAGE)          │
│                                         │                                       │
│   2. IMAGE QUALITY GATE                 ▼                                       │
│      Validates Laplacian blur, underexposure & overexposure                     │
│                                         │                                       │
│   3. DEEP CNN CLASSIFIER (ResNet-50)    ▼                                       │
│      Extracts 7 ISIC multiclass probabilities & computes Grad-CAM Heatmap       │
│                                         │                                       │
│   4. DETERMINISTIC CLINICAL TRIAGE RULES (Auditable Python Engine)              │
│      Evaluates symptoms + AI scores -> Decides Urgency (Red / Amber / Green)    │
│                                         │                                       │
│   5. CONTEXT-AWARE LLM & SAFETY FILTER (Groq API: openai/gpt-oss-120b)          │
│      Translates explanation to English/Hindi; blocked from diagnosing           │
└─────────────────────────────────────────┬───────────────────────────────────────┘
                                          │
                                          ▼
                      ┌────────────────────────────────────────┐
                      │  CLINICIAN WEB PORTAL (DOCTOR-IN-LOOP) │
                      │  • Zero-Knowledge Fernet Decryption    │
                      │  • Dual-Image Pan/Zoom + Grad-CAM XAI  │
                      │  • Audit Trail & Appointment Scheduler │
                      └────────────────────────────────────────┘
```

### Core Architectural Principles
1. **Deterministic Triage Layer**: Visual feature probabilities from the CNN are evaluated by nine deterministic Python rules (e.g. `R1_malignant_class`, `R3_malignant_mass_high`) alongside patient-reported symptoms. The language model only translates the finalized clinical output into layman prose.
2. **Explainable AI (Grad-CAM)**: An implementation of Gradient-weighted Class Activation Mapping computes pixel-level activation gradients, verifying whether the model focused on morphological lesion borders rather than peripheral skin artifacts.
3. **Zero-Knowledge Privacy Vault**: Screening images remain in-memory during inference and are discarded immediately after processing. Persisted storage occurs only when a patient explicitly shares a report with a verified clinician, encrypting the image with symmetric Fernet keys at rest.
4. **Front-Stage OOD Defense**: Rejects scratches, wounds, and non-dermatological inputs (`OTHER_DAMAGE`), preventing false-positive malignant alerts on superficial trauma.

---

## 2. Machine Learning Architecture, Classification Taxonomy & Empirical Benchmarks

Scan4Disease deploys a deep convolutional vision pipeline backed by rigorous, leakage-free evaluation, domain-adaptation analysis, explainability audits, and deterministic clinical safety constraints. Every statistic quoted below was produced by `ml/evaluation/evaluate.py` on a held-out, lesion-grouped test split.

---

### 2.1 Deployed Classifier & Transfer Learning Schedule

The primary deployed model is **ResNet-50** (`resnet50_best.pt`), pretrained on ImageNet-1K and fine-tuned across a two-stage training schedule:

* **Stage 1 (Linear Probing / Feature Extraction)**: Convolutional backbone weights remain frozen while the fully connected classification head (`fc`, 2048 -> 7 logits) is trained with AdamW (learning rate = `1e-3`, weight decay = `1e-2`) for 5 epochs.
* **Stage 2 (Full Backbone Fine-Tuning)**: The entire network is unfrozen and trained end-to-end at a lower learning rate (`1e-4`) with cosine annealing learning rate decay and early stopping on validation balanced accuracy.
* **Class Imbalance Mitigation**: Cross-entropy loss is weighted using the **Effective Number of Samples** formulation ($E_n = (1 - \beta) / (1 - \beta^n)$, with $\beta = 0.9999$), preventing the dominant class (`nv`, 66.9% of HAM10000) from suppressing rare malignant classes (`mel`, `bcc`, `akiec`).
* **Input Preprocessing Transform**:
  * Bilinear resize to 256x256 pixels -> Center crop to 224x224 pixels.
  * ImageNet channel normalization: mean = `[0.485, 0.456, 0.406]`, std = `[0.229, 0.224, 0.225]`.
  * Evaluated through bit-identical parity assertions (`tests/test_parity.py`) between the training framework and production FastAPI runtime.

---

### 2.2 7-Class ISIC Diagnostic Taxonomy & Malignancy Tiers

The label space corresponds strictly to the 7 distinct clinical diagnostic classes of the International Skin Imaging Collaboration (ISIC / HAM10000 `dx` metadata), mapped into three clinically actionable malignancy tiers (`ml/configs/class_mapping.json`):

| Index | Code | Medical Diagnosis (English / Hindi) | Malignancy Tier | ISIC Code | Clinical Description |
|---|---|---|---|---|---|
| **0** | `akiec` | Actinic Keratosis / Intraepithelial Carcinoma<br/>*एक्टिनिक केराटोसिस / इंट्राएपिथेलियल कार्सिनोमा* | **Pre-malignant** | `AK` | Rough, scaly sun-induced keratotic plaque; potential precursor to invasive squamous cell carcinoma. |
| **1** | `bcc` | Basal Cell Carcinoma<br/>*बेसल सेल कार्सिनोमा* | **Malignant** | `BCC` | Common malignant non-melanoma carcinoma with translucent pearly borders and branching telangiectasia. |
| **2** | `bkl` | Benign Keratosis-like Lesion<br/>*सौम्य केराटोसिस* | **Benign** | `BKL` | Non-cancerous solar lentigo, seborrheic keratosis, or lichen-planus-like keratosis. |
| **3** | `df` | Dermatofibroma<br/>*डर्मेटोफाइब्रोमा* | **Benign** | `DF` | Harmless, firm dermal histiocytoma nodule resulting from benign local tissue proliferation. |
| **4** | `mel` | Melanoma (Malignant Cutaneous Melanoma)<br/>*घातक मेलेनोमा* | **Malignant** | `MEL` | Highly aggressive cutaneous malignancy arising from pigment-producing melanocytes; requires urgent excision. |
| **5** | `nv` | Melanocytic Nevus (Common Mole)<br/>*तिल / मेलानोसाइटिक नेवस* | **Benign** | `NV` | Common benign proliferation of melanocytes with regular, symmetric architectural borders. |
| **6** | `vasc` | Vascular Lesion (Angioma / Pyogenic Granuloma)<br/>*संवहनी घाव (एंजियोमा)* | **Benign** | `VASC` | Benign vascular malformation, cherry angioma, or hemorrhage pattern. |

---

### 2.3 Empirical Evaluation Metrics on Held-Out HAM10000 Test Split

All performance metrics and diagnostic accuracies are measured on the **held-out 15% test split (1,502 dermoscopy images)** of the **HAM10000 dataset** (*Human Against Machine with 10,000 training images*, Tschandl et al., ISIC Archive; 10,015 total images across 7,470 lesions). The split is strictly grouped by `lesion_id` to guarantee zero data leakage (since 44.9% of HAM10000 images represent multi-photograph series of the same physical lesion):

#### Overall HAM10000 Test Set Performance (1,502 Images)

| Evaluation Metric | Dataset | Test Value | Clinical Significance |
|---|---|---|---|
| **Overall Accuracy** | **HAM10000 (Dermoscopy)** | **82.2%** (0.822) | Total correct predictions over 1,502 held-out HAM10000 dermoscopy test cases. |
| **Macro-Averaged F1** | **HAM10000 (Dermoscopy)** | **0.706** | Unweighted average across all 7 classes; prevents dominant classes from masking minority performance. |
| **Balanced Accuracy** | **HAM10000 (Dermoscopy)** | **0.722** | Arithmetic mean of recall across all 7 diagnostic categories. |
| **Weighted F1** | **HAM10000 (Dermoscopy)** | **0.823** | Support-weighted harmonic precision-recall score. |
| **Cohen's Kappa ($\kappa$)** | **HAM10000 (Dermoscopy)** | **0.664** | Substantial inter-rater agreement beyond chance ($> 0.60$ threshold). |
| **Macro ROC-AUC** | **HAM10000 (Dermoscopy)** | **0.945** | Multi-class area under the Receiver Operating Characteristic curve. |
| **Expected Calibration Error (ECE)** | **HAM10000 (Dermoscopy)** | **0.101** | Reliability of softmax probabilities vs true empirical likelihood. |
| **Escalation Sensitivity** | **HAM10000 (Dermoscopy)** | **0.738** | Combined detection rate for urgent malignant (`mel`, `bcc`) and pre-malignant (`akiec`) cases. |

#### Per-Class Diagnostic Breakdown (HAM10000 Test Split)

| Class Code | Diagnostic Category | Malignancy | Precision | Recall (Sensitivity) | F1-Score | HAM10000 Test Support |
|---|---|---|---|---|---|---|
| `akiec` | Actinic keratosis / Intraepithelial Carcinoma | Pre-malignant | 0.481 | **0.750** | 0.587 | 52 images |
| `bcc` | Basal cell carcinoma | Malignant | 0.709 | **0.789** | 0.747 | 71 images |
| `bkl` | Benign keratosis-like lesion | Benign | 0.689 | 0.611 | 0.648 | 167 images |
| `df` | Dermatofibroma | Benign | 0.762 | **0.800** | 0.780 | 20 images |
| `mel` | Malignant melanoma | Malignant | 0.589 | **0.575** | 0.582 | 167 images |
| `nv` | Melanocytic nevus (Common mole) | Benign | 0.918 | **0.908** | 0.913 | 1,004 images |
| `vasc` | Vascular lesion | Benign | 0.765 | 0.619 | 0.684 | 21 images |

---

### 2.4 Dermoscopy vs Smartphone Domain Gap Analysis (HAM10000 vs. PAD-UFES-20)

To evaluate real-world camera generalizability, identical ResNet-50 architectures were trained independently on dermoscopy data (**HAM10000**, 10,015 images) and clinical smartphone camera photos (**PAD-UFES-20**, 2,106 usable images / 1,746 lesions):

| Evaluation Configuration | Training Dataset | Evaluation / Test Dataset | Macro-F1 | Balanced Acc | Test Accuracy | Escalation Sensitivity | Melanoma Recall |
|---|---|---|---|---|---|---|---|
| **HAM Model on HAM (In-Domain Dermoscopy)** | **HAM10000** (10,015 img) | **HAM10000 Test** (1,502 dermoscopy img) | **0.706** | **0.722** | **82.2%** (0.822) | **0.738** | **0.575** |
| **HAM Model on PAD (Cross-Domain Smartphone)** | **HAM10000** (10,015 img) | **PAD-UFES-20 Test** (314 smartphone img) | **0.142** | **0.270** | **24.5%** (0.245) | **0.389** | **0.000** |
| **PAD Model on PAD (In-Domain Smartphone)** | **PAD-UFES-20** (2,106 img) | **PAD-UFES-20 Test** (314 smartphone img) | **0.661** *(5-class)* | **0.658** | **76.4%** (0.764) | **0.939** | **0.250** |

> [!IMPORTANT]
> **Domain Gap Finding**: When a pure dermoscopy-trained neural network is evaluated on smartphone camera photos, melanoma recall drops to **0.00** and escalation sensitivity plummets from **0.738** to **0.389**. This empirical gap justifies Scan4Disease's multi-stage quality gate, front-stage lesion router, and dedicated domain-adaptation mechanisms.

---

### 2.5 Multi-Stage Quality Gate & Front-Stage OOD Defense Router

Before sending an image to the 7-class disease classifier, the backend enforces a three-stage defense:

```
Raw Image Upload
       │
       ▼
┌────────────────────────────────────────────────────────┐
│ STAGE 1: IMAGE QUALITY GATE (quality.py)               │
│ • Laplacian blur variance filter                       │
│ • Luminance checks: Underexposed (<40) / Blown (>220)  │
│ • Minimum resolution verification (>= 224x224)         │
└──────────────────────────┬─────────────────────────────┘
                           │ Passed
                           ▼
┌────────────────────────────────────────────────────────┐
│ STAGE 2: FRONT-STAGE ROUTER (lesion_router.py)         │
│ • Operates on 2048-dim penultimate ResNet-50 features  │
│ • 4-Way Softmax: [lesion, healthy, not_skin, wound]   │
│ • High-Recall Lesion Gate: Passes ~98% of true lesions │
└──────────────────────────┬─────────────────────────────┘
                           │ Routed as 'lesion'
                           ▼
┌────────────────────────────────────────────────────────┐
│ STAGE 3: MAHALANOBIS FAR-OOD GATE (ood.py)             │
│ • Minimum Mahalanobis distance to class feature means  │
│ • Rejects non-dermatological inputs & random artifacts │
└──────────────────────────┬─────────────────────────────┘
                           │ Validated
                           ▼
              7-Class Disease Classifier
```

* **Trauma / Wound Defense (`OTHER_DAMAGE`)**: Mechanical scratches, abrasions, and superficial wounds are classified as `other_damage` by the front-stage router, routing users to wound cleanliness advice rather than generating false-positive melanoma alerts.

---

### 2.6 Explainable AI Engine: First-Principles Grad-CAM with Border-Mass Audit

The Explainable AI module is implemented from first principles in PyTorch ([`backend/app/services/gradcam.py`](file:///c:/Users/RAJ/Downloads/Capstone/backend/app/services/gradcam.py)) without black-box third-party dependencies:

1. **Target Layer**: Captures spatial activations $A^k \in \mathbb{R}^{7 \times 7}$ from the final convolutional block of ResNet-50 (`model.layer4[-1]`).
2. **Channel-Wise Importance Weights**:
   $$\alpha_k^c = \frac{1}{Z} \sum_{i=1}^7 \sum_{j=1}^7 \frac{\partial y^c}{\partial A_{i,j}^k}$$
3. **Rectified Linear Combination**:
   $$L_{\text{Grad-CAM}}^c = \text{ReLU}\left(\sum_k \alpha_k^c A^k\right)$$
4. **Border-Mass Quality Self-Audit**:
   * Computes the fraction of total activation energy located within the outer 15% image border (`border_mass_fraction`).
   * If `border_mass_fraction > 0.50`, the heatmap is flagged for clinician review to ensure the network is not anchoring on circular dermatoscope vignetting, hair, surgical ink, or measurement rulers.

---

### 2.7 Deterministic Clinical Triage Rule Engine

Medical urgency is determined by a pure, deterministic Python engine ([`backend/app/services/triage.py`](file:///c:/Users/RAJ/Downloads/Capstone/backend/app/services/triage.py)). Non-deterministic language models are completely isolated from urgency calculations:

```
CNN Probabilities + Patient Anamnesis Survey
                     │
                     ▼
┌────────────────────────────────────────────────────────┐
│ DETERMINISTIC TRIAGE RULES ENGINE (triage.py)          │
│                                                        │
│ R1: Top-1 is 'mel' or 'bcc'               ──► URGENT   │
│ R2: Top-1 is 'akiec'                      ──► PROMPT   │
│ R3: Σ P(mel, bcc) >= 0.40                 ──► URGENT   │
│ R4: Σ P(mel, bcc) >= 0.20                 ──► PROMPT   │
│ R4b: P(akiec) >= 0.20                     ──► PROMPT   │
│ R5: Top-1 confidence < 0.60               ──► PROMPT   │
│ R6: >= 3 symptom red flags                ──► URGENT   │
│ R7: >= 1 symptom red flag                 ──► PROMPT   │
│ R8: Spontaneous unprovoked bleeding       ──► URGENT   │
│ R9: None of the above fired               ──► ROUTINE  │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
          Final Urgency (Red / Amber / Green)
                           │
                           ▼
      Context-Aware LLM Translator (Groq API: openai/gpt-oss-120b)
         (Bilingual prose explanation only)
```

* **Escalation Monotonicity Invariant**: Rules can only elevate urgency. A user answering "no" to all symptoms can never downgrade an urgent malignant CNN prediction.
* **Probability Mass Safety**: If a lesion is predicted as 45% `nv` (benign) but carries 42% `mel` (malignant), Rule `R3` triggers immediately, classifying the case as **Urgent**.

---

### 2.8 Architecture Comparison Matrix (HAM10000 Held-Out Test Split)

Across benchmarked vision backbones evaluated on the **HAM10000 held-out test split (1,502 images)**, ResNet-50 was selected for deployment due to its optimal balance of Macro-F1, stable 2048-dimensional penultimate features for OOD routing, and spatial fidelity for Grad-CAM:

| Backbone Architecture | Benchmark Dataset | Parameters | Input Resolution | Macro-F1 | Balanced Acc | Test Accuracy | Inference Latency (CPU) |
|---|---|---|---|---|---|---|---|
| **ResNet-50 (Deployed)** | **HAM10000 Test (1,502 img)** | **25.6 M** | **224x224** | **0.706** | **0.722** | **82.2%** | **~16 ms** |
| **EfficientNet-B3** | **HAM10000 Test (1,502 img)** | 12.2 M | 300x300 | 0.701 | 0.718 | 81.8% | ~28 ms |
| **DenseNet-121** | **HAM10000 Test (1,502 img)** | 8.0 M | 224x224 | 0.698 | 0.714 | 81.5% | ~22 ms |
| **ConvNeXt-Tiny** | **HAM10000 Test (1,502 img)** | 28.6 M | 224x224 | 0.692 | 0.709 | 80.9% | ~24 ms |
| **EfficientNet-B0** | **HAM10000 Test (1,502 img)** | 5.3 M | 224x224 | 0.684 | 0.695 | 80.1% | ~12 ms |

---

### 2.9 Cloud-Hosted LLM Service & Safety Isolation (Groq API: `openai/gpt-oss-120b`)

Scan4Disease utilizes a hosted cloud LLM endpoint powered by **Groq Cloud API** for high-throughput, low-latency bilingual generation:

* **Inference Provider & Endpoint**: **Groq Cloud API** (`https://api.groq.com/openai/v1`) using dedicated LPU hardware for sub-second inference.
* **Production Model**: `openai/gpt-oss-120b` (`LLM_MODEL`).
* **Runtime Hyperparameters**:
  * `LLM_TEMPERATURE`: `0.3` (conservative setting ensuring factual, grounded explanations without creative drift).
  * `LLM_MAX_TOKENS`: `700` tokens per completion.
  * `LLM_TIMEOUT_SECONDS`: `30.0`s client timeout.
  * `LLM_RATE_LIMIT_RPM`: `10` requests/minute (sliding-window rate limiter protecting paid API quotas).
* **Deterministic Safety Decoupling**:
  * **Strictly Non-Diagnostic**: The LLM never computes or influences medical triage urgency. Urgency is calculated exclusively upstream by the auditable Python triage engine (`triage.py`).
  * **Output Safety Filter (`backend/app/safety/filters.py`)**: All completions pass through deterministic post-processing filters that automatically redact or block unverified prescription suggestions, definitive diagnosis claims, and false reassurance.
  * **Fault-Tolerant Fallback**: If the API key is exhausted or the cloud service is unreachable, `/predict` continues to operate with 100% functionality (classification, Grad-CAM, and deterministic triage advice remain intact with `explanation_available: false`).

---

## 3. Cloud Backend Deployment & Live Access

The backend service is containerized and hosted on **Render Cloud**, providing persistent HTTPS access without requiring local device port forwarding or USB bridging.

* **Production Backend URL**: `https://scan4diseases.onrender.com` *(or local development at `http://localhost:8000`)*
* **Clinician Web Portal**: `https://scan4diseases.onrender.com/portal/login` *(or `http://localhost:8000/portal/login`)*
* **Interactive API Documentation (Swagger)**: `https://scan4diseases.onrender.com/docs`
* **Health & Diagnostics Endpoint**: `https://scan4diseases.onrender.com/health`

---

## 4. Official Android Application Distribution & APK Downloads (GitHub Releases)

The official **Scan4Diseases** Android mobile application is distributed directly to clinicians, evaluators, and patients through **GitHub Releases**. This provides transparent version tracking, tamper-resistant binary distribution, and persistent access to the latest stable build.

### User-Facing Flow

The distribution workflow follows a streamlined, direct path:

**`Download Android App`** -> **`GitHub Releases`** -> **`Latest Release`** -> **`APK Asset Download`**

```
┌─────────────────────────┐     ┌─────────────────────────┐     ┌────────────────────────┐     ┌───────────────────────┐
│  Download Android App   │ ──► │  GitHub Releases Page   │ ──► │     Latest Release     │ ──► │   Download & Install  │
│  (Website / Docs Link)  │     │  (Scan4Diseases Repo)   │     │ (v1.0.0 Stable Build)  │     │      APK Binary       │
└─────────────────────────┘     └─────────────────────────┘     └────────────────────────┘     └───────────────────────┘
```

---

### Direct Download Destination

* **Permanent Latest Release Link**: [https://github.com/Rajrup910/Scan4Diseases/releases/latest](https://github.com/Rajrup910/Scan4Diseases/releases/latest)
* **All Releases & Version History**: [https://github.com/Rajrup910/Scan4Diseases/releases](https://github.com/Rajrup910/Scan4Diseases/releases)
* **Project GitHub Repository**: [https://github.com/Rajrup910/Scan4Diseases](https://github.com/Rajrup910/Scan4Diseases)

> [!NOTE]
> **Permanent URL Behavior**: The `/releases/latest` endpoint is GitHub's official permanent destination that automatically resolves to the most recent published stable release. You **never need to change external website or documentation links** when releasing new updates (`v1.1.0`, `v2.0.0`, etc.).

---

### Copy-Ready Website & Landing Page Buttons

You can embed the following ready-to-use snippets into your website, portal header, or landing page:

#### Option A: Shield Badge CTA (Markdown)
```markdown
[![Download Android APK](https://img.shields.io/badge/Download-Android%20APK-0284c7?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Rajrup910/Scan4Diseases/releases/latest)
```

#### Option B: Modern Styled Button (HTML / CSS)
```html
<!-- Copy & paste into your website landing page, hero section, or navigation bar -->
<a href="https://github.com/Rajrup910/Scan4Diseases/releases/latest" 
   target="_blank" 
   rel="noopener noreferrer" 
   class="btn-apk-download"
   style="display: inline-flex; align-items: center; gap: 10px; padding: 12px 24px; background: linear-gradient(135deg, #0284c7 0%, #0369a1 100%); color: #ffffff; font-weight: 600; font-family: system-ui, -apple-system, sans-serif; font-size: 15px; text-decoration: none; border-radius: 10px; box-shadow: 0 4px 14px rgba(2, 132, 199, 0.35); transition: all 0.2s ease;">
  <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M17.523 15.3414c-.5511 0-.9993-.4486-.9993-.9997s.4482-.9993.9993-.9993c.551 0 .9993.4482.9993.9993.0001.5511-.4483.9997-.9993.9997m-11.046 0c-.5511 0-.9993-.4486-.9993-.9997s.4482-.9993.9993-.9993c.5511 0 .9993.4482.9993.9993 0 .5511-.4482.9997-.9993.9997m11.4045-6.02l1.996-3.4572c.1556-.2696.0633-.6138-.2063-.7694-.2691-.1556-.6133-.0633-.7689.2063l-2.0223 3.5028C15.346 8.2434 13.7225 7.9174 12 7.9174c-1.7225 0-3.346.326-4.8805.8865L5.0972 5.3011c-.1556-.2696-.4998-.3619-.7689-.2063-.2696.1556-.3619.4998-.2063.7694l1.996 3.4572C2.6885 11.1706.3435 14.8624.3435 19.1667h23.313c0-4.3043-2.345-7.9961-5.775-9.8453"/>
  </svg>
  <span>Download Android App</span>
</a>
```

---

### Android Sideloading Notice: "Install from Unknown Source"

Because Scan4Diseases is distributed directly via GitHub Releases outside Google Play:

1. **Browser Download Warning**: When downloading in Chrome or mobile browsers, Android may show:
   > *"File might be harmful. Do you want to download Scan4Diseases-v1.0.0.apk anyway?"*  
   - Tap **Download anyway**.
2. **First-Time Install Permission**: When opening the downloaded APK, Android may display:
   > *"For your security, your phone is not allowed to install unknown apps from this source."*  
   - Tap **Settings** -> Toggle **Allow from this source** (or *Install unknown apps*) to **On** -> Return to the installer and tap **Install**.
3. **Play Protect Verification**: If Google Play Protect displays an *"Unrecognized app"* advisory:
   - Tap **More details** -> **Install anyway**.

---

### Release Versioning & APK Naming Standards

All published artifacts adhere to semantic versioning (`vMAJOR.MINOR.PATCH`):

| Release Tag | Release Title | Target APK Filename | Distribution Status | Description & Capabilities |
|---|---|---|---|---|
| `v1.0.0` | `Scan4Diseases v1.0.0 — Production Release` | `Scan4Diseases-v1.0.0.apk` | **Initial Release** | Production build with 7-class CNN, Grad-CAM, offline skin guide, triage rules, and clinician portal sync. |
| `v1.1.0` | `Scan4Diseases v1.1.0 — Incremental Update` | `Scan4Diseases-v1.1.0.apk` | *Planned* | Enhanced anamnesis questionnaire, additional regional language packs, and offline caching. |
| `v2.0.0` | `Scan4Diseases v2.0.0 — Major Upgrade` | `Scan4Diseases-v2.0.0.apk` | *Planned* | Longitudinal patient tracking, dermoscopic hardware camera integration, and multi-hospital federation. |

---

### Build Requirements: Signed Release Build (Not Debug)

> [!IMPORTANT]
> **Maintainer Requirement**: **Never upload a debug build (`app-debug.apk`) to GitHub Releases.**
> * Debug APKs have unoptimized JIT runtimes, large binaries (~60MB+), disabled tree-shaking / R8 optimization, and security flags open.
> * Always generate a signed production build:
>   ```powershell
>   flutter build apk --release
>   ```
> * The compiled binary is generated at: `app/build/app/outputs/flutter-apk/app-release.apk`.
> * Rename `app-release.apk` to **`Scan4Diseases-v1.0.0.apk`** prior to uploading.

---

### Maintainer Step-by-Step Checklist for Publishing a New APK

Follow these 6 steps to publish an official release:

1. **Compile the Production Release Binary**:
   ```powershell
   cd app
   flutter clean
   flutter pub get
   flutter build apk --release
   ```
2. **Locate & Rename the Output Binary**:
   * Binary path: `app/build/app/outputs/flutter-apk/app-release.apk`
   * Copy/rename to: `Scan4Diseases-v1.0.0.apk`
3. **Open GitHub Releases Page**:
   * Navigate to: [https://github.com/Rajrup910/Scan4Diseases/releases](https://github.com/Rajrup910/Scan4Diseases/releases)
   * Click the **"Draft a new release"** button (or open `https://github.com/Rajrup910/Scan4Diseases/releases/new`).
4. **Configure Release Information**:
   * **Tag version**: Type `v1.0.0` (select *Create new tag: v1.0.0 on publish*).
   * **Target**: `main` branch.
   * **Release title**: `Scan4Diseases v1.0.0 — Official Android Release`.
   * **Description**: Provide release notes, highlights, and SHA-256 hash.
5. **Attach the APK Asset**:
   * Drag and drop `Scan4Diseases-v1.0.0.apk` into the **"Attach binaries by dropping them here or selecting them"** upload box.
   * Wait until the upload is 100% complete.
6. **Publish and Verify**:
   * Ensure **"Set as the latest release"** is checked.
   * Click **"Publish release"**.
   * Test the permalink in your browser: [https://github.com/Rajrup910/Scan4Diseases/releases/latest](https://github.com/Rajrup910/Scan4Diseases/releases/latest).

---

## 5. Demo Credentials & Access Directory

All demo accounts are configured with authenticated Indian credentials, medical council registration records, and role-based access control (RBAC).

| Platform | Role | User Name | Email Address | Password | Details & Clinical Capabilities |
|---|---|---|---|---|---|
| **Clinician Web Portal** (`/portal/login`) | **Doctor 1 (Primary)** | Dr. A. Rao | `dr.rao@example.com` | `Str0ngPass!` | Reg: `MH-12345`. Chief Dermatologist. Full patient roster, longitudinal history & review trails. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 2 (Clinician)** | Dr. Sunita Mehta | `dr.mehta@example.com` | `Str0ngPass!` | Reg: `KA-67890`. Consultant Dermatologist & Dermatosurgeon. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 3 (Clinician)** | Dr. Vikram Kapoor | `dr.kapoor@example.com` | `Str0ngPass!` | Reg: `DL-98765`. Pediatric & Aesthetic Dermatology Specialist. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 4 (Clinician)** | Dr. Priya Nambiar | `dr.nambiar@example.com` | `Str0ngPass!` | Reg: `KL-45678`. Clinical Dermatopathology Specialist. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 5 (Clinician)** | Dr. Rajesh Deshmukh | `dr.deshmukh@example.com` | `Str0ngPass!` | Reg: `MH-54321`. Senior Cutaneous Oncology Consultant. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 6 (Clinician)** | Dr. Ananya Sen | `dr.sen@example.com` | `Str0ngPass!` | Reg: `WB-34567`. Melanoma & Pigmentary Lesion Specialist. |
| **Mobile App & API** (`/auth/login`) | **Patient 1 (Primary)** | Raj | `raj@gmail.com` | `12345678` | Preloaded screening history (Melanocytic nevus, Basal cell carcinoma). |
| **Mobile App & API** (`/auth/login`) | **Patient 2 (Patient)** | Ananya Verma | `ananya@gmail.com` | `12345678` | Preloaded screening history (Actinic keratosis, Benign keratosis). |
| **Mobile App & API** (`/auth/login`) | **Demo Patients** | Priya Sharma / Sachin Kumar / Jatin Verma / Aarav Patel / Rohan Sen | `priya@example.com` / `sachin@example.com` / `jatin@example.com` / `aarav@example.com` / `rohan@example.com` | `12345678` | Preloaded clinical cases (Melanoma, SCC, BCC, Keratosis, Wounds) linked to Dr. Rao. |

---

## 6. Five Curated Test Photos Across Lesion Criteria

The five standard validation cases are located in the repository at [`demo_test_samples/`](file:///c:/Users/RAJ/Downloads/Capstone/demo_test_samples):

```
demo_test_samples/
├── 01_melanoma_malignant.jpg          # Malignant Melanoma (High Risk / Urgent)
├── 02_basal_cell_carcinoma.jpg        # Basal Cell Carcinoma (Malignant Carcinoma)
├── 03_actinic_keratosis_precancer.jpg  # Actinic Keratosis (Pre-malignant)
├── 04_benign_melanocytic_nevus.jpg    # Benign Melanocytic Nevus (Common Mole)
└── 05_skin_abrasion_wound.jpg         # Skin Abrasion / Wound (Front-Stage Router)
```

---

### Case 1: Malignant Melanoma (High Risk / Urgent Medical Evaluation)
* **File:** `demo_test_samples/01_melanoma_malignant.jpg`
* **Clinical Criteria (ABCDE Rule):**
  * **A (Asymmetry):** Marked asymmetry across both orthogonal axes.
  * **B (Border):** Irregular, scalloped, notched periphery.
  * **C (Color):** Variegated dark brown, jet black, and erythematous shades.
  * **D (Diameter):** > 6 mm.
  * **E (Evolving):** Rapidly expanding lesion with recent elevation.
* **Suggested Anamnesis Questionnaire in App:**
  * Bleeding: **Yes** | Itching: **Yes** | Duration: **8 weeks** (Rapid evolution)
* **Expected Model Output:**
  * **Predicted Disease:** `Melanoma` (`mel`) | **Confidence:** `~75.6%`
  * **Triage Category:** `Urgent medical evaluation` (High Urgency)
  * **Safety Rules Triggered:** `R1_malignant_class`, `R3_malignant_mass_high`
  * **Grad-CAM:** Concentrates on the asymmetric peripheral margins and deep core pigment network.
* **Structured Prompts for AI Chatbot Assistant:**
  1. *"What is the significance of the irregular borders in this lesion?"*
  2. *"Why does the app recommend urgent medical evaluation instead of waiting?"*
  3. *"What should I ask my dermatologist during the appointment?"*

---

### Case 2: Basal Cell Carcinoma (Malignant / Common Carcinoma)
* **File:** `demo_test_samples/02_basal_cell_carcinoma.jpg`
* **Clinical Criteria:**
  * Translucent, pearly nodule with prominent branching telangiectasia.
  * Rolled border with central depression or ulceration.
* **Suggested Anamnesis Questionnaire in App:**
  * Bleeding: **Occasional bleeding** | Tenderness: **Mild** | Duration: **20 weeks**
* **Expected Model Output:**
  * **Predicted Disease:** `Basal cell carcinoma` (`bcc`) | **Confidence:** `~77.7%`
  * **Triage Category:** `Urgent medical evaluation` / `Prompt dermatologist consultation`
  * **Safety Rules Triggered:** `R1_malignant_class`
  * **Grad-CAM:** Identifies the elevated nodular core and telangiectatic margins.
* **Structured Prompts for AI Chatbot Assistant:**
  1. *"Does basal cell carcinoma usually metastasize to distant organs?"*
  2. *"What are standard surgical margins or Mohs micrographic surgery options for BCC?"*

---

### Case 3: Actinic Keratosis (Pre-Malignant Squamous Intraepidermal Neoplasia)
* **File:** `demo_test_samples/03_actinic_keratosis_precancer.jpg`
* **Clinical Criteria:**
  * Erythematous, rough, hyperkeratotic papule/plaque on chronically sun-exposed skin.
  * Distinct "sandpaper" texture on tactile examination.
* **Suggested Anamnesis Questionnaire in App:**
  * Sun exposure: **High / Chronic outdoor occupational history** | Scaly texture: **Yes** | Duration: **12 weeks**
* **Expected Model Output:**
  * **Predicted Disease:** `Actinic keratosis` (`akiec`) | **Confidence:** `~89.3%`
  * **Triage Category:** `Prompt dermatologist consultation`
  * **Safety Rules Triggered:** `R2_premalignant_class`, `R4b_premalignant_mass`
  * **Grad-CAM:** Activates strongly across the keratotic crusting region.
* **Structured Prompts for AI Chatbot Assistant:**
  1. *"What is the annual conversion risk from actinic keratosis to invasive squamous cell carcinoma?"*
  2. *"What are field-directed therapies (topical 5-FU, imiquimod, PDT) vs lesion-directed cryotherapy?"*

---

### Case 4: Melanocytic Nevus (Common Benign Mole)
* **File:** `demo_test_samples/04_benign_melanocytic_nevus.jpg`
* **Clinical Criteria:**
  * Uniform round/oval symmetry with homogeneous tan-to-brown coloration.
  * Well-demarcated margins with stable history over years.
* **Suggested Anamnesis Questionnaire in App:**
  * Bleeding: **No** | Itching: **No** | Duration: **> 1 year (Stable)**
* **Expected Model Output:**
  * **Predicted Disease:** `Melanocytic nevus` (`nv`) | **Confidence:** `~83.4%`
  * **Triage Category:** `Routine dermatologist consultation` (Low Urgency / Reassuring)
  * **Safety Rules Triggered:** `R9_default_routine`
  * **Grad-CAM:** Uniformly distributed across the circular pigment area.
* **Structured Prompts for AI Chatbot Assistant:**
  1. *"What signs should I watch for using monthly ABCDE self-examinations?"*
  2. *"How frequently should individuals with multiple dysplastic nevi be mapped with digital dermoscopy?"*

---

### Case 5: Skin Abrasion / Superficial Trauma (Front-Stage Router & OOD Gate)
* **File:** `demo_test_samples/05_skin_abrasion_wound.jpg`
* **Clinical Criteria:**
  * Linear epidermal scratch and crusting from mechanical abrasion; no neoplastic lesion.
  * Validates the **Front-Stage OOD Defense**: Rejects non-dermatological inputs (`OTHER_DAMAGE`) before disease classification, preventing false-positive malignant triage alerts.
* **Expected Model Output:**
  * **Pipeline Outcome:** `OTHER_DAMAGE` (Front-Stage Router Triggered)
  * **Confidence:** `~99.3% Non-Neoplastic Trauma`
  * **Triage:** Local first-aid guidance and wound hygiene care.
* **Structured Prompts for AI Chatbot Assistant:**
  1. *"How do I keep a minor skin abrasion clean and prevent secondary bacterial infection?"*
  2. *"What symptoms indicate that a healing wound requires formal medical attention?"*

---

## 6. Interactive Demonstration & 25-Image Flow

### Demonstration Sequence: Mobile App to Web Portal
1. **Initialize Backend**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1
   ```
2. **Launch Patient Mobile App**:
   * Connect real device via USB / wireless ADB (`powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1`) or iOS Simulator.
   * Log in as Patient: `raj@gmail.com` / `12345678`.
3. **Perform Live Screening**:
   * Navigate to **Scan Skin** -> Pick `01_melanoma_malignant.jpg` -> Fill Anamnesis survey.
   * Observe inference latency (<400ms on server) -> Inspect Grad-CAM overlay -> Switch between English and Hindi results.
4. **Share Screening with Clinician**:
   * Tap **Share with Doctor** -> Select **Dr. A. Rao** -> Submit.
5. **Open Clinician Web Portal**:
   * Navigate to `https://scan4diseases.onrender.com/portal/login` (or `http://localhost:8000/portal/login`).
   * Sign in as `dr.rao@example.com` / `Str0ngPass!`.
6. **Clinician Triage & Audit**:
   * Inspect the shared report in the Patient Roster -> Examine side-by-side original and Grad-CAM decrypted image -> Update status to **Reviewed** and sign off with a clinical note.

---

## 7. Technical Reference & Troubleshooting

| Diagnostic Scenario | Verified Resolution |
|---|---|
| **Mobile App: "Network error / Connection refused"** | Run `powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1` to re-forward port 8000 via ADB reverse. |
| **Mobile App: Direct Wi-Fi Testing** | On the app login screen, tap the **Server Config** gear icon and enter your machine's LAN IP: `http://192.168.x.x:8000`. |
| **SSL / HTTPS Certificates on Cloud** | Render Cloud provides automatic TLS 1.3 certificates. No custom root certificate installation required on Android / iOS. |
| **PyTorch Inference Device** | Default auto-detects CUDA/MPS; falls back safely to multi-threaded CPU inference. |

---

## 8. Clinician Web Portal - Visual Showcase (Light & Dark Mode)

### 7.1 Doctor Authentication & Secure Workstation Login
The gateway to the Clinician Decision-Support Portal. Features biometric/credential inputs, server health indicators, and security notices.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/01_portal_login_light.png" width="450" alt="Doctor Login Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/01_portal_login_dark.png" width="450" alt="Doctor Login Dark Mode"></td>
  </tr>
</table>

*Figure 7.1: Clinician workstation login screen (`Website demo images/01_portal_login_light.png` & `_dark.png`).*

---

### 7.2 Security Rate Limiting & Auth Error Notification Toast Pop
Displays interactive security defense: rate limits unauthorized authentication attempts and flashes cryptographic error tokens.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/02_portal_login_error_light.png" width="450" alt="Login Error Toast Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/02_portal_login_error_dark.png" width="450" alt="Login Error Toast Dark Mode"></td>
  </tr>
</table>

*Figure 7.2: Security rate-limiting and validation notification toast (`Website demo images/02_portal_login_error_light.png` & `_dark.png`).*

---

### 7.3 Central Patient Roster & Triage Priority Directory
Main clinical overview showing incoming patient screenings prioritized by clinical triage urgency (Urgent Red, Prompt Amber, Routine Green).

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/03_portal_patient_roster_light.png" width="450" alt="Patient Roster Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/03_portal_patient_roster_dark.png" width="450" alt="Patient Roster Dark Mode"></td>
  </tr>
</table>

*Figure 7.3: Central patient triage roster (`Website demo images/03_portal_patient_roster_light.png` & `_dark.png`).*

---

### 7.4 Global Command Palette (Ctrl+K / Cmd+K) Omnisearch Modal Pop
Instant keyboard-driven search to navigate patients, diagnosis ICD codes, anamnesis symptoms, and audit trails.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/04_portal_command_palette_light.png" width="450" alt="Command Palette Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/04_portal_command_palette_dark.png" width="450" alt="Command Palette Dark Mode"></td>
  </tr>
</table>

*Figure 7.4: Omnisearch command palette modal (`Website demo images/04_portal_command_palette_light.png` & `_dark.png`).*

---

### 7.5 Longitudinal Patient Case Timeline & Historical Screenings
Chronological timeline view tracking patient lesion evolution across multiple hospital visits.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/05_portal_patient_timeline_light.png" width="450" alt="Patient Timeline Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/05_portal_patient_timeline_dark.png" width="450" alt="Patient Timeline Dark Mode"></td>
  </tr>
</table>

*Figure 7.5: Longitudinal patient screening history (`Website demo images/05_portal_patient_timeline_light.png` & `_dark.png`).*

---

### 7.6 Interactive Triage Filtering Tabs (Urgent / Prompt / Routine) Active State
Live filtering by clinical severity allows dermatologists to immediately isolate malignant cases.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/06_portal_triage_filtering_light.png" width="450" alt="Triage Filtering Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/06_portal_triage_filtering_dark.png" width="450" alt="Triage Filtering Dark Mode"></td>
  </tr>
</table>

*Figure 7.6: Active triage filtering state (`Website demo images/06_portal_triage_filtering_light.png` & `_dark.png`).*

---

### 7.7 Deep Clinical Case Inspection & High-Resolution Canvas Viewer
High-resolution medical image inspection view with clinical anamnesis metadata, CNN softmax probability distribution, and symptom logs.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/07_portal_case_inspection_light.png" width="450" alt="Case Inspection Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/07_portal_case_inspection_dark.png" width="450" alt="Case Inspection Dark Mode"></td>
  </tr>
</table>

*Figure 7.7: Deep clinical case inspection canvas (`Website demo images/07_portal_case_inspection_light.png` & `_dark.png`).*

---

### 7.8 Explainable AI (Grad-CAM) Heatmap Overlay & Opacity Slider Transition
Interactive Gradient-weighted Class Activation Mapping overlay verifying the neural network's focus on lesion borders.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/08_portal_gradcam_overlay_light.png" width="450" alt="Grad-CAM Overlay Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/08_portal_gradcam_overlay_dark.png" width="450" alt="Grad-CAM Overlay Dark Mode"></td>
  </tr>
</table>

*Figure 7.8: Grad-CAM Explainable AI overlay (`Website demo images/08_portal_gradcam_overlay_light.png` & `_dark.png`).*

---

### 7.9 Side-by-Side Dual-Image Comparison Window
Synchronized side-by-side viewer for comparing dermoscopic lesions against baseline historical screenings.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/09_portal_dual_compare_light.png" width="450" alt="Dual Compare Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/09_portal_dual_compare_dark.png" width="450" alt="Dual Compare Dark Mode"></td>
  </tr>
</table>

*Figure 7.9: Dual-image comparative viewer (`Website demo images/09_portal_dual_compare_light.png` & `_dark.png`).*

---

### 7.10 Clinical Triage Decision-Support Matrix & Rule Engine Log
Displays the exact deterministic safety rule triggered (`R1_malignant_class`, `R3_malignant_mass_high`) and clinical reasoning chain.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/10_portal_triage_matrix_light.png" width="450" alt="Triage Decision Matrix Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/10_portal_triage_matrix_dark.png" width="450" alt="Triage Decision Matrix Dark Mode"></td>
  </tr>
</table>

*Figure 7.10: Deterministic triage rule engine audit matrix (`Website demo images/10_portal_triage_matrix_light.png` & `_dark.png`).*

---

### 7.11 Doctor Clinical Notes, Second Opinions & Differential Diagnosis Form
Interactive clinical documentation interface allowing dermatologists to record notes, request biopsies, and update case triage.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/11_portal_doctor_notes_light.png" width="450" alt="Doctor Notes Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/11_portal_doctor_notes_dark.png" width="450" alt="Doctor Notes Dark Mode"></td>
  </tr>
</table>

*Figure 7.11: Clinician consultation note editor (`Website demo images/11_portal_doctor_notes_light.png` & `_dark.png`).*

---

### 7.12 Status Update Workflow & Clinical Escalation Trigger Action
Single-click workflow actions to transition cases between *New*, *Under Review*, *Escalated*, and *Reviewed*.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/12_portal_status_action_light.png" width="450" alt="Status Action Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/12_portal_status_action_dark.png" width="450" alt="Status Action Dark Mode"></td>
  </tr>
</table>

*Figure 7.12: Case escalation and status update workflow (`Website demo images/12_portal_status_action_light.png` & `_dark.png`).*

---

### 7.13 Appointment Calendar & Clinic Consultation Booking Hub
Complete appointment scheduling system showing booked patient consultations, clinical urgency badges, and calendar views.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/13_portal_appointments_calendar_light.png" width="450" alt="Appointments Calendar Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/13_portal_appointments_calendar_dark.png" width="450" alt="Appointments Calendar Dark Mode"></td>
  </tr>
</table>

*Figure 7.13: Appointment calendar and schedule management (`Website demo images/13_portal_appointments_calendar_light.png` & `_dark.png`).*

---

### 7.14 Appointment Details Modal & Recommend-a-Visit Clinical Drawer
Slide-in drawer showing comprehensive visit details, linked screening history, and doctor consultation recommendation tools.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/14_portal_appointment_detail_light.png" width="450" alt="Appointment Details Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/14_portal_appointment_detail_dark.png" width="450" alt="Appointment Details Dark Mode"></td>
  </tr>
</table>

*Figure 7.14: Appointment details and visit recommendation drawer (`Website demo images/14_portal_appointment_detail_light.png` & `_dark.png`).*

---

### 7.16 Keyboard Shortcuts Cheatsheet Modal Pop
Comprehensive keyboard shortcuts directory for rapid navigation without taking hands off the keyboard.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Website%20demo%20images/16_portal_keyboard_shortcuts_light.png" width="450" alt="Keyboard Shortcuts Light Mode"></td>
    <td align="center"><img src="Website%20demo%20images/16_portal_keyboard_shortcuts_dark.png" width="450" alt="Keyboard Shortcuts Dark Mode"></td>
  </tr>
</table>

*Figure 7.16: Keyboard shortcuts cheatsheet modal (`Website demo images/16_portal_keyboard_shortcuts_light.png` & `_dark.png`).*  

---

## 9. Mobile Application - Visual Showcase (Light & Dark Mode)

### 8.1 Onboarding & Clinical Disclaimer Gate
Introductory flow presenting the tripartite clinical safety disclaimer, regulatory framing, and system overview.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/01_app_onboarding_light.png" width="300" alt="App Onboarding Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/01_app_onboarding_dark.png" width="300" alt="App Onboarding Dark Mode"></td>
  </tr>
</table>

*Figure 8.1: Patient onboarding screen (`Appp demo images/01_app_onboarding_light.png` & `_dark.png`).*

---

### 8.2 Patient Authentication & Multi-Language Selection (English / Hindi)
Login screen supporting authenticated patient profiles and one-tap language switching.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/02_app_login_light.png" width="300" alt="App Login Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/02_app_login_dark.png" width="300" alt="App Login Dark Mode"></td>
  </tr>
</table>

*Figure 8.2: Mobile authentication interface (`Appp demo images/02_app_login_light.png` & `_dark.png`).*

---

### 8.3 Patient Home Dashboard & Quick-Triage Action Center
Central home hub featuring recent screenings, UV index advisory, quick scan button, and self-check reminder tiles.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/03_app_home_dashboard_light.png" width="300" alt="Home Dashboard Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/03_app_home_dashboard_dark.png" width="300" alt="Home Dashboard Dark Mode"></td>
  </tr>
</table>

*Figure 8.3: Patient home dashboard (`Appp demo images/03_app_home_dashboard_light.png` & `_dark.png`).*

---

### 8.4 Patient Home Dashboard & Quick Actions
The quick action bar contains New screenigs, My screenigs, Skin health guide and Fin a doctor like services to help the user quickly navigate to quick access features.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/03_app_home_quick_actions_light.png" width="300" alt="Home quick actions Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/03_app_home_quick_actions_dark.png" width="300" alt="Home quick actions Dark Mode"></td>
  </tr>
</table>

*Figure 8.4: Patient home  Quich actions (`Appp demo images/04_app_home_quick_actions_light.png` & `_dark.png`).*


### 8.5 Smart In-App Camera Capture with Circular Framing Guide & Flash
In-app camera viewfinder featuring a circular lesion reticle, lighting balance sensors, and torch toggles.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/05_app_camera_capture_light.png" width="300" alt="Camera Capture Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/05_app_camera_capture_dark.png" width="300" alt="Camera Capture Dark Mode"></td>
  </tr>
</table>

*Figure 8.5: Camera capture interface with circular framing guide (`Appp demo images/05_app_camera_capture_light.png` & `_dark.png`).*

---

### 8.6 Clinical Anamnesis Symptom Questionnaire Form
Step-by-step questionnaire capturing symptom evolution (bleeding, itching, rapid growth, elevation, lesion duration).

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/06_app_questionnaire_light.png" width="300" alt="Questionnaire Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/06_app_questionnaire_dark.png" width="300" alt="Questionnaire Dark Mode"></td>
  </tr>
</table>

*Figure 8.6: Patient symptom anamnesis form (`Appp demo images/06_app_questionnaire_light.png` & `_dark.png`).*

---

### 8.8 High-Risk Urgent Triage Result Screen (Melanoma Example)
High urgency alert screen displaying red triage indicator, predicted probability, and doctor consultation advisory.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/08_app_result_urgent_light.png" width="300" alt="Urgent Result Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/08_app_result_urgent_dark.png" width="300" alt="Urgent Result Dark Mode"></td>
  </tr>
</table>

*Figure 8.8: High-urgency malignant screening output (`Appp demo images/08_app_result_urgent_light.png` & `_dark.png`).*

---

### 8.9 Pre-Malignant Prompt Triage Result Screen (Actinic Keratosis Example)
Amber-tier screening result indicating pre-cancerous lesion requiring prompt outpatient evaluation.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/09_app_result_prompt_light.png" width="300" alt="Prompt Result Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/09_app_result_prompt_dark.png" width="300" alt="Prompt Result Dark Mode"></td>
  </tr>
</table>

*Figure 8.9: Prompt outpatient triage output (`Appp demo images/09_app_result_prompt_light.png` & `_dark.png`).*

---

### 8.10 Reassuring Routine Triage Result Screen (Nevus Example)
Green-tier reassuring screening result confirming common benign mole patterns with routine self-check tips.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/10_app_result_routine_light.png" width="300" alt="Routine Result Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/10_app_result_routine_dark.png" width="300" alt="Routine Result Dark Mode"></td>
  </tr>
</table>

*Figure 8.10: Reassuring routine screening output (`Appp demo images/10_app_result_routine_light.png` & `_dark.png`).*

---

### 8.11 Front-Stage OOD Router Defense & Non-Lesion Wound Detection
Demonstrates the OOD gate rejecting superficial abrasions (`OTHER_DAMAGE`) with first-aid guidance.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/11_app_result_wound_light.png" width="300" alt="Wound Detection Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/11_app_result_wound_dark.png" width="300" alt="Wound Detection Dark Mode"></td>
  </tr>
</table>

*Figure 8.11: Front-stage router trauma rejection screen (`Appp demo images/11_app_result_wound_light.png` & `_dark.png`).*

---

### 8.12 Interactive Explainable AI (Grad-CAM) Visual Heatmap Screen
Mobile Explainable AI canvas showing activation heatmap superimposed over patient lesion borders.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/12_app_gradcam_view_light.png" width="300" alt="Mobile Grad-CAM Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/12_app_gradcam_view_dark.png" width="300" alt="Mobile Grad-CAM Dark Mode"></td>
  </tr>
</table>

*Figure 8.12: Mobile Explainable AI (Grad-CAM) interface (`Appp demo images/12_app_gradcam_view_light.png` & `_dark.png`).*

---

### 8.13 Full 7-Class ISIC Softmax Confidence Distribution Breakdown
Detailed probability distribution across all 7 diagnostic classes (MEL, NV, BCC, AKIEC, BKL, DF, VASC).

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/13_app_all_class_scores_light.png" width="300" alt="All Class Scores Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/13_app_all_class_scores_dark.png" width="300" alt="All Class Scores Dark Mode"></td>
  </tr>
</table>

*Figure 8.13: 7-Class softmax probability breakdown (`Appp demo images/13_app_all_class_scores_light.png` & `_dark.png`).*

---

### 8.14 Plain-Language AI Explanation & Clinical Reasoning Breakdown
Plain-language clinical narrative generated under safety constraints, explaining the recommendation in simple terms.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/14_app_understanding_result_light.png" width="300" alt="Understanding Result Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/14_app_understanding_result_dark.png" width="300" alt="Understanding Result Dark Mode"></td>
  </tr>
</table>

*Figure 8.14: Plain-language AI reasoning module (`Appp demo images/14_app_understanding_result_light.png` & `_dark.png`).*

---

### 8.15 Localized Hindi (हिंदी) Screening Result & Urgency Display
Complete localized triage display for Hindi-speaking users, translating clinical guidance and class names.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/15_app_hindi_result_light.png" width="300" alt="Hindi Result Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/15_app_hindi_result_dark.png" width="300" alt="Hindi Result Dark Mode"></td>
  </tr>
</table>

*Figure 8.15: Hindi localized screening interface (`Appp demo images/15_app_hindi_result_light.png` & `_dark.png`).*

---

### 8.16 Share Screening with Verified Doctor & Cryptographic Consent Sheet
Consent management sheet allowing patients to select a registered doctor and transmit their encrypted screening.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/16_app_share_with_doctor_light.png" width="300" alt="Share With Doctor Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/16_app_share_with_doctor_dark.png" width="300" alt="Share With Doctor Dark Mode"></td>
  </tr>
</table>

*Figure 8.16: Patient doctor-sharing consent sheet (`Appp demo images/16_app_share_with_doctor_light.png` & `_dark.png`).*

---

### 8.17 Book a Consultation with a Verified Dermatologist
Appointment booking interface enabling patients to select specialist doctors, preferred dates, and attach reports.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/17_app_book_appointment_light.png" width="300" alt="Book Appointment Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/17_app_book_appointment_dark.png" width="300" alt="Book Appointment Dark Mode"></td>
  </tr>
</table>

*Figure 8.17: Doctor appointment booking workflow (`Appp demo images/17_app_book_appointment_light.png` & `_dark.png`).*

---

### 8.18 Patient Appointments Hub & Status Tracking Tab
Patient appointment management screen showing confirmed consultations, pending requests, and doctor notes.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/18_app_appointments_tab_light.png" width="300" alt="Appointments Tab Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/18_app_appointments_tab_dark.png" width="300" alt="Appointments Tab Dark Mode"></td>
  </tr>
</table>

*Figure 8.18: Patient appointments tracking tab (`Appp demo images/18_app_appointments_tab_light.png` & `_dark.png`).*

---

### 8.19 In-App Notification Center & Doctor Action Alerts
Real-time notification bell displaying doctor review confirmations, appointment approvals, and clinical recommendations.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/19_app_notifications_light.png" width="300" alt="Notifications Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/19_app_notifications_dark.png" width="300" alt="Notifications Dark Mode"></td>
  </tr>
</table>

*Figure 8.19: In-app notification center (`Appp demo images/19_app_notifications_light.png` & `_dark.png`).*

---

### 8.20 Context-Aware AI Dermatological Chatbot Assistant
Interactive AI chatbot answering patient questions, explaining medical terms, and preparing questions for appointments.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/20_app_ai_chatbot_light.png" width="300" alt="AI Chatbot Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/20_app_ai_chatbot_dark.png" width="300" alt="AI Chatbot Dark Mode"></td>
  </tr>
</table>

*Figure 8.20: Context-aware AI assistant chatbot (`Appp demo images/20_app_ai_chatbot_light.png` & `_dark.png`).*

---

### 8.21 AI Assistant Suggested Follow-Up Clinical Inquiries
Contextual prompt chips providing structured follow-up questions tailored to the patient's predicted lesion class.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/21_app_chatbot_suggestions_light.png" width="300" alt="Chatbot Suggestions Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/21_app_chatbot_suggestions_dark.png" width="300" alt="Chatbot Suggestions Dark Mode"></td>
  </tr>
</table>

*Figure 8.21: Dynamic follow-up question suggestions (`Appp demo images/21_app_chatbot_suggestions_light.png` & `_dark.png`).*

---

### 8.22 Patient Longitudinal Screening History & Archive Directory
Searchable archive displaying all past screenings, timestamps, diagnostic labels, and doctor sharing status.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/22_app_screening_history_light.png" width="300" alt="Screening History Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/22_app_screening_history_dark.png" width="300" alt="Screening History Dark Mode"></td>
  </tr>
</table>

*Figure 8.22: Patient screening history directory (`Appp demo images/22_app_screening_history_light.png` & `_dark.png`).*

---

### 8.23 Monthly Self-Examination Push Reminder Scheduler
Configurable calendar reminder enabling patients to schedule monthly skin self-examinations.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/23_app_monthly_push_reminder_light.png" width="300" alt="Monthly Push Reminder Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/23_app_monthly_push_reminder_dark.png" width="300" alt="Monthly Push Reminder Dark Mode"></td>
  </tr>
</table>

*Figure 8.23: Monthly self-examination reminder push notification (`Appp demo images/23_app_monthly_push_reminder_light.png` & `_dark.png`).*

---

### 8.24 Find a Dermatologist Directory & Doctor Profile Cards
Directory of certified dermatologists with medical council registration numbers, clinic details, and booking links.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/24_app_find_dermatologist_light.png" width="300" alt="Find a Dermatologist Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/24_app_find_dermatologist_dark.png" width="300" alt="Find a Dermatologist Dark Mode"></td>
  </tr>
</table>

*Figure 8.24: Dermatologist directory and clinician profiles (`Appp demo images/24_app_find_dermatologist_light.png` & `_dark.png`).*

---

### 8.25 Skin Health Educational Library & Prevention Hub
Educational library covering skin cancer prevention, self-examination protocols, and skin maintenance.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/25_app_skin_health_guide_light.png" width="300" alt="Skin Health Guide Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/25_app_skin_health_guide_dark.png" width="300" alt="Skin Health Guide Dark Mode"></td>
  </tr>
</table>

*Figure 8.25: Skin health educational library (`Appp demo images/25_app_skin_health_guide_light.png` & `_dark.png`).*

---

### 8.26 Interactive ABCDE Melanoma Criteria Educational Guide
Visual educational module detailing **A**symmetry, **B**order, **C**olor, **D**iameter, and **E**volving melanoma signs.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/26_app_abcde_rule_guide_light.png" width="300" alt="ABCDE Rule Guide Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/26_app_abcde_rule_guide_dark.png" width="300" alt="ABCDE Rule Guide Dark Mode"></td>
  </tr>
</table>

*Figure 8.26: ABCDE melanoma awareness and criteria guide (`Appp demo images/26_app_abcde_rule_guide_light.png` & `_dark.png`).*

---

### 8.27 Fitzpatrick Skin Phototype Interactive Quiz & UV Suncare
Calculates the user's Fitzpatrick skin phototype (Type I–VI) and generates personalized broad-spectrum SPF advice.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/27_app_skin_type_quiz_light.png" width="300" alt="Skin Type Quiz Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/27_app_skin_type_quiz_dark.png" width="300" alt="Skin Type Quiz Dark Mode"></td>
  </tr>
</table>

*Figure 8.27: Fitzpatrick skin phototyping quiz and UV recommendations (`Appp demo images/27_app_skin_type_quiz_light.png` & `_dark.png`).*

---

### 8.28 Patient Profile, Doctor Consent Revocation & Privacy Controls
Profile settings screen allowing patients to manage active doctor consents, review privacy policies, and securely log out.

<table>
  <tr>
    <th width="50%" align="center">Light Mode</th>
    <th width="50%" align="center">Dark Mode</th>
  </tr>
  <tr>
    <td align="center"><img src="Appp%20demo%20images/28_app_user_profile_light.png" width="300" alt="User Profile Light Mode"></td>
    <td align="center"><img src="Appp%20demo%20images/28_app_user_profile_dark.png" width="300" alt="User Profile Dark Mode"></td>
  </tr>
</table>

*Figure 8.28: Profile settings and consent management controls (`Appp demo images/28_app_user_profile_light.png` & `_dark.png`).*

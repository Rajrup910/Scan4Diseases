# AI-Assisted Dermatology Screening Mobile Application
## Master Implementation Instructions for Claude

> **Purpose:** This document is the master specification for planning, implementing, testing, debugging, and documenting the complete project. Treat it as the project's source of truth.
>
> **Important:** The application is an AI-assisted **screening and educational decision-support system**, not an autonomous medical diagnostic system.

---

# 1. Project Objective

Build a mobile application that allows a user to:

1. Capture or upload a photograph of a skin lesion.
2. Validate and preprocess the image.
3. Run a transfer-learning-based deep-learning classifier.
4. Classify the lesion into approximately **7–8 dermatological classes**, based on a justified class mapping from the selected datasets.
5. Display the predicted class and model confidence.
6. Generate a **Grad-CAM heatmap** showing which image regions contributed to the prediction.
7. Ask a short, structured symptom questionnaire.
8. Combine the computer-vision result with the questionnaire.
9. Pass the structured result to an **open-source LLM**.
10. Generate:
   - Plain-language explanation
   - Controlled urgency/triage guidance
   - Bilingual follow-up conversation
11. Always display a mandatory dermatologist-consultation warning.

The system must clearly distinguish:

```text
CNN
→ Visual classification

Rule-based safety layer
→ Controlled triage/safety logic

LLM
→ Explanation, language support, and conversation
```

The LLM must **not** be treated as the primary diagnostic model.

---

# 2. Mandatory Pre-Implementation Review

**Do not immediately write large amounts of code.**

First inspect the existing project/repository and determine:

- Current project structure
- Existing frontend
- Existing backend
- Existing ML code
- Existing datasets or dataset references
- Existing models
- Existing APIs
- Existing dependencies
- Existing documentation
- Existing bugs
- What can be reused
- What should be removed
- What should be refactored
- What is missing

Before implementation, produce a concise technical assessment:

```text
Existing System
      ↓
Problems / Risks
      ↓
Recommended Changes
      ↓
Proposed Architecture
      ↓
Implementation Plan
```

Separate recommendations into:

### Required
Necessary for the project to function correctly.

### Recommended
Meaningful improvements that should be implemented if practical.

### Optional
Features that should only be added after the core system is working.

Do not introduce unnecessary complexity merely to make the project look more advanced.

---

# 3. Recommended Architecture

Use this as the starting architecture, but improve it if inspection shows a better approach:

```text
                    MOBILE APPLICATION
                           │
                           │ HTTPS / REST
                           ▼
                    FASTAPI BACKEND
                           │
              ┌────────────┴─────────────┐
              │                          │
              ▼                          ▼
       IMAGE PROCESSING             QUESTIONNAIRE
              │                          │
              ▼                          │
       CNN CLASSIFIER                    │
       ┌───────────────┐                 │
       │ ResNet-50     │                 │
       │ EfficientNet  │                 │
       └───────────────┘                 │
              │                          │
       ┌──────┼─────────┐                │
       ▼      ▼         ▼                │
    Class  Confidence Grad-CAM            │
       │      │         │                │
       └──────┴────┬────┘                │
                    │                    │
                    └────────┬───────────┘
                             ▼
                    STRUCTURED RESULT
                             │
                             ▼
                    SAFETY / TRIAGE LAYER
                             │
                             ▼
                    OPEN-SOURCE LLM
                             │
                  ┌──────────┼──────────┐
                  ▼          ▼          ▼
             Explanation   Triage*   Bilingual Chat
                             │
                             ▼
                  DERMATOLOGIST WARNING

* Prefer deterministic rules for the actual safety/triage
  category; use the LLM to explain the controlled result.
```

---

# 4. Recommended Technology Stack

Prioritize free and open-source technologies.

## Mobile

Preferred:

- Flutter
- Dart

Alternative:

- React Native

Use Flutter unless an existing project already uses another framework effectively.

## Backend

Preferred:

- Python
- FastAPI
- Uvicorn

Recommended endpoints:

```text
GET  /health
POST /predict
POST /chat
```

Add endpoints only when genuinely required.

## Machine Learning

Use:

- PyTorch
- torchvision
- scikit-learn
- NumPy
- pandas
- Pillow
- OpenCV where useful

## CNN Candidates

Evaluate:

- ResNet-50
- EfficientNet-B0/B2/B3

Do not assume both must be deployed.

Train/evaluate both when computationally practical and select the deployment model based on evidence.

## LLM

Prefer an open-source model such as:

- Qwen
- Llama
- Mistral

Possible local runtimes:

- Ollama
- llama.cpp
- Hugging Face Transformers

Choose the model based on available hardware. Use quantization when appropriate.

---

# 5. Dataset Strategy

Use publicly available dermatology datasets such as:

- HAM10000
- ISIC 2019

Before training:

- Inspect class distributions.
- Inspect metadata.
- Inspect image dimensions.
- Validate labels.
- Identify duplicates where possible.
- Identify class imbalance.
- Check for patient/lesion identifiers.
- Check for possible data leakage.

## Critical Data-Leakage Rule

Do **not** randomly split images in a way that allows images belonging to the same patient or lesion to appear in both training and test sets when patient/lesion identifiers are available.

The test set must represent genuinely unseen data.

Document the exact split strategy.

---

# 6. Class Design

Do not arbitrarily create an eighth class simply to satisfy the project description.

First inspect the actual labels in the selected datasets.

If combining HAM10000 and ISIC 2019:

1. Identify compatible disease categories.
2. Create a documented mapping.
3. Explain how incompatible labels are handled.
4. Do not merge medically distinct categories without justification.
5. Store the final mapping in a version-controlled file such as:

```text
ml/config/class_mapping.json
```

The final number of classes should be determined by:

- Label compatibility
- Data quality
- Class frequency
- Clinical meaning
- Project feasibility

---

# 7. Image Preprocessing

Implement a reproducible preprocessing pipeline.

Typical inference pipeline:

```text
Input Image
    ↓
Validate File
    ↓
RGB Conversion
    ↓
Resize / Crop
    ↓
Tensor Conversion
    ↓
Model-Specific Normalization
    ↓
CNN Inference
```

For pretrained ImageNet models, use the normalization expected by the selected architecture unless there is a documented reason to change it.

## Training Augmentation

Potential augmentations:

- Horizontal flip
- Small rotations
- Controlled crop
- Scale/zoom
- Brightness adjustment
- Contrast adjustment

Avoid transformations that create medically unrealistic images.

Keep training augmentation separate from validation/test preprocessing.

---

# 8. Transfer Learning

Do not train ResNet-50 or EfficientNet from scratch unless there is a specific research reason.

Use pretrained ImageNet weights.

General process:

```text
ImageNet pretrained model
          ↓
Replace original classifier
          ↓
Add dermatology classifier
          ↓
Initially freeze most backbone layers
          ↓
Train classification head
          ↓
Unfreeze selected deeper layers
          ↓
Fine-tune with a lower learning rate
```

Use appropriate techniques such as:

- Adam or AdamW
- Learning-rate scheduler
- Weight decay
- Early stopping
- Model checkpointing

Record all hyperparameters.

---

# 9. ResNet-50

ResNet-50 is a 50-layer residual CNN.

Its key feature is the **skip connection**:

```text
Input x
  ├───────────────┐
  ↓               │
Convolutional     │
layers            │
  ↓               │
F(x)              │
  └────── + x ◄───┘
        ↓
      Output
```

Instead of learning the entire mapping directly, residual blocks learn a residual function:

```text
H(x) = F(x) + x
```

Advantages:

- Strong feature extraction
- Mature and widely used architecture
- Good transfer-learning baseline
- Strong performance on image classification

Approximate parameter count:

```text
~25.6 million
```

Use ResNet-50 as a strong baseline for comparison.

---

# 10. EfficientNet

EfficientNet is designed to achieve strong accuracy with better computational efficiency.

It uses **compound scaling**, which scales:

- Depth
- Width
- Input resolution

in a coordinated manner.

EfficientNet variants include:

```text
B0
B1
B2
B3
...
B7
```

EfficientNet-B0 is much smaller than ResNet-50, with approximately 5.3 million parameters.

Advantages:

- Lower parameter count
- Lower memory requirements
- Faster inference
- Better suitability for mobile-oriented deployment

Do not assume EfficientNet is automatically better. Measure it.

---

# 11. ResNet-50 vs EfficientNet Experiment

Train/evaluate both using the **same data split and evaluation methodology**.

Compare:

- Accuracy
- Balanced accuracy
- Macro precision
- Macro recall
- Macro F1
- Weighted F1
- ROC-AUC where appropriate
- Parameter count
- Model size
- Inference latency
- Memory usage

Example decision:

```text
If EfficientNet has comparable or better F1/recall
and substantially lower computational cost:

→ Deploy EfficientNet

Keep ResNet-50 as the experimental baseline.
```

This provides a stronger academic justification than simply selecting one model without comparison.

---

# 12. Class Imbalance

This is a major consideration for dermatology datasets.

Do not rely on raw accuracy alone.

Possible techniques:

### Class-weighted loss

Give greater weight to underrepresented classes.

### Weighted sampling

Use a weighted sampler when appropriate.

### Controlled augmentation

Increase training variation for minority classes.

Evaluate which method works best.

Do not oversample so aggressively that the model simply memorizes minority examples.

---

# 13. Training Pipeline

Use a reproducible training pipeline.

Required components:

```text
Dataset loader
    ↓
Transforms
    ↓
Train / validation / test split
    ↓
DataLoader
    ↓
Model
    ↓
Loss
    ↓
Optimizer
    ↓
Scheduler
    ↓
Validation
    ↓
Checkpoint
    ↓
Final test evaluation
```

Save the best model based on a validation metric chosen before final testing.

Do not select a model by repeatedly checking the test set.

---

# 14. Evaluation

Report at minimum:

- Accuracy
- Balanced accuracy
- Precision
- Recall
- Macro F1
- Weighted F1
- Confusion matrix
- Per-class precision/recall/F1
- ROC-AUC where appropriate
- Training/validation curves
- Inference time

Medical screening is particularly sensitive to false negatives, so explicitly analyze recall/sensitivity for clinically important classes.

Do not fabricate results.

If the model achieves 82%, report 82%.

If it achieves 91%, report 91%.

---

# 15. Expected Performance

Use **85–90%+ accuracy only as a development target**, not a promised result.

Actual performance depends on:

- Data split
- Dataset composition
- Class balance
- Preprocessing
- Model architecture
- Fine-tuning strategy
- Image quality
- Patient population

The final report must contain measured test-set results.

A strong project should emphasize:

```text
Macro F1
Per-class recall
Confusion matrix
Balanced accuracy
Calibration
```

rather than only headline accuracy.

---

# 16. Confidence Score

The classifier produces logits, which are converted into class probabilities using Softmax:

```text
P_i = exp(z_i) / Σ exp(z_j)
```

Example:

```text
Melanoma          0.84
Nevus             0.08
BCC               0.03
Other             0.05
```

Display:

```text
Predicted class: Melanoma
Model confidence: 84%
```

Do **not** tell the user:

> "There is an 84% chance that you have melanoma."

Instead say:

> "The model assigned its highest prediction score (84%) to the melanoma class."

Where practical, investigate confidence calibration using:

- Reliability diagrams
- Expected Calibration Error
- Temperature scaling

---

# 17. Grad-CAM

Grad-CAM is the explainability component.

It should answer:

> "Which regions of the image contributed most to the model's prediction?"

Implementation process:

1. Run the image through the CNN.
2. Identify the predicted class.
3. Select an appropriate late convolutional layer.
4. Calculate gradients of the predicted class score with respect to that layer's feature maps.
5. Compute importance weights from the gradients.
6. Weight the feature maps.
7. Sum the weighted feature maps.
8. Apply ReLU.
9. Normalize the activation map.
10. Resize it to the original image dimensions.
11. Overlay it on the original image.

Conceptually:

```text
Image
  ↓
CNN
  ↓
Feature Maps
  ↓
Predicted Class
  ↓
Gradients
  ↓
Importance Weights
  ↓
Weighted Feature Maps
  ↓
Grad-CAM
  ↓
Heatmap Overlay
```

---

# 18. Grad-CAM Validation

Do not simply generate a heatmap and call it explainability.

Test multiple images and inspect whether the heatmap focuses on:

- Lesion region
- Relevant lesion structures

rather than:

- Background
- Image border
- Hair
- Clothing
- Watermarks
- Lighting artifacts

If the model repeatedly focuses on irrelevant regions, investigate:

- Dataset bias
- Preprocessing
- Cropping
- Image artifacts
- Data leakage

Document limitations.

Grad-CAM is an interpretability aid, not proof that the model is using medically correct reasoning.

---

# 19. Image Quality Check

Consider adding a basic image-quality gate before classification.

Potential problems:

- Severe blur
- Very dark image
- Extreme overexposure
- No obvious lesion
- Excessive obstruction

If the image is clearly inadequate:

```text
Image quality is insufficient for screening.
Please capture a clearer, well-lit image.
```

Do not build a complex quality model unless necessary.

A simple, reliable check is preferable to an unreliable extra ML model.

---

# 20. Symptom Questionnaire

Use a short structured questionnaire.

Potential fields:

```text
duration
recent_change
itching
pain
bleeding
size_change
color_change
family_history
sun_exposure
```

Example:

```json
{
  "duration": "2_months",
  "recent_change": true,
  "itching": false,
  "pain": true,
  "bleeding": false,
  "color_change": true
}
```

Do not present questionnaire answers as validated diagnostic criteria unless they are supported by the project's medical evidence.

---

# 21. Backend

Use FastAPI as the bridge between the mobile application and AI services.

Recommended structure:

```text
backend/
├── app/
│   ├── main.py
│   ├── routes/
│   │   ├── health.py
│   │   ├── predict.py
│   │   └── chat.py
│   ├── services/
│   │   ├── inference.py
│   │   ├── preprocessing.py
│   │   ├── gradcam.py
│   │   ├── triage.py
│   │   └── llm.py
│   ├── models/
│   ├── safety/
│   └── config.py
└── tests/
```

Do not put the entire backend in one file.

Do not put model training code inside the API server.

---

# 22. API

## GET /health

Example response:

```json
{
  "status": "ok"
}
```

## POST /predict

Input:

```text
image
questionnaire
```

Output should contain structured information such as:

```json
{
  "predicted_class": "melanoma",
  "confidence": 0.84,
  "probabilities": {},
  "gradcam_url": "...",
  "triage": "prompt_consultation"
}
```

## POST /chat

Input:

```json
{
  "prediction": {},
  "questionnaire": {},
  "message": "What does this result mean?"
}
```

Output:

```json
{
  "response": "..."
}
```

Validate all input.

Do not expose:

- Local filesystem paths
- Secrets
- Internal stack traces
- Sensitive model information

---

# 23. LLM Responsibilities

The LLM receives structured outputs from the CNN and questionnaire.

Example:

```json
{
  "predicted_class": "melanoma",
  "confidence": 0.84,
  "symptoms": {
    "recent_change": true,
    "bleeding": false,
    "pain": true
  }
}
```

The LLM may:

- Explain the model result
- Explain medical terminology in simple language
- Explain why professional evaluation may be appropriate
- Answer general follow-up questions
- Translate the explanation
- Maintain the application's safety language

The LLM must **not**:

- Invent symptoms
- Invent test results
- Claim to have examined the patient
- Convert model confidence into medical certainty
- Provide a definitive diagnosis
- Recommend starting/stopping prescription medication
- Override the application's safety layer

---

# 24. LLM Prompt

Use a controlled system prompt along the following lines:

```text
You are an AI health-information assistant.

You are not a doctor and must not provide a definitive diagnosis.

The computer-vision model has produced a classification.
Explain the result in simple language.

Do not invent symptoms, medical history, test results,
or clinical findings.

Do not convert model confidence into a claim about the
probability that the user has a disease.

Explain that the result is preliminary.

Use the supplied safety/triage category rather than
inventing your own medical urgency category.

Always recommend consultation with a qualified dermatologist.

If the user requests another supported language,
provide the same information in that language.

Do not recommend starting, stopping, or changing
prescription medication.
```

Refine the prompt after testing.

---

# 25. Deterministic Safety / Triage Layer

Do not let the LLM freely determine medical urgency.

Prefer:

```text
Questionnaire + model output
          ↓
Deterministic safety rules
          ↓
Controlled triage category
          ↓
LLM explains the category
```

Possible categories:

```text
Routine dermatologist consultation
Prompt dermatologist consultation
Urgent medical evaluation
```

The exact rules must be conservative, documented, and reviewed.

The LLM should explain a controlled recommendation rather than independently inventing one.

---

# 26. Bilingual Support

Support at least:

- English
- Hindi

Design the language layer so more languages can be added later.

The translation must preserve:

- Disease/class names
- Confidence values
- Safety warnings
- Triage category
- Meaning of the original explanation

The application should not silently change numerical values during translation.

---

# 27. Mandatory Safety Guardrail

Every result must display a fixed application-level warning.

Example:

```text
IMPORTANT

This result is generated by an AI screening system
and is not a medical diagnosis.

Please consult a qualified dermatologist for professional
evaluation, especially if the lesion is new, changing,
painful, bleeding, or otherwise concerning.
```

This warning must be implemented in the application itself.

Do not rely solely on the LLM to produce it.

---

# 28. Mobile Application

Recommended screens:

## Home

- Start screening
- About
- Safety information

## Image Capture

- Camera
- Gallery
- Preview
- Retake

## Questionnaire

Short structured questions.

## Processing

Display:

```text
Analyzing image...
```

Do not display fake progress percentages.

## Results

Display:

- Predicted class
- Confidence
- Original image
- Grad-CAM overlay
- Explanation
- Triage recommendation
- Fixed dermatologist warning

## AI Chat

Allow follow-up questions while preserving safety constraints.

---

# 29. Privacy

Treat uploaded skin photographs as sensitive information.

Prefer:

- Temporary image storage
- Automatic deletion of temporary files
- Minimal personal information
- No unnecessary cloud storage
- No permanent image storage unless genuinely required

If data is stored, document:

- What is stored
- Why it is stored
- Retention period
- Deletion process

Do not collect unnecessary:

- Names
- Phone numbers
- Addresses
- Personal identifiers

---

# 30. Error Handling

Handle:

- Invalid images
- Unsupported formats
- Corrupted images
- Very small images
- Low-quality images
- Backend unavailable
- CNN failure
- LLM unavailable
- Timeouts
- Missing questionnaire fields

Example:

```text
Unable to analyze the image.

Please upload a clearer image and try again.
```

Never silently fail.

---

# 31. GitHub Repository Structure

The repository must be organized so that a student, evaluator, or future developer can understand where every part of the project belongs. Keep the mobile application, backend, machine learning, documentation, scripts, and configuration clearly separated.

Recommended final repository:

```text
derma-screening/
│
├── mobile/                              # Flutter mobile application
│   └── flutter_app/
│       ├── lib/
│       │   ├── main.dart
│       │   ├── screens/                 # App screens
│       │   ├── widgets/                 # Reusable UI components
│       │   ├── services/                # API/client services
│       │   ├── models/                  # Dart data models
│       │   ├── providers/               # State management
│       │   ├── utils/                   # Helpers/constants
│       │   └── theme/                   # App theme
│       ├── assets/
│       │   ├── images/
│       │   └── icons/
│       ├── test/
│       ├── pubspec.yaml
│       └── README.md
│
├── backend/                             # FastAPI backend
│   ├── app/
│   │   ├── main.py                      # FastAPI entry point
│   │   ├── config.py                    # Configuration
│   │   ├── routes/                      # API endpoints
│   │   │   ├── health.py
│   │   │   ├── predict.py
│   │   │   └── chat.py
│   │   ├── services/                    # Business/runtime logic
│   │   │   ├── inference.py
│   │   │   ├── preprocessing.py
│   │   │   ├── gradcam.py
│   │   │   ├── triage.py
│   │   │   └── llm.py
│   │   ├── models/                      # Runtime model-loading code
│   │   ├── schemas/                     # Pydantic schemas
│   │   ├── safety/                      # Safety/guardrail logic
│   │   └── utils/
│   ├── tests/
│   ├── requirements.txt
│   ├── .env.example
│   └── README.md
│
├── ml/                                  # Machine-learning work
│   ├── configs/                         # Training/model configuration
│   │   ├── class_mapping.json
│   │   └── training_config.yaml
│   ├── preprocessing/                   # Dataset preparation
│   │   ├── prepare_dataset.py
│   │   ├── split_dataset.py
│   │   └── validate_dataset.py
│   ├── datasets/                        # Dataset metadata/scripts only
│   │   └── README.md
│   ├── training/                        # Training scripts
│   │   ├── train_resnet50.py
│   │   ├── train_efficientnet.py
│   │   └── common.py
│   ├── evaluation/                      # Evaluation scripts/results
│   │   ├── evaluate.py
│   │   ├── compare_models.py
│   │   └── generate_confusion_matrix.py
│   ├── explainability/                  # Grad-CAM implementation
│   │   └── generate_gradcam.py
│   ├── notebooks/                       # Exploratory notebooks
│   ├── checkpoints/                     # Local model checkpoints
│   │   └── .gitkeep
│   └── README.md
│
├── scripts/                             # Project-level utility scripts
│   ├── setup.sh
│   ├── run_backend.sh
│   └── run_training.sh
│
├── docs/                                # Project documentation
│   ├── architecture.md
│   ├── model_report.md
│   ├── dataset.md
│   ├── API.md
│   ├── gradcam.md
│   ├── llm.md
│   ├── safety.md
│   └── development.md
│
├── assets/                              # Public README/demo assets
│   ├── screenshots/
│   ├── diagrams/
│   └── demo/
│
├── tests/                               # Cross-component/integration tests
│
├── .github/
│   └── workflows/
│       └── ci.yml                       # Optional GitHub Actions CI
│
├── .gitignore
├── .env.example
├── README.md                            # Main GitHub project page
├── PROJECT_STATUS.md                    # Persistent Claude development state
├── LICENSE
└── CONTRIBUTING.md                      # Optional
```

## Repository Organization Rules

### `mobile/`
Contains only the Flutter application. Do not place Python, model-training, or backend code here.

### `backend/`
Contains only the API and runtime application/inference logic. The backend may load a trained model, but it must not contain notebooks or lengthy training scripts.

### `ml/`
Contains dataset preparation, training, evaluation, model comparison, Grad-CAM, and ML configuration. This keeps the machine-learning component independently understandable.

### `ml/notebooks/`
Use notebooks for exploration, visualization, and experiments. Important production logic must also exist in reusable Python scripts; do not make a notebook the only implementation of a critical pipeline.

### `ml/checkpoints/`
Store model checkpoints locally. Do not commit large `.pt`, `.pth`, `.ckpt`, or `.safetensors` files by default. Use Git LFS or a documented artifact/model-hosting strategy if weights must be distributed.

### Dataset storage
Do not upload HAM10000 or ISIC 2019 directly into GitHub. Keep actual datasets outside Git and document download/setup instructions in `ml/datasets/README.md`.

### `docs/`
Keep all technical documentation here so the repository is easy to navigate.

### `assets/`
Store public project screenshots, diagrams, and demonstration assets. Never commit private patient/lesion photographs.

### `PROJECT_STATUS.md`
This is mandatory and acts as persistent development memory between Claude sessions.

# 48. GitHub README Structure

The root `README.md` is the project's main GitHub landing page. Use this structure:

```text
# AI-Assisted Dermatology Screening

## Overview
## Key Features
## System Architecture
## Technology Stack
## Machine Learning Pipeline
## Dataset
## Model Comparison
## Grad-CAM Explainability
## LLM Integration
## Safety and Medical Disclaimer
## Repository Structure
## Installation
## Running the Backend
## Running the Mobile App
## Training the Models
## Evaluation
## Screenshots
## Limitations
## Future Work
## Contributors
```

Keep the README understandable to someone who has never seen the codebase. Include a simplified architecture diagram near the top.

# 49. Git and File Management Rules

Use meaningful commits:

```text
feat: add dermatology dataset pipeline
feat: implement ResNet50 training
feat: add EfficientNet comparison
feat: implement Grad-CAM
feat: add prediction API
feat: add symptom questionnaire
feat: integrate local LLM
feat: add Flutter result screen
fix: handle invalid image uploads
docs: update model evaluation
```

Do not commit:

```text
datasets/
*.pt
*.pth
*.ckpt
*.safetensors
.env
API keys
private images
large generated files
```

Keep generated caches and IDE files out of Git, including:

```text
__pycache__/
.venv/
.idea/
.vscode/
.dart_tool/
build/
.pytest_cache/
.ipynb_checkpoints/
```

The root `.gitignore` should cover Python, Flutter, model, dataset, environment, and operating-system artifacts.

---

# 48. Configuration

Do not hard-code configuration throughout the codebase.

Use configuration/environment variables for:

- Model path
- LLM endpoint
- Port
- Dataset paths
- Class mapping
- Thresholds
- Storage paths
- Debug mode

Never commit API keys or secrets.

Use `.env.example`, not a real `.env`, in the repository.

---

# 49. Testing

## Backend

Test:

- `/health`
- `/predict`
- `/chat`
- Invalid files
- Invalid inputs
- LLM failure
- Model failure
- Timeout handling

## ML

Test:

- Model loading
- Input shape
- Output class count
- Probability normalization
- Grad-CAM generation
- Checkpoint loading

## Frontend

Test:

- Camera
- Gallery
- Questionnaire
- API connection
- API failure
- Results
- Chat
- Safety warning visibility

## Integration

Test the full path:

```text
Mobile
 ↓
API
 ↓
Preprocessing
 ↓
CNN
 ↓
Grad-CAM
 ↓
Questionnaire
 ↓
Safety/Triage
 ↓
LLM
 ↓
Results
```

---

# 48. Experiment Tracking

Every model experiment should record:

```text
model
dataset version
class mapping
image size
augmentation
optimizer
learning rate
batch size
epochs
weight decay
random seed
validation metric
test metrics
training time
inference time
checkpoint
```

A CSV/JSON log is sufficient for this project.

---

# 49. Reproducibility

Set random seeds where practical.

Record:

- Python version
- PyTorch version
- CUDA version if applicable
- Package versions
- Dataset version/source
- Class mapping
- Random seed
- Hyperparameters

The training process should be repeatable.

---

# 48. Free-Computing Requirement

Prefer free resources:

- Google Colab Free
- Kaggle Notebooks
- Local CPU/GPU
- Open-source Python packages
- Local LLMs
- Free IDEs
- GitHub

Do not introduce paid APIs unless explicitly approved.

If a paid service appears necessary, first propose a free alternative.

Training should use checkpoints so that a runtime interruption does not require starting over.

---

# 49. Development Phases

Do not build everything simultaneously.

## Phase 1 — Repository Audit

Inspect the repository.

Create/update:

```text
PROJECT_STATUS.md
```

Deliver:

```text
Existing Architecture
Problems
Recommended Changes
Final Proposed Architecture
Implementation Plan
```

---

## Phase 2 — Dataset Pipeline

Implement:

- Loading
- Cleaning
- Label mapping
- Leakage-aware splitting
- Augmentation
- Class balancing

Test independently.

---

## Phase 3 — ResNet-50 Baseline

Implement:

- Transfer learning
- Training
- Validation
- Checkpointing
- Evaluation

Save:

```text
resnet50_best.pt
metrics
confusion matrix
classification report
```

---

## Phase 4 — EfficientNet

Implement and evaluate EfficientNet using the same split.

Compare both models.

Select the deployment model based on evidence.

---

## Phase 5 — Grad-CAM

Implement Grad-CAM for the selected model.

Generate and inspect heatmaps.

---

## Phase 6 — FastAPI

Implement:

```text
/health
/predict
```

Connect:

- Preprocessing
- Model inference
- Confidence
- Grad-CAM

Test with Postman/curl before connecting the mobile application.

---

## Phase 7 — Questionnaire

Add structured questionnaire support.

---

## Phase 8 — Safety/Triage Layer

Implement deterministic safety rules before LLM integration.

---

## Phase 9 — LLM

Connect the local/open-source LLM.

Implement:

```text
Prediction + Symptoms + Triage
            ↓
       Controlled Prompt
            ↓
            LLM
            ↓
Explanation / Conversation
```

Test for hallucination and unsafe outputs.

---

## Phase 10 — Flutter Application

Implement:

- Home
- Camera/gallery
- Questionnaire
- Processing
- Results
- Chat
- Safety information

---

## Phase 11 — Full Integration

Test the complete pipeline end-to-end.

---

## Phase 12 — Final Testing and Documentation

Complete:

- Unit tests
- Integration tests
- Model evaluation
- API testing
- Mobile testing
- Safety testing
- README
- Architecture documentation
- Model report
- Screenshots
- Limitations
- Future work

Only after the core system is stable should major UI polish be added.

---

# 48. Git Rules

Use meaningful commits:

```text
feat: add dermatology dataset pipeline
feat: implement ResNet50 training
feat: add EfficientNet comparison
feat: implement Grad-CAM
feat: add prediction API
feat: add symptom questionnaire
feat: integrate local LLM
feat: add Flutter result screen
fix: handle invalid image uploads
docs: update model evaluation
```

Do not commit:

```text
datasets/
*.pt
*.pth
*.ckpt
.env
API keys
large generated files
```

unless an explicit artifact-storage strategy has been configured.

---

# 49. Documentation Requirements

The final README must contain:

1. Project overview
2. Problem statement
3. Architecture
4. Features
5. Technology stack
6. Dataset information
7. Class mapping
8. Model architecture
9. Transfer-learning procedure
10. Training methodology
11. Evaluation results
12. ResNet-50 vs EfficientNet comparison
13. Grad-CAM explanation
14. LLM architecture
15. Safety/triage architecture
16. API documentation
17. Installation
18. Running instructions
19. Screenshots
20. Limitations
21. Future work

Never document features that have not actually been implemented.

---

# 48. Medical and Technical Limitations

The final documentation must state:

- The system is not a medical diagnostic device.
- It cannot replace a dermatologist.
- Smartphone photographs differ from controlled dermoscopic images.
- Camera quality and lighting affect performance.
- Dataset populations may not represent all skin tones or populations.
- Model confidence does not guarantee correctness.
- Rare classes may have lower performance.
- False positives and false negatives are possible.
- Grad-CAM is an interpretability aid, not proof of medically correct reasoning.
- The LLM can produce incorrect language and therefore operates behind safety constraints.

Do not market the system as detecting cancer with certainty.

---

# 49. Session Limit / Restart / Continuation Rule

This project will likely span multiple Claude sessions.

**Whenever the Claude session limit is reached, the session resets, or a new Claude session is started, continue the existing project instead of starting over.**

At the beginning of every new session:

1. Inspect the current repository.
2. Read `PROJECT_STATUS.md`.
3. Read the README.
4. Inspect recent code changes.
5. Check the current branch/status if Git is available.
6. Determine the last completed phase.
7. Determine what task was unfinished.
8. Continue from that exact state.

Do not recreate completed work.

Do not retrain models unnecessarily.

Do not replace working architecture without a documented reason.

Do not assume the project is starting from zero.

If the previous session ended halfway through a task, inspect the files and continue from the incomplete state.

---

# 48. PROJECT_STATUS.md — Mandatory Persistent Memory

Maintain:

```text
PROJECT_STATUS.md
```

After every significant development session, update it with:

```text
# Project Status

## Current Phase
...

## Completed
- ...

## Currently Working On
- ...

## Next Task
- ...

## Known Bugs
- ...

## Known Limitations
- ...

## Model Results
- ...

## Files Changed
- ...

## Dependencies Added
- ...

## Commands Used
- ...

## Important Decisions
- ...

## Session Continuation Notes
- ...
```

This file is the project's persistent development memory.

### Mandatory rule

**Every time the Claude session limit resets, restart/continue the project by reading `PROJECT_STATUS.md` and the existing codebase, then resume from the last recorded state.**

---

# 49. Training Checkpoints

Save checkpoints throughout training:

```text
ml/checkpoints/
├── resnet50_best.pt
├── efficientnet_best.pt
└── final_model.pt
```

Training must be resumable.

If Google Colab/Kaggle disconnects:

```text
DO NOT START FROM ZERO
        ↓
Load latest checkpoint
        ↓
Resume training
```

---

# 48. What Not to Do

Never:

- Fabricate accuracy numbers.
- Claim the model diagnoses cancer.
- Claim confidence equals clinical probability.
- Allow the LLM to invent medical facts.
- Let the LLM independently override the safety layer.
- Use patient/data leakage.
- Train on test images.
- Report training accuracy as final performance.
- Claim Grad-CAM proves medical reasoning.
- Store unnecessary personal data.
- Commit secrets.
- Rewrite functioning components without justification.
- Add unnecessary features before the core system works.
- Restart the entire project after a session reset.
- Use paid services without first considering a free alternative.

---

# 49. Final Deliverables

At completion, the repository should contain:

```text
1. Functional Flutter mobile application

2. Transfer-learning dermatology classifier

3. ResNet-50 baseline

4. EfficientNet experiment/comparison

5. Proper dataset pipeline

6. Leakage-aware train/validation/test split

7. Actual evaluation results

8. Confusion matrix and per-class metrics

9. Grad-CAM visualization

10. FastAPI backend

11. Structured symptom questionnaire

12. Deterministic safety/triage layer

13. Local/open-source LLM integration

14. Bilingual conversation

15. Mandatory dermatologist warning

16. Error handling

17. Automated/basic tests

18. Complete README

19. PROJECT_STATUS.md

20. Model training documentation

21. API documentation

22. Architecture documentation
```

---

# 48. First Action — Start Here

Before implementing anything:

### Step 1
Inspect the complete existing repository.

### Step 2
Identify what is already implemented.

### Step 3
Create or update:

```text
PROJECT_STATUS.md
```

### Step 4
Produce the technical assessment:

```text
Existing System
       ↓
Problems
       ↓
Recommended Changes
       ↓
Final Architecture
       ↓
Implementation Phases
```

### Step 5
Present the proposed changes before making major architectural changes.

### Step 6
Once the plan is established, implement phase-by-phase.

Do not attempt to implement the entire application in one response/session.

---

# 49. Priority Order

When deciding what to work on next, follow:

```text
1. Correctness
2. Data integrity
3. Reproducibility
4. Medical safety
5. Core functionality
6. Model performance
7. Explainability
8. API reliability
9. LLM integration
10. Mobile UX
11. Performance optimization
12. Visual polish
```

The final project should be a technically credible, reproducible B.Tech project that can be demonstrated end-to-end and whose machine-learning claims are supported by actual experimental evidence.

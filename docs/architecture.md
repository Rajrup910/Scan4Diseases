# Architecture

## The one idea

Three components, three different kinds of authority:

| Component | Decides | Can it be wrong? | Is it auditable? |
|---|---|---|---|
| CNN | which category the lesion resembles | yes, and it reports how confident | via metrics on a held-out split |
| Rule layer | medical urgency | only if a rule is wrong | yes — numbered rules, unit tests |
| LLM | wording and language | yes, frequently | no — so it decides nothing |

Most "AI doctor" projects collapse these into one: an LLM is handed an image or a label and
asked to say how worried the user should be. That produces urgency judgements that vary
between runs, cannot be tested, and cannot be defended in a review. Here, urgency is a pure
function that a reviewer can read in one sitting.

## Request flow

```
POST /predict  (multipart: image + questionnaire JSON + language)
        │
        ▼
1. decode_image()                     preprocessing.py
        │   size / format / truncation / EXIF rotation / RGB
        │   FAIL → 422 with a specific reason
        ▼
2. assess_quality()                   quality.py
        │   Laplacian variance (blur), mean luminance (exposure), resolution
        │   FAIL → 422 "image quality is insufficient" + how to fix it
        ▼
3. InferenceService.predict()         inference.py
        │   resize 256 → centre-crop 224 → ImageNet normalise
        │   forward pass → logits → temperature → softmax
        │   Grad-CAM on the last conv block, in the same pass
        │   NO MODEL → 503 (never a fabricated prediction)
        ▼
4. triage.assess()                    triage.py       ◄── URGENCY DECIDED HERE
        │   pure function: prediction + probabilities + questionnaire → category
        ▼
5. store.save_overlay()               storage.py
        │   only the heatmap is written; the photograph never touches disk
        ▼
6. LLMService.explain()               llm.py
        │   structured JSON in → four fixed sections out
        │   → safety filter                            filters.py
        │   FAIL → explanation_available: false, everything else still returned
        ▼
7. get_disclaimer()                   disclaimer.py
        │   constant text, attached unconditionally
        ▼
   200 PredictionResponse
```

Step 4 happens before step 6. That ordering *is* the safety argument: no generated text can
influence the urgency, because the urgency already exists when the model is called.

## Package boundaries

```
ml/                     backend/
├── preprocessing/      ├── app/routes/       thin HTTP layer, no logic
├── training/           ├── app/services/     preprocessing, quality, inference,
├── evaluation/         │                     gradcam, triage, llm, storage
└── explainability/     ├── app/models/       runtime model + class mapping loading
                        ├── app/schemas/      the API contract
                        └── app/safety/       disclaimers + output filter
```

**The backend never imports `ml`.** It duplicates three small things — the model factory,
the eval preprocessing transform, and Grad-CAM — so the API server can deploy without
scikit-learn, matplotlib, pandas or the training code. On a free CPU tier that is a real
saving, and section 21 of the specification requires the separation anyway.

Duplication that can drift is a liability, so [`tests/test_parity.py`](../tests/test_parity.py)
asserts:

- both class-mapping loaders agree on version, order and malignancy tiers
- both eval transforms produce **bit-identical tensors**
- both model factories produce identical `state_dict` keys and shapes
- both Grad-CAM implementations produce numerically identical maps
- a checkpoint written by training loads in the backend

The preprocessing parity test is the important one. A train/serve preprocessing mismatch
raises no error — the model just quietly performs worse in production than in evaluation,
and you find out months later, if ever.

## Shared contract: `class_mapping.json`

```
              ml/configs/class_mapping.json
                (version-controlled, single source of truth)
                 │              │              │
        training │     backend  │      report  │
                 ▼              ▼              ▼
          class order    display names   the table in the README
          num_classes    translations
                         malignancy tier → triage rules
```

A checkpoint records the class codes it was trained on. Loading refuses if they disagree
with the current mapping — serving predictions where index 4 means `mel` to the model and
something else to the API is the kind of bug that produces confidently wrong medical output.

## State

The backend is stateless per request. Everything long-lived is built once in the FastAPI
lifespan and stored on `app.state`:

| Object | Why it is a singleton |
|---|---|
| `InferenceService` | loading a 90 MB checkpoint per request would be absurd |
| `LLMService` | one pooled `httpx.AsyncClient` |
| `TemporaryStore` | plus a background janitor purging expired overlays every 5 min |

Grad-CAM hooks are registered and removed per call via a context manager. A forward hook
left attached to a model reused across thousands of requests is a slow memory leak, and
`test_gradcam_hooks_are_removed` guards against it.

## Deployment shapes

**Development / demo** — everything on the laptop; the phone connects over the same WiFi to
the LAN IP. GPU inference, local Ollama. This is a completely legitimate demo setup.

**Phase 2** — the CNN moves to Hugging Face Spaces (free CPU, ONNX). The LLM cannot follow:
the free tier has no GPU. Either it stays on the laptop behind a free Cloudflare Tunnel, or
a free hosted API stands in. State this openly in the limitations section; examiners respect
a known constraint far more than a vague claim about scalability.

## Error handling

Every failure produces a stable `error` code and a user-safe `message`. Unexpected
exceptions are logged in full with a short incident id and reduced to a generic message on
the way out — `test_errors_never_leak_internals` asserts no filesystem path, module name or
traceback appears in any client-visible response.

## Reading order

1. [`backend/app/services/triage.py`](../backend/app/services/triage.py) — the interesting part
2. [`backend/app/routes/predict.py`](../backend/app/routes/predict.py) — the pipeline, in order
3. [`ml/preprocessing/split_dataset.py`](../ml/preprocessing/split_dataset.py) — why the numbers are trustworthy
4. [`ml/explainability/gradcam.py`](../ml/explainability/gradcam.py) — the explainability component

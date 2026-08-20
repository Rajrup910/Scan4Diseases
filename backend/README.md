# Backend

FastAPI service bridging the mobile application and the AI components.

```bash
.venv/Scripts/python.exe -m uvicorn backend.app.main:app --reload --port 8000
```

Docs at `http://localhost:8000/docs`. Full endpoint reference: [`docs/API.md`](../docs/API.md).

## Layout

```
app/
├── main.py            application factory, lifespan, CORS, janitor task
├── config.py          all settings, from environment / .env
├── dependencies.py    service accessors
├── routes/            health.py  predict.py  chat.py  media.py
├── services/          preprocessing  quality  inference  gradcam  triage  llm  storage
├── models/            runtime model loading + class mapping
├── schemas/           Pydantic request/response contract
├── safety/            disclaimer.py (constants)  filters.py (output filter)
└── utils/errors.py    uniform error handling
tests/
```

Routes stay thin — parse, call services, assemble the response. Logic lives in `services/`,
which keeps it testable without HTTP.

## The one thing to understand

`services/triage.py` decides medical urgency, and it is a **pure function**. It runs before
the LLM is called. No generated text can influence the category.

```
inference → triage rules → LLM explains the category → fixed disclaimer
```

Read [`docs/safety.md`](../docs/safety.md) before changing anything in `services/triage.py`
or `safety/`.

## Running without a trained model

`/predict` returns **503** when no checkpoint is loaded. That is deliberate — a screening
API that invents predictions is worse than one that is honestly unavailable.

For UI development before training finishes:

```bash
ALLOW_STUB_MODEL=true
```

Responses are then flagged `"stub": true`, `/health` reports `stub_mode: true`, and a
warning is logged on every call. **Never enable it for a demo or evaluation.**

## Configuration

Copy `.env.example` from the repository root to `backend/.env` and edit. Nothing is
hardcoded; nothing secret is committed.

The settings that change behaviour most:

| Variable | Default | Effect |
|---|---|---|
| `MODEL_CHECKPOINT` | `ml/checkpoints/deployed_model.pt` | which model is served |
| `MODEL_ARCH` | `efficientnet_b0` | must match the checkpoint |
| `ALLOW_STUB_MODEL` | `false` | synthetic predictions |
| `LOW_CONFIDENCE_THRESHOLD` | `0.60` | below this, triage escalates |
| `CALIBRATION_TEMPERATURE` | `1.0` | from `evaluate.py --calibrate` |
| `STORAGE_TTL_MINUTES` | `15` | `0` disables overlay storage |
| `LLM_ENABLED` | `true` | `false` skips the LLM cleanly |

## Why this package does not import `ml`

So the API server can be deployed without scikit-learn, matplotlib, pandas or any training
code — a real saving on a free CPU tier, and required by section 21 of the specification.

Three things are therefore duplicated: the model factory, the eval preprocessing transform,
and Grad-CAM. [`tests/test_parity.py`](../tests/test_parity.py) asserts they cannot drift —
including that both preprocessing paths produce **bit-identical** tensors, because a
train/serve preprocessing mismatch raises no error and just quietly degrades accuracy.

## Tests

```bash
.venv/Scripts/python.exe -m pytest backend/tests -v
```

They run **without** a checkpoint and **without** Ollama, so they pass on a fresh clone and
in CI.

| File | Covers |
|---|---|
| `test_triage.py` | every rule, plus the escalation-only and missing-≠-no invariants |
| `test_safety.py` | output filter, disclaimers, confidence phrasing |
| `test_api.py` | all endpoints, every error path, path traversal, no internal leakage |

## Privacy

The uploaded photograph is never written to disk. Only the Grad-CAM overlay is stored, under
a 128-bit random name, deleted after the TTL, on shutdown, and opportunistically on write.
`/chat` is stateless. No personal identifiers are collected anywhere.

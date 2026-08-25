# Scan4Disease — Demo Showcase & Preview

A single reference that walks every **general path** and every **edge case** across the two
surfaces of the product: the **Flutter mobile app** (patient-facing) and the **FastAPI/Jinja2
clinician web portal** — plus the safety, rate-limiting, and appearance behaviours that sit
behind them.

> Scope note: this preview documents behaviour as of the full-stack audit dated **2026-08-25**,
> which added the glossy-emerald dark theme + persisted theme toggle, smoother on-media type
> and section headers, app-wide page transitions, the SQLite `busy_timeout`/pool hardening, and
> the high-contrast 404 glow fix. See the changelog at the end.

---

## 1. Verification dataset

Ten curated lesions — five HAM10000 (dermatoscopic) and five PAD-UFES-20 (clinical smartphone)
— covering distinct diagnostic classes are assembled by
[`scripts/prepare_demo_dataset_grid.py`](scripts/prepare_demo_dataset_grid.py) into a single
labelled board at [`demo_test_samples/demo_verification_grid.png`](demo_test_samples/demo_verification_grid.png),
with the source files copied to `demo_test_samples/manual_verification/`.

| Row | Source | Classes shown | Capture style |
|---|---|---|---|
| Top | HAM10000 | `mel`, `bcc`, `akiec`, `nv`, `bkl` | Dermatoscope |
| Bottom | PAD-UFES-20 | `MEL`, `BCC`, `ACK`, `NEV`, `SCC` | Smartphone clinical |

Notes are colour-coded to the triage palette: **red = malignant**, **amber = pre-malignant**,
**teal = benign**.

**Regenerate & verify:**

```bash
python scripts/prepare_demo_dataset_grid.py
```

The script always rebuilds the grid. When it is run inside the backend environment (with
`torch` installed) it additionally streams each of the ten images through the in-process
`POST /predict` and logs, per image: HTTP status, pipeline outcome, predicted class, confidence,
triage category, and Grad-CAM activation. Where `torch`/FastAPI are not importable it prints a
clear `[SKIP]` and still produces the grid, so it is safe to run anywhere.

---

## 2. Mobile app — general paths

| # | Flow | What to show | Expected result |
|---|---|---|---|
| 1 | **Launch / restore** | Cold start | Opens straight to Home for a signed-in user, in the last-used **language** and **light/dark theme** (all restored before first frame). |
| 2 | **Sign in** | `raj@gmail.com` / `12345678` | Auth gate clears to the home shell; preloaded screening history is present. |
| 3 | **Home → slide to start** | Drag the slide-to-start control | Full-viewport emerald wash crests, tab silently swaps to **New screening**, wash reverses out. |
| 4 | **Capture / upload** | Camera or gallery | Photo guide shown; image staged for screening. |
| 5 | **Questionnaire** | Answer / skip symptoms | Optional — skipping is valid and does not block screening. |
| 6 | **Result** | Submit a lesion photo | Predicted class + calibrated confidence, **all-class score** breakdown, **Grad-CAM** overlay with focus description, and a triage card. |
| 7 | **AI explanation** | Read the four-section explanation | "What the scan found / could mean / how urgent / what to do", in the chosen language. |
| 8 | **Chatbot** | Ask a follow-up | Warm, practical answers grounded in the result; suggested questions provided. |
| 9 | **Reports** | Open Reports tab | Screening history list; open a report for detail; compare two reports. |
| 10 | **Share with doctor** | Share a report | Generates a shareable clinician link/record. |
| 11 | **Skin guide** | Care & Tools tabs | ABCDE rule, common conditions, glossary, sun protection, skin-type quiz. |
| 12 | **Find a dermatologist** | Nearby doctors | Location-based dermatologist lookup. |
| 13 | **Self-exam reminder** | Monthly prompt | Appears once when due; "Open guide" jumps to Care & Tools. |
| 14 | **Profile** | You tab | Screening stats, **Dark mode toggle**, explanation language, reminder, privacy, sign out. |

### 2a. Appearance (new)

| Case | Steps | Expected |
|---|---|---|
| Toggle to dark | Profile → **Dark mode** switch on | App-wide switch to glossy emerald dark theme (`#0F1117` canvas, `#161920` glass cards, `#2DD4BF` teal accent); the moon icon and subtitle update. |
| Toggle to light | Switch off | Returns to the clinical light theme. |
| Persistence | Kill & relaunch | Re-opens in the last-chosen mode (stored in secure storage, same store as auth/language). |
| First run | Fresh install | Follows the OS light/dark setting (`ThemeMode.system`) until the user picks explicitly. |
| Transitions | Push any screen (result, chat, report detail) | Smooth fade + slight upward glide + subtle scale settle, consistent on Android and iOS. |
| Headers over video | Any section header / floating title | Soft frosted "pill" headers and triple-halo on-media type stay readable over the moving backdrop — no jagged outline. |

### 2b. Language

| Case | Steps | Expected |
|---|---|---|
| English explanation | Language = English | Explanation + chat replies in English; numbers/category names preserved. |
| Hindi explanation | Language = हिन्दी | Same result content translated to Hindi; the medical category name and confidence value are kept verbatim. |

---

## 3. Mobile app — edge cases

| Trigger | Backend code / HTTP | User-facing behaviour |
|---|---|---|
| **Blurry / dark / overexposed / tiny image** | `image_quality_insufficient` · 422 | Rejected *before* inference with actionable advice (e.g. "hold steadier", "add light"). No cost spent on the model. |
| **Not a skin photo** (object, scene) | router `not_skin` → `no_lesion_detected` · 422 | "We couldn't find a skin lesion… take a clear, close-up picture." |
| **Healthy skin** | router `healthy` → outcome `healthy` · 200 | Fixed, application-owned guidance; deliberately **not** phrased as an all-clear; no disease class, no Grad-CAM, no LLM. |
| **Wound / abrasion** | router `other_damage` · 200 | Routed to non-lesion wound-care advice via the safety gate rather than forced into a disease class. |
| **Empty / corrupt upload** | `empty_image` / decode error · 422 | Clear "upload a clearer image" message. |
| **Low model confidence** | triage `low_confidence` flag | Triage still decided by rules; explanation notes uncertainty; dermatologist referral emphasised. |
| **Explanation unavailable** (LLM offline/timeout) | `explanation_available: false` · 200 | Classification, Grad-CAM, **and triage still returned** — only the prose explanation is absent. The clinically meaningful result never depends on the LLM. |
| **Chat rate-limited** | `rate_limit_exceeded` · **429** | "Rate limit exceeded (10 requests per minute)…"; the app surfaces a wait-and-retry message. |
| **Chat server busy** | concurrency cap (3) · 429 | "Server is busy handling other LLM requests. Please try again shortly." |
| **Chat LLM offline** | `llm_unavailable` · 503 | An offline LLM looks offline (no fabricated answer). |
| **Unsafe LLM output** | safety filter | Blocked output is replaced by a structured clinical template (ABCDE, next steps) — still helpful, never unsafe. |
| **Model missing** | `model_unavailable` · 503 | "The screening model is not available right now. Please try again later." |
| **Inference error** | `inference_failed` · 500 | Generic, internals-safe message; no stack trace leaks. |
| **Wrong login** | `invalid_credentials` | Rejected without revealing which field failed. |
| **Register existing email** | `email_taken` | Clear, non-enumerating message. |

---

## 4. Clinician web portal — general paths

| # | Flow | Route | Expected |
|---|---|---|---|
| 1 | **Sign in** | `/portal/login` | Any demo doctor (e.g. `dr.rao@example.com` / `Str0ngPass!`). |
| 2 | **Patient roster** | `/portal/patients` | Directory of patients linked to the clinician. |
| 3 | **Patient reports** | `/portal/patients/{id}` | That patient's screening reports. |
| 4 | **Report detail** | report view | Class, confidence, all-class scores, triage, Grad-CAM overlay, disclaimer. |
| 5 | **Dark mode** | portal theme | `:root[data-theme="dark"]` palette mirrors the app dark theme. |
| 6 | **API docs** | `/docs` | OpenAPI/Swagger for the same endpoints. |

---

## 5. Clinician web portal — edge cases

| Trigger | HTTP | Behaviour |
|---|---|---|
| **Unknown / expired URL** | 404 | Styled clinical 404 page (`404.html`) with a **high-contrast luminous "404" glow** (retuned `--mint` token + dual drop-shadow), a **context-aware primary action** (Patient directory when signed in, Clinician sign-in otherwise), a real **Go back** button (`history.back()` with a safe fallback), and an **API docs** link — no redundant buttons. |
| **Accessing another clinician's patient** | `not_authorized` / no-access page | Access is scoped; a friendly no-access page is shown instead of raw data. |
| **Record not found** | `not_found` · 404 | Same styled 404 as above. |
| **Shared image at rest** | — | Patient-shared images are Fernet-encrypted at rest (`IMAGE_ENCRYPTION_KEY`). |

---

## 6. Safety & robustness (behind both surfaces)

- **Ordering is the safety argument.** Quality gate → router → CNN + Grad-CAM → **deterministic triage** → LLM → fixed disclaimer. Urgency is fixed *before* the language model is ever called, so no generated text can change it.
- **Triage is rule-based**, not model-authored; the LLM only rewords a decision already made.
- **Fixed disclaimer** is always present and application-owned — never generated.
- **LLM rate limiting:** sliding-window **10 RPM per client IP** + **3 max concurrent** generations (`LLMRateLimiter`). `/predict` degrades gracefully (`explanation_available: false`); `/chat` returns **HTTP 429** with a clear reason.
- **Database:** SQLite in **WAL** mode with `synchronous=NORMAL`, a **30s `busy_timeout`** so concurrent writers queue instead of erroring under load, `foreign_keys=ON`, and a bounded connection pool (`pool_size=10`, `max_overflow=20`, `pool_recycle=1800`, `pool_pre_ping`). Sync DB handlers run in FastAPI's threadpool, off the inference/LLM event loop.
- **Privacy:** the uploaded photograph is never persisted — only the Grad-CAM overlay is stored, transiently; `/chat` is stateless (the client echoes context back).

---

## 7. Suggested 5-minute demo script

1. Sign in on mobile as `raj@gmail.com` → Home → **slide to start**.
2. Upload `demo_test_samples/manual_verification/ham_mel_*.jpg` (Melanoma) → show class, all-class scores, **Grad-CAM**, **Urgent** triage, explanation.
3. Ask the chatbot "how urgent is this?" → grounded answer.
4. Profile → flip **Dark mode** → note the glossy emerald theme + smooth transition; relaunch to show it persists.
5. Upload `pad_ACK_*.png` (Actinic Keratosis) → **pre-malignant / prompt** triage.
6. Upload the wound sample → **safety gate** routes to wound-care advice (edge case).
7. Portal: sign in as `dr.rao@example.com` → open the patient's report → then hit a bad URL to show the **glowing 404** with context-aware navigation.

---

## 8. Changelog — 2026-08-25 full-stack audit

- **Mobile dark theme:** new `ThemeService` (persisted light/dark/system), full glossy-emerald `Themes.darkTheme`, theme-aware Profile screen with a **moon/sun `Switch.adaptive` toggle**, wired through the root `MaterialApp` (`themeMode` + `darkTheme`).
- **Type & headers:** smoother triple-Gaussian `onMedia` halo (and a dark `onMediaDark`) so every floating header sharpens automatically; new `sectionHeaderStyle` + frosted `sectionHeaderPill` helpers.
- **Transitions:** app-wide `SmoothPageTransitionsBuilder` (fade + upward glide + scale settle) applied to both themes.
- **Backend:** SQLite `busy_timeout` + `foreign_keys` pragmas and explicit connection-pool sizing; confirmed WAL, 429 chat rate-limiting, and graceful `/predict` fallback.
- **Portal 404:** retuned `--mint` token and dual drop-shadow for a high-contrast luminous "404"; non-redundant, context-aware navigation verified.
- **Demo tooling:** new `scripts/prepare_demo_dataset_grid.py` → 10-image verification grid + optional in-process `/predict` scoring.

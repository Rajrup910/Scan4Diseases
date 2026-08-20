# Project Status — Scan4Disease App (Flutter client)

## Current Phase
Integrated with the Scan4Disease FastAPI backend. Ready to run once Flutter is installed.

## Completed
- Flutter 3.44 compatibility fixes; cross-platform image preview.
- Upload / camera / gallery flow.
- **Questionnaire rewired to the backend contract** — enum values now match the
  `Questionnaire` schema exactly (`duration`, `size_change`, `sun_exposure`), so
  `/predict` no longer returns HTTP 422 on submit.
- **API client (`DiagnoseAPI.dart`) integrated**: multipart image + questionnaire JSON
  + `language`; strips unanswered fields; resolves the relative `gradcam_url` to an
  absolute one; surfaces the backend's user-safe error message.
- **Result screen (`ResultData.dart`) rebuilt** to the real response contract:
  - `probabilities` handled as a LIST (was wrongly treated as a Map).
  - `triage` handled as an OBJECT — colour-coded card (green/amber/red) with label,
    advice and the "why this recommendation" reasons (was `.toString()` on a Map).
  - Grad-CAM overlay displayed with a plain-language caption.
  - `predicted_name` headline + model-score bar with correct "not a probability" wording.
  - Low-confidence note, stub-mode banner, backend disclaimer.
- Smart base URL (`config.dart`): web/desktop -> 127.0.0.1:8000, Android emulator ->
  10.0.2.2:8000, override via `--dart-define=API_BASE_URL=...`.
- Removed dead `server/` (old Node backend with committed secrets) and `temp.dart`.
- Contract verified end-to-end against the trained ResNet-50 + live backend (Python
  harness replaying the app's exact request): 200 OK, all fields present.

## Currently Working On
- Nothing pending in code. Blocked only on the Flutter SDK being installed to run it.

## Next Task
1. Install Flutter (see repo `docs/development.md` §1.6 or the run steps below).
2. `flutter pub get` in this folder.
3. Start the backend (`scripts/run_backend.ps1` from the repo root — model already wired
   via the repo `.env`).
4. `flutter run -d chrome` (easiest) or `-d windows`, or an Android emulator.

## Known Bugs / Limitations
- Reports are in-memory and reset on restart.
- Grad-CAM shows only when the backend returns a URL; it expires after a short TTL.
- Camera on web/desktop falls back to file picker (guarded in `main.dart`).
- Backend must be running and reachable at the resolved base URL.

## Important Decisions
- Never show a fabricated diagnosis when the backend is unavailable — the app surfaces
  the real error and shows no result.
- The fixed medical disclaimer is shown on every result (from the backend, with a local
  fallback).
- Urgency is taken verbatim from the backend's deterministic triage — the app does not
  compute or override it.

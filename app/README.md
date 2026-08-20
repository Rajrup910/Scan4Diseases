# Scan4Disease — Mobile App (Flutter)

The screening client for **Scan4Disease**. It captures or picks a skin-lesion photo,
collects a short structured symptom questionnaire, sends both to the FastAPI backend, and
renders the classification, Grad-CAM heatmap, deterministic triage, and the backend's fixed
medical disclaimer.

> This app is a screening and educational aid, **not** a diagnostic device. It never
> diagnoses, and every result recommends consulting a qualified dermatologist.

See the root [`README.md`](../README.md) for the full system architecture and the backend.

## Structure

```
app/
├── lib/
│   ├── main.dart              app entry; loads the persisted backend URL before first frame
│   ├── config.dart            runtime-configurable backend base URL (ApiConfig)
│   ├── LandingPage/           first-run landing
│   ├── Screens/
│   │   ├── Auth/              login / auth gate (JWT)
│   │   ├── Home/              home dashboard
│   │   ├── Upload/            camera · gallery · preview · questionnaire · results
│   │   ├── Reports/           saved report view
│   │   ├── Chat/              follow-up assistant
│   │   ├── Doctors/           find a nearby dermatologist (OpenStreetMap Nominatim)
│   │   ├── Guide/             skin self-exam guide
│   │   └── theme.dart         shared theme
│   └── services/              api client, auth, chat, localisation, doctor lookup, reminders
├── assets/                    icons, illustrations, placeholders
├── android/ ios/ web/ …       Flutter platform scaffolds
└── test/                      widget/unit tests
```

## Running

Requires the Flutter SDK (3.4x) and a configured device or emulator.

```bash
flutter pub get
flutter run
```

Build a debug APK:

```bash
flutter build apk --debug
```

## Pointing the app at the backend

The base URL resolves in this order (first non-empty wins), so IP changes never require a
rebuild:

1. **Runtime override** — typed into the in-app *Server settings* dialog and persisted.
2. **Compile-time override** — `flutter run --dart-define=API_BASE_URL=http://<ip>:8000`.
3. **Platform default** — `http://127.0.0.1:8000`.

- **Physical phone:** use the laptop's LAN IP (same Wi-Fi, backend bound to `0.0.0.0`), or
  run `adb reverse tcp:8000 tcp:8000` over USB and keep the `127.0.0.1` default.
- **Android emulator:** the laptop is `10.0.2.2`.

## Client safety obligations

These are not style preferences — they come from the system's safety architecture and a
review will check them.

1. **Always display `disclaimer`**, unmodified and untruncated. It is produced by the
   backend, never by the language model.
2. **Never render `confidence` as a disease probability.** Say "the model gave its highest
   score to this category", never "you have an X% chance of this".
3. **`triage.category` is authoritative.** Do not re-derive urgency on the device.
4. **Handle `explanation_available: false`.** The LLM is optional; always show the
   classification, heatmap, and triage regardless.
5. **Check `stub`.** If true, the values are placeholders — say so on screen.
6. **Handle every documented error code** with an actionable message. The backend's
   `message` field is already localised and safe to display verbatim.

The API contract is documented in [`../docs/API.md`](../docs/API.md).

## Testing

```bash
flutter analyze
flutter test
```

Manually verify: camera · gallery · questionnaire · API success · API failure · offline ·
results rendering · chat · **disclaimer visibility on every result screen**. Test on at
least two physical phones — camera variance between devices is significant and is a
limitation worth quantifying in the report.

See [`PROJECT_STATUS.md`](PROJECT_STATUS.md) for the current integration state.

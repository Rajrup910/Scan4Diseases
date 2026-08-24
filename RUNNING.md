# Running Scan4Disease

Everything you need to start the **backend + web portal** and the **Flutter phone app**, plus the phone↔laptop tunnel and fixes for the usual snags. All commands are for **Windows PowerShell**, run from the repo root `C:\Users\RAJ\Downloads\Capstone` unless noted.

---

## What the project is

| Piece | Stack | Where it runs |
|---|---|---|
| **Backend API** | FastAPI (Python) | `http://localhost:8000` |
| **Clinician web portal** | Jinja2 + vanilla CSS/JS, served **by the backend** | `http://localhost:8000/portal/login` |
| **Patient mobile app** | Flutter (Dart) | on the phone, talks to the backend |

The web portal is part of the backend — starting the backend starts the portal too. There is no separate "frontend server".

---

## 0. One-time setup (only the first time, or after a fresh clone)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1
```

Populate the portal with demo data (one doctor, patients, reports):

```powershell
.\.venv\Scripts\python.exe scripts\seed_portal_demo.py
```

**Add adb to PATH permanently** (so `adb` works in every terminal):

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:LOCALAPPDATA\Android\Sdk\platform-tools", "User")
```

Close and reopen the terminal after this.

---

## 1. Start the backend + web portal

Open a PowerShell window at the repo root and run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1
```

Leave it running. It prints:

- Web portal → **http://localhost:8000/portal/login**
- API docs → http://localhost:8000/docs
- Health → http://localhost:8000/health
- A LAN URL for the phone (Wi-Fi option, see below)

**Demo Logins for Presentation & Testing:**

- **Clinician Web Portal** (`http://localhost:8000/portal/login`):
  - **Doctor 1:** `dr.rao@example.com` / `Str0ngPass!` (Dr. A. Rao — Reg: MH-12345)
  - **Doctor 2:** `dr.mehta@example.com` / `Str0ngPass!` (Dr. Sunita Mehta — Reg: KA-67890)
  - **Doctor 3:** `dr.kapoor@example.com` / `Str0ngPass!` (Dr. Vikram Kapoor — Reg: DL-98765)
  - **Doctor 4:** `dr.nambiar@example.com` / `Str0ngPass!` (Dr. Priya Nambiar — Reg: KL-45678)
  - **Doctor 5:** `dr.deshmukh@example.com` / `Str0ngPass!` (Dr. Rajesh Deshmukh — Reg: MH-54321)
  - **Doctor 6:** `dr.sen@example.com` / `Str0ngPass!` (Dr. Ananya Sen — Reg: WB-34567)
- **Patient Mobile App / API** (`http://localhost:8000/auth/login`):
  - **Patient 1:** `raj@gmail.com` / `12345678` (Raj)
  - **Patient 2:** `ananya@gmail.com` / `12345678` (Ananya Verma)
  - **Other Demo Patients:** `priya@example.com`, `sam@example.com`, `jordan@example.com` / `12345678`


Useful flags: `-Port 8080` (if 8000 is busy), `-NoReload`.

To view the portal, just open **http://localhost:8000/portal/login** in a browser. If the page looks stale after a change, hard-refresh with **Ctrl + F5**.

---

## 2. Connect the phone (reverse tunnel)

The app is hard-coded to `http://127.0.0.1:8000`. On the phone that means the phone itself, so `adb reverse` maps it to the laptop's backend over the USB cable.

**Before this:** phone plugged in via a **data** USB cable, **USB debugging ON** (Settings → Developer options), and the "Allow USB debugging?" prompt accepted on the phone.

Easiest — run the helper (works even if `adb` isn't on PATH):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1
```

Wait for **`Verified from the phone: backend is reachable…`**.

If the backend is on a different port, e.g. 8080:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1 -BackendPort 8080
```

Or do it manually in one line:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8000 tcp:8000
```

> **Re-run this whenever the app shows "Connection refused."** The tunnel drops on phone sleep, adb restart, or laptop reboot. No rebuild needed.

**No-cable alternative (same Wi-Fi):** in the app's login screen tap **⚙ Server settings**, enter `http://<laptop-LAN-IP>:8000` (the backend window prints the IP), and skip the tunnel. Windows Firewall must allow inbound TCP 8000.

---

## 3. Run the Flutter app

### Option A — VS Code (simplest)

1. Bottom-right status bar: make sure the selected device is **OnePlus CPH2585** (click it to switch if it shows the wireless entry or Windows/Chrome).
2. Press **F5** (Run ▸ Start Debugging). VS Code runs `flutter pub get` and `flutter run` for you.

### Option B — terminal

```powershell
cd app
flutter pub get
flutter run
```

Pick **OnePlus CPH2585** from the device list.

> Run `flutter pub get` after pulling changes that touch `pubspec.yaml` (e.g. the video background needs the `video_player` plugin).

Hot reload: `r` · Hot restart: `R` · Quit: `q`.

Build a release APK:

```powershell
cd app
flutter build apk --release
```

---

## Every-session order

1. **Backend** — `scripts\run_backend.ps1` (wait for "Application startup complete").
2. Plug in phone, accept the USB-debugging prompt.
3. **Tunnel** — `scripts\connect_phone.ps1` (must say "Verified from the phone").
4. **App** — VS Code **F5**, or `cd app; flutter run`.
5. **Portal** — open `http://localhost:8000/portal/login` in a browser.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| App: **Connection refused / timed out** | Re-run `scripts\connect_phone.ps1`. Make sure the backend window is running. |
| `'adb' is not recognized` | Use the full path `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" …`, or add it to PATH (step 0). |
| `flutter run` lists only Windows/Chrome/Edge (no phone) | Phone not on adb. `adb kill-server; adb start-server; adb devices` — you want a line ending in `device`. If `unauthorized`, accept the prompt on the phone. If missing, replug a **data** cable and set USB mode to **File transfer**. |
| A ghost device like `adb-xxxx not found` | Leftover **Wireless debugging** entry. On the phone turn **Developer options → Wireless debugging OFF**, then `adb disconnect`. |
| `cd app` fails with "path … app\app not found" | You're already inside `app\`. Don't `cd app` again — just run `flutter run`. |
| Port 8000 already in use | Start backend on another port: `scripts\run_backend.ps1 -Port 8080`, then `scripts\connect_phone.ps1 -BackendPort 8080`. |
| Portal page looks stale after an edit | Hard-refresh the browser: **Ctrl + F5**. |
| Portal has no patients/reports | Re-run `.\.venv\Scripts\python.exe scripts\seed_portal_demo.py` (safe to run again). |
| Reset the app's backend URL | In the app's **⚙ Server settings** dialog, tap **Reset to default**. |

---

## Quick reference

```powershell
# backend + web portal
powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1

# phone tunnel (re-run on "Connection refused")
powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1

# flutter app
cd app; flutter pub get; flutter run
```

Portal: **http://localhost:8000/portal/login** — `dr.rao@example.com` / `Str0ngPass!` or `dr.mehta@example.com` / `Str0ngPass!`
Patient App: `raj@gmail.com` / `12345678` or `ananya@gmail.com` / `12345678`

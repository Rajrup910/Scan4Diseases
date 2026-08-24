# 📖 Scan4Disease — User & Presentation Testing Guide

A step-by-step evaluation guide for the **Scan4Disease Mobile Application** (Flutter) and **Clinician Web Portal** (FastAPI/Jinja2), featuring 5 curated test photos across distinct dermatological criteria, structured AI chatbot prompts, and complete login credentials.

---

## 🔑 1. Demo Credentials & Access Directory

| Platform | Role | Name | Email | Password | Details & Capabilities |
|---|---|---|---|---|---|
| **Clinician Web Portal** (`/portal/login`) | **Doctor 1 (Primary)** | Dr. A. Rao | `dr.rao@example.com` | `Str0ngPass!` | Reg: `MH-12345`. Chief Dermatologist. Full patient roster & reviews. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 2 (Clinician)** | Dr. Sunita Mehta | `dr.mehta@example.com` | `Str0ngPass!` | Reg: `KA-67890`. Consultant Dermatologist & Dermatosurgeon. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 3 (Clinician)** | Dr. Vikram Kapoor | `dr.kapoor@example.com` | `Str0ngPass!` | Reg: `DL-98765`. Pediatric & Aesthetic Dermatology. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 4 (Clinician)** | Dr. Priya Nambiar | `dr.nambiar@example.com` | `Str0ngPass!` | Reg: `KL-45678`. Clinical Dermatopathology Specialist. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 5 (Clinician)** | Dr. Rajesh Deshmukh | `dr.deshmukh@example.com` | `Str0ngPass!` | Reg: `MH-54321`. Senior Cutaneous Oncology Consultant. |
| **Clinician Web Portal** (`/portal/login`) | **Doctor 6 (Clinician)** | Dr. Ananya Sen | `dr.sen@example.com` | `Str0ngPass!` | Reg: `WB-34567`. Melanoma & Pigmentary Lesion Specialist. |
| **Mobile App & API** (`/auth/login`) | **Patient 1 (Primary)** | Raj | `raj@gmail.com` | `12345678` | Preloaded screening history (Melanocytic nevus, BCC). |
| **Mobile App & API** (`/auth/login`) | **Patient 2 (Patient)** | Ananya Verma | `ananya@gmail.com` | `12345678` | Preloaded screening history (Actinic keratosis, Benign keratosis). |
| **Mobile App & API** (`/auth/login`) | **Demo Patients** | Priya Sharma / Sam Rivera / Jordan Lee | `priya@example.com` / `sam@example.com` / `jordan@example.com` | `12345678` | Clinical cases (Melanoma, SCC, Seborrheic keratosis) linked to doctors. |


---

## 📸 2. Five Curated Test Photos Across Lesion Criteria

All 5 photos are located in the [`demo_test_samples/`](file:///c:/Users/RAJ/Downloads/Capstone/demo_test_samples) directory. You can transfer these to your phone gallery or select them directly in the app:

```
demo_test_samples/
├── 01_melanoma_malignant.jpg          # Malignant Melanoma (High Risk)
├── 02_basal_cell_carcinoma.jpg        # Basal Cell Carcinoma (Malignant)
├── 03_actinic_keratosis_precancer.jpg  # Actinic Keratosis (Pre-malignant)
├── 04_benign_melanocytic_nevus.jpg    # Benign Melanocytic Nevus (Mole)
└── 05_skin_abrasion_wound.jpg         # Skin Abrasion / Wound (Safety Gate)
```

---

### 🔴 Photo 1: Malignant Melanoma (High Risk / Urgent)
* **File:** `demo_test_samples/01_melanoma_malignant.jpg`
* **Clinical Criteria (ABCDE Rule):**
  * **A (Asymmetry):** Marked asymmetry across axes.
  * **B (Border):** Irregular, scalloped, notched edges.
  * **C (Color):** Variegated dark brown, black, and reddish hues.
  * **D (Diameter):** > 6 mm.
  * **E (Evolving):** Rapidly changing lesion.
* **Suggested Questionnaire Input in App:**
  * Bleeding: **Yes**
  * Itching: **Yes**
  * Duration: **8 weeks** (Rapid evolution)
* **Expected Model Output:**
  * **Predicted Disease:** `Melanoma` (`mel`)
  * **Confidence:** `~75.6%`
  * **Triage Category:** `Urgent medical evaluation` (High Urgency — Red Tone)
  * **Safety Rules Triggered:** `R1_malignant_class`, `R3_malignant_mass_high`
  * **Grad-CAM:** Highlights peripheral asymmetry and deep pigmented core.
* **Structured Questions for AI Assistant (Chatbot):**
  1. *"What is the significance of the irregular borders in this lesion?"*
  2. *"Why does the app recommend urgent medical evaluation instead of waiting?"*
  3. *"What should I ask my dermatologist during the appointment?"*

---

### 🟠 Photo 2: Basal Cell Carcinoma (Malignant / Common Carcinoma)
* **File:** `demo_test_samples/02_basal_cell_carcinoma.jpg`
* **Clinical Criteria:**
  * Pearly, translucent papule/nodule with prominent telangiectasia (tiny blood vessels).
  * Rolled translucent border with central depression or ulceration.
* **Suggested Questionnaire Input in App:**
  * Bleeding: **Occasional bleeding**
  * Pain/Tenderness: **Mild**
  * Duration: **20 weeks** (Slow-growing)
* **Expected Model Output:**
  * **Predicted Disease:** `Basal cell carcinoma` (`bcc`)
  * **Confidence:** `~77.7%`
  * **Triage Category:** `Urgent medical evaluation` / `Prompt consultation`
  * **Safety Rules Triggered:** `R1_malignant_class`
  * **Grad-CAM:** Focuses on the nodular elevated zone and telangiectatic margins.
* **Structured Questions for AI Assistant (Chatbot):**
  1. *"Does basal cell carcinoma usually spread to other organs?"*
  2. *"What are standard treatment options for BCC (e.g. Mohs surgery, excision)?"*

---

### 🟡 Photo 3: Actinic Keratosis (Pre-malignant)
* **File:** `demo_test_samples/03_actinic_keratosis_precancer.jpg`
* **Clinical Criteria:**
  * Dry, rough, erythematous scaly patch on sun-damaged skin.
  * "Sandpaper-like" texture upon lateral palpation.
* **Suggested Questionnaire Input in App:**
  * Sun exposure: **High / Frequent outdoor exposure**
  * Rough/Scaly texture: **Yes**
  * Duration: **12 weeks**
* **Expected Model Output:**
  * **Predicted Disease:** `Actinic keratosis` (`akiec`)
  * **Confidence:** `~89.3%`
  * **Triage Category:** `Prompt dermatologist consultation` (Pre-malignant Flag)
  * **Safety Rules Triggered:** `R2_premalignant_class`, `R4b_premalignant_mass`
  * **Grad-CAM:** Activates on the keratotic scaly surface area.
* **Structured Questions for AI Assistant (Chatbot):**
  1. *"Can actinic keratosis turn into squamous cell carcinoma if left untreated?"*
  2. *"What preventive measures (sunscreen, cryotherapy) are recommended?"*

---

### 🟢 Photo 4: Melanocytic Nevus (Common Benign Mole)
* **File:** `demo_test_samples/04_benign_melanocytic_nevus.jpg`
* **Clinical Criteria:**
  * Symmetrical, uniform tan-to-dark brown pigmentation.
  * Sharp, smooth, circumscribed borders with stable long-term history.
* **Suggested Questionnaire Input in App:**
  * Bleeding: **No**
  * Itching: **No**
  * Duration: **> 1 year (Stable)**
* **Expected Model Output:**
  * **Predicted Disease:** `Mole` / `Melanocytic nevus` (`nv`)
  * **Confidence:** `~83.4%`
  * **Triage Category:** `Routine dermatologist consultation` (Low Urgency / Reassuring — Green Tone)
  * **Safety Rules Triggered:** `R9_default_routine`
  * **Grad-CAM:** Symmetrically centers over the homogeneous pigment network.
* **Structured Questions for AI Assistant (Chatbot):**
  1. *"What signs should I monitor for changes in this mole (ABCDE rules)?"*
  2. *"How often should routine self-skin examinations be performed?"*

---

### 🛡️ Photo 5: Skin Abrasion / Wound (Safety Gate & Front-Stage Router)
* **File:** `demo_test_samples/05_skin_abrasion_wound.jpg`
* **Clinical Criteria:**
  * Superficial epidermal erosion / mechanical scratch / non-neoplastic tissue injury.
  * Demonstrates the multi-stage safety defense: front-stage router rejects non-lesions before disease classification can produce a false positive.
* **Expected Model Output:**
  * **Pipeline Outcome:** `OTHER_DAMAGE` (Front-Stage Router Triggered)
  * **Confidence:** `~99.3% Non-Lesion`
  * **Triage:** General first-aid and wound cleanliness guidance.
  * **Safety Defense:** Prevents inaccurate skin cancer diagnosis on simple scratches or wounds.
* **Structured Questions for AI Assistant (Chatbot):**
  1. *"How should I clean and dress a minor skin abrasion?"*
  2. *"When does a wound require medical evaluation (e.g. infection signs)?"*

---

## 🚀 3. Step-by-Step Demonstration Flow

### Step A: Starting the Backend Server
1. Open PowerShell in the project root:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1
   ```
2. Wait for `Application startup complete.` (Backend runs on `http://localhost:8000`).

---

### Step B: Mobile App Login & Screening (Patient Side)
1. **Connect the phone:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1
   ```
2. **Launch the App:**
   ```powershell
   cd app
   flutter run
   ```
3. **Log in as a Patient:**
   * Email: `raj@gmail.com` (or `ananya@gmail.com`)
   * Password: `12345678`
4. **Run a Screening:**
   * Tap **Scan Skin / New Screening**.
   * Upload or capture one of the sample photos (e.g. `01_melanoma_malignant.jpg`).
   * Complete the quick symptom questionnaire.
   * View the structured AI result: Prediction, Class Probabilities, Grad-CAM Heatmap, Triage Guidance, and Multilingual Explanations (English / Hindi).
5. **Share with Clinician:**
   * On the result screen, tap the blue banner **"Share with a Doctor"**.
   * Select **Dr. A. Rao** or **Dr. Sunita Mehta** and tap **"Share this screening"**.

---

### Step C: Clinician Web Portal Review (Doctor Side)
1. Open your browser to: **`http://localhost:8000/portal/login`**
2. **Sign in as Clinician:**
   * Email: `dr.rao@example.com` (or `dr.mehta@example.com`)
   * Password: `Str0ngPass!`
3. **Inspect the Patient Roster:**
   * View the patient directory and incoming shared reports with triage badges (Urgent, Prompt, Routine).
4. **Open the Shared Report:**
   * View the original clinical photo and decrypted Grad-CAM heatmap side-by-side.
   * Review patient symptoms and confidence score breakdown.
5. **Clinical Workflow Action:**
   * Change status to **"Reviewed"** or **"Escalated"**.
   * Enter a doctor's clinical note (e.g., *"Excisional biopsy recommended within 7 days"*).
   * Submit to record the encrypted review trail and audit log.

---

## 💡 4. Pro-Tips & Troubleshooting

| Issue / Scenario | Solution / Command |
|---|---|
| **App shows "Connection refused"** | Re-run `powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1` to re-establish the reverse adb tunnel. |
| **Wi-Fi connection instead of USB** | In the app login screen, tap ⚙ **Server settings**, enter `http://<laptop-IP>:8000`. |
| **Reset Demo Database & Accounts** | Run `.\.venv\Scripts\python.exe scripts\seed_portal_demo.py`. |
| **Run Automated Login Verification** | Run `.\.venv\Scripts\python.exe backend\tests\verify_logins.py`. |
| **Run Pre-Demo Diagnostic Health Check** | Run `.\.venv\Scripts\python.exe scripts\demo_check.py`. |

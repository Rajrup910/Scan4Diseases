"""Generate a modern, styled, printable HTML/PDF document from DEMO_USER_GUIDE.md."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Scan4Disease — Presentation & Demo Testing Guide</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');

  :root {
    --primary: #0284c7;
    --primary-dark: #0369a1;
    --urgent: #ef4444;
    --prompt: #f59e0b;
    --routine: #10b981;
    --bg: #f8fafc;
    --card: #ffffff;
    --text: #0f172a;
    --text-muted: #475569;
    --border: #e2e8f0;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Inter', system-ui, -apple-system, sans-serif;
    background-color: var(--bg);
    color: var(--text);
    line-height: 1.6;
    padding: 40px 20px;
  }

  .container {
    max-width: 960px;
    margin: 0 auto;
    background: var(--card);
    padding: 48px;
    border-radius: 16px;
    box-shadow: 0 4px 20px -2px rgba(0, 0, 0, 0.05), 0 2px 6px -1px rgba(0, 0, 0, 0.03);
    border: 1px solid var(--border);
  }

  .header {
    border-bottom: 2px solid var(--border);
    padding-bottom: 24px;
    margin-bottom: 32px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .badge {
    background: #e0f2fe;
    color: #0369a1;
    padding: 6px 14px;
    border-radius: 9999px;
    font-size: 0.85rem;
    font-weight: 600;
  }

  h1 { font-size: 2.2rem; font-weight: 800; color: #0f172a; letter-spacing: -0.02em; }
  h2 { font-size: 1.45rem; font-weight: 700; color: #1e293b; margin-top: 36px; margin-bottom: 16px; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
  h3 { font-size: 1.15rem; font-weight: 600; color: #334155; margin-top: 20px; margin-bottom: 10px; }
  p { margin-bottom: 12px; color: var(--text-muted); }

  table {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0 24px 0;
    font-size: 0.95rem;
  }

  th, td {
    padding: 12px 14px;
    text-align: left;
    border: 1px solid var(--border);
  }

  th {
    background: #f1f5f9;
    font-weight: 600;
    color: #1e293b;
  }

  tr:nth-child(even) {
    background: #f8fafc;
  }

  .photo-card {
    background: #ffffff;
    border: 1px solid var(--border);
    border-left: 5px solid var(--primary);
    border-radius: 12px;
    padding: 20px;
    margin-bottom: 24px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.02);
  }

  .photo-card.urgent { border-left-color: var(--urgent); }
  .photo-card.prompt { border-left-color: var(--prompt); }
  .photo-card.routine { border-left-color: var(--routine); }
  .photo-card.gate { border-left-color: #6366f1; }

  .tag-urgent { background: #fee2e2; color: #b91c1c; padding: 3px 8px; border-radius: 4px; font-weight: 600; font-size: 0.8rem; }
  .tag-prompt { background: #fef3c7; color: #b45309; padding: 3px 8px; border-radius: 4px; font-weight: 600; font-size: 0.8rem; }
  .tag-routine { background: #d1fae5; color: #047857; padding: 3px 8px; border-radius: 4px; font-weight: 600; font-size: 0.8rem; }
  .tag-gate { background: #e0e7ff; color: #4338ca; padding: 3px 8px; border-radius: 4px; font-weight: 600; font-size: 0.8rem; }

  code {
    background: #f1f5f9;
    padding: 2px 6px;
    border-radius: 4px;
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 0.9em;
    color: #0f172a;
  }

  pre {
    background: #0f172a;
    color: #f8fafc;
    padding: 16px;
    border-radius: 8px;
    overflow-x: auto;
    font-family: 'Consolas', monospace;
    font-size: 0.88rem;
    margin: 12px 0 20px 0;
  }

  ul, ol {
    margin-left: 24px;
    margin-bottom: 16px;
    color: var(--text-muted);
  }

  li { margin-bottom: 6px; }

  .print-btn {
    background: #0284c7;
    color: white;
    padding: 10px 18px;
    border: none;
    border-radius: 8px;
    font-weight: 600;
    cursor: pointer;
    text-decoration: none;
    display: inline-block;
  }
  .print-btn:hover { background: #0369a1; }

  @media print {
    body { background: white; padding: 0; }
    .container { box-shadow: none; border: none; padding: 0; }
    .print-btn { display: none; }
  }
</style>
</head>
<body>

<div class="container">
  <div class="header">
    <div>
      <h1>Scan4Disease</h1>
      <p>Presentation & Testing Demo Guide (Mobile App & Clinician Web Portal)</p>
    </div>
    <div>
      <button class="print-btn" onclick="window.print()">🖨️ Print / Save as PDF</button>
    </div>
  </div>

  <h2>🔑 1. Demo Logins & Access Directory</h2>
  <table>
    <thead>
      <tr>
        <th>Platform</th>
        <th>Role</th>
        <th>User Name</th>
        <th>Email ID</th>
        <th>Password</th>
        <th>Capabilities & Notes</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Web Portal</strong><br><code>/portal/login</code></td>
        <td><strong>Doctor 1 (Primary)</strong></td>
        <td>Dr. A. Rao</td>
        <td><code>dr.rao@example.com</code></td>
        <td><code>Str0ngPass!</code></td>
        <td>Reg: MH-12345 · Chief Dermatologist. Full patient roster & reviews.</td>
      </tr>
      <tr>
        <td><strong>Web Portal</strong><br><code>/portal/login</code></td>
        <td><strong>Doctor 2 (Clinician)</strong></td>
        <td>Dr. Sunita Mehta</td>
        <td><code>dr.mehta@example.com</code></td>
        <td><code>Str0ngPass!</code></td>
        <td>Reg: KA-67890 · Consultant Dermatologist & Dermatosurgeon.</td>
      </tr>
      <tr>
        <td><strong>Web Portal</strong><br><code>/portal/login</code></td>
        <td><strong>Doctor 3 (Clinician)</strong></td>
        <td>Dr. Vikram Kapoor</td>
        <td><code>dr.kapoor@example.com</code></td>
        <td><code>Str0ngPass!</code></td>
        <td>Reg: DL-98765 · Pediatric & Aesthetic Dermatology.</td>
      </tr>
      <tr>
        <td><strong>Web Portal</strong><br><code>/portal/login</code></td>
        <td><strong>Doctor 4 (Clinician)</strong></td>
        <td>Dr. Priya Nambiar</td>
        <td><code>dr.nambiar@example.com</code></td>
        <td><code>Str0ngPass!</code></td>
        <td>Reg: KL-45678 · Clinical Dermatopathology Specialist.</td>
      </tr>
      <tr>
        <td><strong>Web Portal</strong><br><code>/portal/login</code></td>
        <td><strong>Doctor 5 (Clinician)</strong></td>
        <td>Dr. Rajesh Deshmukh</td>
        <td><code>dr.deshmukh@example.com</code></td>
        <td><code>Str0ngPass!</code></td>
        <td>Reg: MH-54321 · Senior Cutaneous Oncology Consultant.</td>
      </tr>
      <tr>
        <td><strong>Web Portal</strong><br><code>/portal/login</code></td>
        <td><strong>Doctor 6 (Clinician)</strong></td>
        <td>Dr. Ananya Sen</td>
        <td><code>dr.sen@example.com</code></td>
        <td><code>Str0ngPass!</code></td>
        <td>Reg: WB-34567 · Melanoma & Pigmentary Lesion Specialist.</td>
      </tr>
      <tr>
        <td><strong>Mobile App</strong><br><code>/auth/login</code></td>
        <td><strong>Patient 1 (Primary)</strong></td>
        <td>Raj</td>
        <td><code>raj@gmail.com</code></td>
        <td><code>12345678</code></td>
        <td>Preloaded history: Melanocytic nevus & Basal cell carcinoma.</td>
      </tr>

      <tr>
        <td><strong>Mobile App</strong><br><code>/auth/login</code></td>
        <td><strong>Patient 2 (Patient)</strong></td>
        <td>Ananya Verma</td>
        <td><code>ananya@gmail.com</code></td>
        <td><code>12345678</code></td>
        <td>Preloaded history: Actinic keratosis & Benign keratosis.</td>
      </tr>
      <tr>
        <td><strong>Mobile App</strong><br><code>/auth/login</code></td>
        <td><strong>Demo Patients</strong></td>
        <td>Priya / Sam / Jordan</td>
        <td><code>priya@example.com</code><br><code>sam@example.com</code></td>
        <td><code>12345678</code></td>
        <td>Clinical demo cases linked to doctors in worklists.</td>
      </tr>
    </tbody>
  </table>

  <h2>📸 2. Five Curated Test Photos Across Lesion Criteria</h2>
  <p>All photos are located in the local workspace directory: <code>demo_test_samples/</code></p>

  <div class="photo-card urgent">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h3>🔴 Photo 1: Malignant Melanoma (High Risk)</h3>
      <span class="tag-urgent">URGENT MEDICAL EVALUATION</span>
    </div>
    <p><strong>File Location:</strong> <code>demo_test_samples/01_melanoma_malignant.jpg</code></p>
    <p><strong>Diagnostic Criteria (ABCDE):</strong> Asymmetric borders, dark pigmented irregular margins, variegation, diameter >6mm, fast evolution.</p>
    <p><strong>Symptom Inputs:</strong> Bleeding = <em>Yes</em>, Itching = <em>Yes</em>, Duration = <em>8 weeks</em>.</p>
    <p><strong>Expected Model Output:</strong> Predicted: <code>Melanoma (mel)</code> · Confidence: <code>75.6%</code> · Triage: <code>Urgent medical evaluation</code> · Grad-CAM: Saliency centered on core pigment.</p>
    <p><strong>Structured AI Assistant Questions:</strong></p>
    <ul>
      <li><em>"What is the clinical significance of irregular borders in this lesion?"</em></li>
      <li><em>"Why does the app recommend urgent medical evaluation?"</em></li>
    </ul>
  </div>

  <div class="photo-card prompt">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h3>🟠 Photo 2: Basal Cell Carcinoma (Malignant)</h3>
      <span class="tag-prompt">PROMPT CONSULTATION</span>
    </div>
    <p><strong>File Location:</strong> <code>demo_test_samples/02_basal_cell_carcinoma.jpg</code></p>
    <p><strong>Diagnostic Criteria:</strong> Pearly nodule, translucent border, visible telangiectasia (tiny vessels), central indentation.</p>
    <p><strong>Symptom Inputs:</strong> Bleeding = <em>Occasional</em>, Pain = <em>Mild</em>, Duration = <em>20 weeks</em>.</p>
    <p><strong>Expected Model Output:</strong> Predicted: <code>Basal cell carcinoma (bcc)</code> · Confidence: <code>77.7%</code> · Triage: <code>Urgent / Prompt medical evaluation</code>.</p>
    <p><strong>Structured AI Assistant Questions:</strong></p>
    <ul>
      <li><em>"What are standard treatment options for BCC (e.g. Mohs surgery)?"</em></li>
      <li><em>"Does basal cell carcinoma usually metastasize?"</em></li>
    </ul>
  </div>

  <div class="photo-card prompt">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h3>🟡 Photo 3: Actinic Keratosis (Pre-malignant)</h3>
      <span class="tag-prompt">PROMPT CONSULTATION</span>
    </div>
    <p><strong>File Location:</strong> <code>demo_test_samples/03_actinic_keratosis_precancer.jpg</code></p>
    <p><strong>Diagnostic Criteria:</strong> Erythematous, rough, sandpaper-like scaly patch on chronic sun-exposed skin area.</p>
    <p><strong>Symptom Inputs:</strong> Sun exposure = <em>High</em>, Rough surface = <em>Yes</em>, Duration = <em>12 weeks</em>.</p>
    <p><strong>Expected Model Output:</strong> Predicted: <code>Actinic keratosis (akiec)</code> · Confidence: <code>89.3%</code> · Triage: <code>Prompt dermatologist consultation</code>.</p>
    <p><strong>Structured AI Assistant Questions:</strong></p>
    <ul>
      <li><em>"Can actinic keratosis progress into invasive squamous cell carcinoma?"</em></li>
      <li><em>"What preventive care and sun protection steps should be taken?"</em></li>
    </ul>
  </div>

  <div class="photo-card routine">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h3>🟢 Photo 4: Melanocytic Nevus (Benign Mole)</h3>
      <span class="tag-routine">ROUTINE CONSULTATION</span>
    </div>
    <p><strong>File Location:</strong> <code>demo_test_samples/04_benign_melanocytic_nevus.jpg</code></p>
    <p><strong>Diagnostic Criteria:</strong> Symmetrical round shape, uniform pigment network, distinct smooth borders, stable long-term history.</p>
    <p><strong>Symptom Inputs:</strong> Bleeding = <em>No</em>, Itching = <em>No</em>, Duration = <em>> 1 year (Stable)</em>.</p>
    <p><strong>Expected Model Output:</strong> Predicted: <code>Mole (nv)</code> · Confidence: <code>83.4%</code> · Triage: <code>Routine dermatologist consultation</code>.</p>
    <p><strong>Structured AI Assistant Questions:</strong></p>
    <ul>
      <li><em>"What signs indicate that a normal mole might be turning malignant?"</em></li>
      <li><em>"How frequently should routine skin checks be performed?"</em></li>
    </ul>
  </div>

  <div class="photo-card gate">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h3>🛡️ Photo 5: Skin Abrasion / Wound (Safety Gate & Router)</h3>
      <span class="tag-gate">NON-LESION SAFETY GATE TRIGGERED</span>
    </div>
    <p><strong>File Location:</strong> <code>demo_test_samples/05_skin_abrasion_wound.jpg</code></p>
    <p><strong>Diagnostic Criteria:</strong> Superficial mechanical scratch / wound / non-lesion damage. Multi-stage safety router halts classification before disease mapping.</p>
    <p><strong>Expected Model Output:</strong> Pipeline Outcome: <code>OTHER_DAMAGE</code> · Router Confidence: <code>99.3% Non-Lesion</code> · Triage: First-aid and hygiene guidance.</p>
    <p><strong>Structured AI Assistant Questions:</strong></p>
    <ul>
      <li><em>"What are the best first-aid practices for a minor skin scratch or abrasion?"</em></li>
      <li><em>"How can I tell if a skin wound has become infected?"</em></li>
    </ul>
  </div>

  <h2>🚀 3. Step-by-Step Walkthrough Flow</h2>
  <ol>
    <li><strong>Start Backend:</strong> Run <code>powershell -ExecutionPolicy Bypass -File scripts\\run_backend.ps1</code></li>
    <li><strong>Connect Phone:</strong> Run <code>powershell -ExecutionPolicy Bypass -File scripts\\connect_phone.ps1</code></li>
    <li><strong>Patient Screening (App):</strong> Sign in as <code>raj@gmail.com</code> / <code>12345678</code> &rarr; Scan photo &rarr; View AI report &rarr; Tap <em>"Share with a Doctor"</em> &rarr; Select <em>Dr. A. Rao</em>.</li>
    <li><strong>Doctor Review (Web Portal):</strong> Open <code>http://localhost:8000/portal/login</code> &rarr; Sign in as <code>dr.rao@example.com</code> / <code>Str0ngPass!</code> &rarr; Open Patient Worklist &rarr; Inspect photo, Grad-CAM, & answers &rarr; Enter doctor note and update review status.</li>
  </ol>


  <h2>💡 4. Pro-Tips & Diagnostic Commands</h2>
  <table>
    <thead><tr><th>Diagnostic Action</th><th>Command</th></tr></thead>
    <tbody>
      <tr><td>Re-connect Phone Tunnel</td><td><code>powershell -ExecutionPolicy Bypass -File scripts\\connect_phone.ps1</code></td></tr>
      <tr><td>Verify All Logins</td><td><code>.\\.venv\\Scripts\\python.exe backend\\tests\\verify_logins.py</code></td></tr>
      <tr><td>Pre-Demo Smoke Test</td><td><code>.\\.venv\\Scripts\\python.exe scripts\\demo_check.py</code></td></tr>
      <tr><td>Re-seed Demo Database</td><td><code>.\\.venv\\Scripts\\python.exe scripts\\seed_portal_demo.py</code></td></tr>
    </tbody>
  </table>

</div>

</body>
</html>
"""


def main() -> int:
    output_html = REPO_ROOT / "demo_guide_printable.html"
    output_html.write_text(HTML_TEMPLATE, encoding="utf-8")
    print(f"Generated printable guide HTML: {output_html}")
    print("You can open this file in any browser and press Ctrl+P (or click Print) to save as PDF!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

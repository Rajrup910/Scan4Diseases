"""FastAPI backend for Scan4Disease.

The backend orchestrates, it does not decide. Responsibilities are split deliberately:

    CNN            visual classification         -> class + confidence + Grad-CAM
    triage rules   medical urgency               -> deterministic Python, auditable
    LLM            explanation and translation    -> never sets urgency

Nothing here imports from `ml.training`. Training code stays out of the API server.
"""

__version__ = "0.1.0"

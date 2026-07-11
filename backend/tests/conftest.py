import os
import sys
from pathlib import Path

# Ensure the backend package is importable regardless of the current working
# directory when pytest runs in CI or locally.
BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

# The app builds its Settings at import time and expects DB_* to be present.
# These dummy values let the app import without a real database (no connection
# is opened until a request actually hits the DB).
os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_PORT", "3306")
os.environ.setdefault("DB_DATABASE", "testdb")
os.environ.setdefault("DB_USERNAME", "test")
os.environ.setdefault("DB_PASSWORD", "test")

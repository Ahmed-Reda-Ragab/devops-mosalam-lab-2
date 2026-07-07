import os

# The app builds its Settings at import time and expects DB_* to be present.
# These dummy values let the app import without a real database (no connection
# is opened until a request actually hits the DB).
os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_PORT", "3306")
os.environ.setdefault("DB_DATABASE", "testdb")
os.environ.setdefault("DB_USERNAME", "test")
os.environ.setdefault("DB_PASSWORD", "test")

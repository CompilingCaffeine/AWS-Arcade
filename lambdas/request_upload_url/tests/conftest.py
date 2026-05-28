import os
import pathlib
import sys

PKG_DIR = pathlib.Path(__file__).resolve().parents[1]

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("UPLOAD_BUCKET", "test-uploads")
os.environ.setdefault("PRESIGNED_URL_TTL_SECS", "900")
os.environ.setdefault("MAX_UPLOAD_BYTES", str(50 * 1024 * 1024))

sys.path.insert(0, str(PKG_DIR))

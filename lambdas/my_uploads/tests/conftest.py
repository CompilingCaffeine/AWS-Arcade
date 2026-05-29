import os
import pathlib
import sys

PKG_DIR = pathlib.Path(__file__).resolve().parents[1]

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("CATALOG_TABLE", "test-catalog")

sys.path.insert(0, str(PKG_DIR))

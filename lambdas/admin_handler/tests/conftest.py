import os
import pathlib
import sys

PKG_DIR = pathlib.Path(__file__).resolve().parents[1]

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("SITE_BUCKET", "test-site")
os.environ.setdefault("CATALOG_TABLE", "test-catalog")
os.environ.setdefault("CLOUDFRONT_DISTRIBUTION_ID", "EXAMPLEDIST")
os.environ.setdefault("SENDER_EMAIL", "")
os.environ.setdefault("ADMIN_EMAIL", "")
os.environ.setdefault("PORTFOLIO_HOSTNAME", "")

sys.path.insert(0, str(PKG_DIR))

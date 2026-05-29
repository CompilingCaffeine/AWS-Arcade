import os
import pathlib
import sys

PKG_DIR = pathlib.Path(__file__).resolve().parents[1]
REPO_ROOT = PKG_DIR.parents[1]

os.environ.setdefault("AWS_DEFAULT_REGION", "us-west-2")
os.environ.setdefault("SITE_BUCKET", "test-site-bucket")
os.environ.setdefault("SUBMISSIONS_TABLE", "test-submissions-table")
os.environ.setdefault("CLOUDFRONT_DISTRIBUTION_ID", "EXAMPLEDIST")
os.environ.setdefault(
    "MANIFEST_SCHEMA_PATH",
    str(REPO_ROOT / "schemas" / "manifest.schema.json"),
)

sys.path.insert(0, str(PKG_DIR))

#!/usr/bin/env python3
"""Simple smoke test for upload.py"""

import sys
from pathlib import Path
import pytest
from moto import mock_aws
import boto3

# Import main to test
from upload import main


@pytest.fixture
def temp_workspace(tmp_path):
    """Create temporary workspace with artifact directory and config file."""
    # Create artifact directory
    artifact_dir = tmp_path / "build"
    artifact_dir.mkdir()

    # Create test files in artifact directory
    (artifact_dir / "index.html").write_text("<html>Hello</html>")

    assets_dir = artifact_dir / "assets"
    assets_dir.mkdir()
    (assets_dir / "app.js").write_text("console.log('test');")
    (assets_dir / "style.css").write_text("body { color: red; }")

    (artifact_dir / "favicon.ico").write_bytes(b"\x00\x00\x01\x00")

    # Create config file outside artifact directory
    config_file = tmp_path / ".cache-config.yml"
    config_file.write_text("""
default-cache-control: "max-age=3600"
file-overrides:
  - file: index.html
    cache-control: "no-cache"
    """)

    return {"artifact_dir": artifact_dir, "config_file": config_file}


@mock_aws
def test_upload_workflow(temp_workspace):
    """End-to-end smoke test: create files, run main(), verify results."""
    artifact_dir = temp_workspace["artifact_dir"]
    config_file = temp_workspace["config_file"]

    # Setup mocked S3
    s3_client = boto3.client("s3", region_name="us-east-1")
    s3_client.create_bucket(Bucket="test-bucket")
    print("✓ Created test files and mocked S3 bucket")

    # Run main() with test arguments
    sys.argv = [
        "upload.py",
        str(artifact_dir),
        "test-bucket",
        "static/abc123",
        str(config_file),
    ]

    result = main()
    assert result == 0, "main() should return 0 on success"
    print("✓ main() executed successfully")

    # Verify uploads in S3
    response = s3_client.list_objects_v2(Bucket="test-bucket")
    uploaded_keys = [obj["Key"] for obj in response.get("Contents", [])]

    print(f"\nUploaded {len(uploaded_keys)} files to S3:")
    for key in sorted(uploaded_keys):
        print(f"  - {key}")

    # Verify all expected files are present
    assert len(uploaded_keys) == 5
    assert "static/abc123/index.html" in uploaded_keys
    assert "static/abc123/assets/app.js" in uploaded_keys
    assert "static/abc123/assets/style.css" in uploaded_keys
    assert "static/abc123/favicon.ico" in uploaded_keys  # Versioned
    assert "favicon.ico" in uploaded_keys  # At root
    print("✓ All files present in S3")

    # Verify cache-control headers
    index_obj = s3_client.head_object(
        Bucket="test-bucket", Key="static/abc123/index.html"
    )
    assert index_obj["CacheControl"] == "no-cache"
    print("✓ index.html has no-cache header")

    js_obj = s3_client.head_object(
        Bucket="test-bucket", Key="static/abc123/assets/app.js"
    )
    assert js_obj["CacheControl"] == "max-age=3600"
    print("✓ app.js has default cache-control header")

    print("\n✅ All smoke tests passed!")

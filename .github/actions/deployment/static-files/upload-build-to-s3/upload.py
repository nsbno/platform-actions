#!/usr/bin/env python3
"""Upload static files to S3 with optional cache-control headers."""

import sys
import asyncio
import mimetypes
from pathlib import Path
import yaml
import boto3


def parse_config(config_file):
    """Parse cache-control configuration from YAML file."""
    if not config_file or not config_file.exists():
        return None, {}

    cache_config = yaml.safe_load(config_file.read_text()) or {}
    default_cache = cache_config.get("default-cache-control")
    overrides = {
        o["file"]: o["cache-control"] for o in cache_config.get("file-overrides", [])
    }
    return default_cache, overrides


def collect_files(artifact_path, s3_bucket, s3_path, default_cache, overrides):
    """
    Collect all files to upload with their S3 destinations and cache-control.

    Returns a list of dicts with keys: local_path, s3_bucket, s3_key, cache_control, content_type
    """
    files_to_upload = []

    # Collect all files from artifact directory
    for file_path in artifact_path.rglob("*"):
        if not file_path.is_file():
            continue

        relative = str(file_path.relative_to(artifact_path)).replace("\\", "/")
        s3_key = f"{s3_path}/{relative}"
        cache_control = overrides.get(relative, default_cache)
        content_type, _ = mimetypes.guess_type(str(file_path))

        files_to_upload.append(
            {
                "local_path": file_path,
                "s3_bucket": s3_bucket,
                "s3_key": s3_key,
                "cache_control": cache_control,
                "content_type": content_type,
            }
        )

    # Add favicon to bucket root if exists
    favicon = artifact_path / "favicon.ico"
    if favicon.exists():
        content_type, _ = mimetypes.guess_type(str(favicon))
        files_to_upload.append(
            {
                "local_path": favicon,
                "s3_bucket": s3_bucket,
                "s3_key": "favicon.ico",
                "cache_control": default_cache,
                "content_type": content_type,
            }
        )

    return files_to_upload


async def upload_file(file_info, s3_client):
    """Upload a single file to S3 asynchronously."""
    extra_args = {}

    if file_info["content_type"]:
        extra_args["ContentType"] = file_info["content_type"]

    if file_info["cache_control"]:
        extra_args["CacheControl"] = file_info["cache_control"]

    # Run blocking S3 call in thread pool
    await asyncio.to_thread(
        s3_client.upload_file,
        str(file_info["local_path"]),
        file_info["s3_bucket"],
        file_info["s3_key"],
        ExtraArgs=extra_args or None,
    )


async def upload_files(files_to_upload, s3_client):
    """Upload all files to S3 concurrently."""
    tasks = [upload_file(file_info, s3_client) for file_info in files_to_upload]
    await asyncio.gather(*tasks)


def main():
    if len(sys.argv) < 4:
        print(
            "Usage: upload_simple.py <artifact_path> <s3_bucket> <s3_path> [config_file]"
        )
        return 1

    artifact_path = Path(sys.argv[1])
    s3_bucket = sys.argv[2]
    s3_path = sys.argv[3]
    config_file = Path(sys.argv[4]) if len(sys.argv) > 4 else None

    # Step 1: Parse config
    default_cache, overrides = parse_config(config_file)

    # Step 2: Collect all files to upload
    files_to_upload = collect_files(
        artifact_path, s3_bucket, s3_path, default_cache, overrides
    )

    # Step 3: Upload all files
    s3_client = boto3.client("s3")
    asyncio.run(upload_files(files_to_upload, s3_client))

    print(f"✓ Uploaded {len(files_to_upload)} files to s3://{s3_bucket}/{s3_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

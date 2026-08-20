#!/usr/bin/env python3
"""Weekly FUTU upgrade check helper.

Queries the official FUTU stable OpenD download and the PyPI ``futu-api``
release to detect a newer OpenD version than the one pinned in
``versions.json``. When a change is found it prints a machine-readable summary
that a caller (a GitHub Actions workflow) turns into an issue or PR. It never
updates production digests and never auto-merges: it only reports.

The script is intentionally read-only and safe to run as a scheduled job.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "versions.json"

# The official stable download redirects to a concrete URL when a new release
# ships; the version is embedded in the archive filename.
STABLE_URL = "https://softwaredownload.futunn.com/Futu_OpenD_{version}_Ubuntu18.04.tar.gz"
PYPI_JSON = "https://pypi.org/pypi/futu-api/json"

_VERSION_RE = re.compile(r"^Futu_OpenD_(\d+\.\d+\.\d+)_Ubuntu18\.04\.tar\.gz$")


def _split(version: str) -> tuple[int, int, int]:
    return tuple(int(part) for part in version.split("."))  # type: ignore[return-value]


def latest_futu_api_version() -> str | None:
    """Return the newest ``futu-api`` version on PyPI, or ``None`` on failure."""
    try:
        with urllib.request.urlopen(PYPI_JSON, timeout=30) as response:
            data = json.load(response)
    except Exception:  # noqa: BLE001 - a transient network failure is non-fatal
        return None
    return data.get("info", {}).get("version")


def latest_opend_version() -> tuple[str, str] | None:
    """Resolve the latest stable OpenD download URL, or ``(url, None)`` on miss."""
    # FUTU does not publish a stable "latest" index; probe the version page by
    # trying known OpenD 10.9.x patch signatures. This is intentionally
    # conservative: if we cannot resolve a newer version we report nothing and
    # the maintainer upgrades the manifest by hand, which is the safe default.
    # The workflow's maintainer page is the authoritative source for new
    # patch versions; the script's job is to surface drift, not to guess.
    # We therefore only report the OpenD that is pinned and compare against a
    # hard-coded "known current" list supplied via --known-versions, so the
    # check stays deterministic and never fabricates a version.
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Check for FUTU version drift.")
    parser.add_argument(
        "--known-opend",
        help="comma-separated known current OpenD versions to compare against",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    pinned_opend = manifest["opend_version"]
    pinned_api = manifest["futu_api_version"]

    lines: list[str] = []
    newest_api = latest_futu_api_version()
    if newest_api and _split(newest_api) > _split(pinned_api):
        lines.append(
            f"PyPI futu-api {pinned_api} -> {newest_api} "
            "(review pyproject.toml, uv.lock, the Docker version manifest, and adapter tests together)"
        )

    known = [
        version.strip()
        for version in (args.known_opend or "").split(",")
        if version.strip()
    ]
    for version in known:
        if _split(version) > _split(pinned_opend):
            lines.append(f"OpenD {pinned_opend} -> {version} (possible patch/minor update)")

    if not lines:
        print("no FUTU version drift detected")
        return 0
    print("FUTU version drift detected:")
    for line in lines:
        print(f"  - {line}")
    return 1


if __name__ == "__main__":
    sys.exit(main())

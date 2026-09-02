#!/usr/bin/env python3
"""Calculate the deterministic build identity for a BCU source checkout."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def git(repo: Path, *arguments: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout


def calculate(repo: Path) -> dict[str, object]:
    repo = repo.resolve()
    commit = git(repo, "rev-parse", "--short=12", "HEAD").decode().strip()
    dirty = bool(git(repo, "status", "--porcelain", "--untracked-files=all"))
    raw_paths = git(
        repo,
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        "Sources",
    )
    paths = sorted(path for path in raw_paths.split(b"\0") if path)
    if not paths:
        raise RuntimeError(f"No Sources/ files found in {repo}")

    digest = hashlib.sha256()
    for raw_path in paths:
        relative_path = raw_path.decode("utf-8", errors="surrogateescape")
        digest.update(raw_path)
        digest.update(b"\0")
        digest.update((repo / relative_path).read_bytes())
        digest.update(b"\0")

    sources_sha256 = digest.hexdigest()
    cleanliness = "dirty" if dirty else "clean"
    return {
        "identity": f"{commit}-{cleanliness}:{sources_sha256}",
        "commit": commit,
        "dirty": dirty,
        "sourcesSHA256": sources_sha256,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--format", choices=("json", "tsv"), required=True)
    args = parser.parse_args()

    result = calculate(args.repo)
    if args.format == "json":
        print(json.dumps(result, separators=(",", ":")))
    else:
        print(
            result["identity"],
            result["commit"],
            str(result["dirty"]).lower(),
            result["sourcesSHA256"],
            sep="\t",
        )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render build/config-coverage/ from build/config/ for a local coverage run.

In every container that runs kms-server it:
  - swaps the core-service image for the -coverage one (images/build-coverage.sh)
  - sets LLVM_PROFILE_FILE, in continuous mode (%c), so the counters reach the file
    while the server runs
  - mounts /var/lib/kms-coverage/<statefulset> from the host at /coverage, where
    run-local.sh collects the profiles
Everything else is copied unchanged. Antithesis runs never use this config.

  antithesis/local/coverage-config.py
"""
import os
import shutil
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "build", "config", "manifests")
OUT = os.path.join(HERE, "..", "build", "config-coverage", "manifests")
HOST_DIR = "/var/lib/kms-coverage"


def patch(doc):
    """Patch one manifest document in place; return the names of the patched containers."""
    if not doc or doc.get("kind") not in ("StatefulSet", "Deployment"):
        return []
    pod = doc["spec"]["template"]["spec"]
    patched = []
    for c in pod.get("containers", []):
        if "kms-server" not in " ".join(c.get("command", []) + c.get("args", [])):
            continue
        c["image"] += "-coverage"
        c.setdefault("env", []).append({"name": "LLVM_PROFILE_FILE", "value": "/coverage/%p-%c.profraw"})
        c.setdefault("volumeMounts", []).append({"name": "coverage", "mountPath": "/coverage"})
        patched.append(c["name"])
    if patched:
        host = f"{HOST_DIR}/{doc['metadata']['name']}"
        pod.setdefault("volumes", []).append({"name": "coverage", "hostPath": {"path": host, "type": "Directory"}})
    return patched


def main():
    if not os.path.isdir(SRC):
        sys.exit(f"{SRC} not found; run make config first")
    shutil.rmtree(os.path.dirname(OUT), ignore_errors=True)
    os.makedirs(OUT)
    statefulsets = []
    for name in sorted(os.listdir(SRC)):
        with open(os.path.join(SRC, name)) as f:
            # A trailing --- loads as an empty document, which kapp rejects when dumped as null.
            docs = [d for d in yaml.safe_load_all(f) if d is not None]
        for doc in docs:
            if patch(doc):
                statefulsets.append(doc["metadata"]["name"])
        with open(os.path.join(OUT, name), "w") as f:
            yaml.safe_dump_all(docs, f, sort_keys=False)
    if not statefulsets:
        sys.exit("no container runs kms-server; nothing patched")
    print(" ".join(statefulsets))


if __name__ == "__main__":
    main()

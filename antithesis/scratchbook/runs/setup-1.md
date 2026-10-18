# setup-1 · 0f9fd70d · current@3095d82a · incomplete · 15 m

Report: none (the run ended `incomplete` during setup, before any test ran).

- **What happened:** Antithesis could not pull `us-central1-docker.pkg.dev/molten-verve-216720/zama-repository/kms/core-client:speedrun-3095d82a`: "manifest unknown" (error 4001, "The provided image definition could not resolve to a reachable image"). Build log: [buildlogs-0f9fd70d.txt](../logs/buildlogs-0f9fd70d.txt), lines 317–321.
- **Why:** our launch step. For this Kubernetes config, snouty pushed only the config image ([launch output](../logs/launch-setup-1.out)); the harness pushes the KMS images with a separate step (`make push`, [push.sh](../../images/push.sh)), which speedrun hadn't run.
- **Classification:** harness mistake (false positive of the setup, not a platform failure). Fix: push the images before every launch with a new image tag.

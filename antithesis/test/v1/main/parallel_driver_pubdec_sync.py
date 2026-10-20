#!/usr/bin/env python3
"""Public decryptions through the sync endpoint: kms-core-client --sync sends
PublicDecryptSync, which starts the decryption and waits up to 60 s for its result, and
re-sends the same request on Unavailable. The calls and their checks are
helper_decrypt.public_decrypts."""
from helper_decrypt import public_decrypts

public_decrypts("pubdec.sync", sync=True)

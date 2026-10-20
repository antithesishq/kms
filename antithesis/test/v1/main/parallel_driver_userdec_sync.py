#!/usr/bin/env python3
"""User decryptions through the sync endpoint: kms-core-client --sync sends UserDecryptSync,
which starts the decryption and waits up to 60 s for its result, and re-sends the same
request on Unavailable. The calls and their checks are helper_decrypt.user_decrypts."""
from helper_decrypt import user_decrypts

user_decrypts("userdec.sync", sync=True)

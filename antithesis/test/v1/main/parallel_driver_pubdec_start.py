#!/usr/bin/env python3
"""Public decryptions through the async endpoint: PublicDecrypt, then kms-core-client polls
GetPublicDecryptionResult. The calls and their checks are helper_decrypt.public_decrypts."""
from helper_decrypt import public_decrypts

public_decrypts("pubdec.start", sync=False)

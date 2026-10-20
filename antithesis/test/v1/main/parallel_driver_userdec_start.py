#!/usr/bin/env python3
"""User decryptions through the async endpoint: UserDecrypt, then kms-core-client polls
GetUserDecryptionResult. The calls and their checks are helper_decrypt.user_decrypts."""
from helper_decrypt import user_decrypts

user_decrypts("userdec.start", sync=False)

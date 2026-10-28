"""Validate apksigner output without relying on one build-tools version's labels."""

import re
import sys

EXPECTED_CERTIFICATE = "dda68ac39ed55cfc079eaaae33e37eb0a39eeea6a9652071a338cc87b4407e5b"
CERTIFICATE_LINE = re.compile(
    r"^(?:Signer #1|V[0-9]+(?:\.[0-9]+)? Signer(?: #1)?:) "
    r"certificate SHA-256 digest: ([0-9a-fA-F]{64})$"
)


def valid_signature(output: str) -> bool:
    lines = output.splitlines()
    if [line for line in lines if line.startswith("Number of signers:")] != [
        "Number of signers: 1"
    ]:
        return False
    certificates = [line for line in lines if "certificate SHA-256 digest:" in line]
    if not certificates:
        return False
    matches = [CERTIFICATE_LINE.fullmatch(line) for line in certificates]
    return all(match is not None and match.group(1).lower() == EXPECTED_CERTIFICATE for match in matches)


if __name__ == "__main__":
    if not valid_signature(sys.stdin.read()):
        sys.exit("Android APK signing identity does not match the existing releases.")
    print("Android APK signing identity matches the existing releases.")

import unittest

from scripts.verify_android_signature import EXPECTED_CERTIFICATE, valid_signature


class AndroidSigningOutputTest(unittest.TestCase):
    def test_accepts_build_tools_36_output(self):
        self.assertTrue(valid_signature(
            "Number of signers: 1\n"
            f"Signer #1 certificate SHA-256 digest: {EXPECTED_CERTIFICATE}\n"
        ))

    def test_accepts_build_tools_37_output_and_multiple_matching_schemes(self):
        self.assertTrue(valid_signature(
            "Number of signers: 1\n"
            f"V2 Signer: certificate SHA-256 digest: {EXPECTED_CERTIFICATE}\n"
            f"V3 Signer: certificate SHA-256 digest: {EXPECTED_CERTIFICATE}\n"
        ))

    def test_rejects_different_certificate_or_extra_signer(self):
        wrong = "0" * 64
        self.assertFalse(valid_signature(
            "Number of signers: 1\n"
            f"V2 Signer: certificate SHA-256 digest: {wrong}\n"
        ))
        self.assertFalse(valid_signature(
            "Number of signers: 2\n"
            f"Signer #1 certificate SHA-256 digest: {EXPECTED_CERTIFICATE}\n"
        ))

    def test_rejects_missing_or_unknown_signer_format(self):
        self.assertFalse(valid_signature("Number of signers: 1\n"))
        self.assertFalse(valid_signature(
            "Number of signers: 1\n"
            f"Signer #2 certificate SHA-256 digest: {EXPECTED_CERTIFICATE}\n"
        ))
        self.assertFalse(valid_signature(
            "Number of signers: 1\nNumber of signers: 1\n"
            f"Signer #1 certificate SHA-256 digest: {EXPECTED_CERTIFICATE}\n"
        ))


if __name__ == "__main__":
    unittest.main()

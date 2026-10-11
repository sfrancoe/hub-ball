import unittest
from datetime import datetime, timezone, timedelta
from publish_beta_release import verified_target, GROUPS

class BetaPublisherTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 10, tzinfo=timezone.utc)
        self.receipt = {'version': '1.1', 'build': 123, 'status': 'available_to_scott_only', 'uploadStatus': 'upload_command_succeeded'}
        self.info = {'CFBundleIdentifier': 'com.sfrancoe.HubBall', 'CFBundleVersion': '123', 'CFBundleShortVersionString': '1.1', 'UIDeviceFamily': [1, 2], 'MinimumOSVersion': '17.0'}
        self.expiry = None
        self.external = 'IN_BETA_TESTING'; self.group_ids = GROUPS; self.private = False; self.expired = False
    def fetch(self, path):
        if '/apps/' in path:
            return {'data': [{'id': gid} for gid in self.group_ids]}
        if '/betaGroups/' in path:
            return {'data': [] if self.private and '58b84' in path else [{'id': 'build123'}]}
        return {'data': [{'id': 'build123', 'attributes': {'processingState': 'VALID', 'expired': self.expired, 'minOsVersion': '17.0', 'expirationDate': self.expiry or (self.now + timedelta(days=30)).isoformat()}}], 'included': [
            {'type': 'preReleaseVersions', 'attributes': {'version': '1.1'}},
            {'type': 'buildBetaDetails', 'attributes': {'internalBuildState': 'IN_BETA_TESTING', 'externalBuildState': self.external}}]}
    def target(self):
        return verified_target(123, self.receipt, self.info, self.fetch, self.now)
    def test_requires_actual_availability_in_every_group(self):
        self.assertEqual(self.target()['verifiedGroupIDs'], sorted(GROUPS))
        self.private = True
        with self.assertRaises(ValueError): self.target()
        self.private = False; self.external = 'READY_FOR_BETA_SUBMISSION'
        with self.assertRaises(ValueError): self.target()
    def test_unknown_group_expired_or_unsupported_build_fails(self):
        self.group_ids = GROUPS | {'another-group'}
        with self.assertRaises(ValueError): self.target()
        self.group_ids = GROUPS; self.expired = True
        with self.assertRaises(ValueError): self.target()
        self.expired = False; self.info['UIDeviceFamily'] = [1]
        with self.assertRaises(ValueError): self.target()
    def test_apple_offset_expiry_preserves_exact_instant_in_utc(self):
        self.now = datetime(2026, 10, 11, 18, tzinfo=timezone.utc)
        self.expiry = '2027-01-09T09:01:01-08:00'
        target = self.target()
        self.assertEqual(target['expiresAt'], '2027-01-09T17:01:01Z')
        self.assertEqual(datetime.fromisoformat(target['expiresAt'].replace('Z', '+00:00')), datetime.fromisoformat(self.expiry))
    def test_offset_confirmation_and_expiry_are_both_normalized(self):
        self.now = datetime(2026, 10, 10, 10, 30, tzinfo=timezone(timedelta(hours=5, minutes=30)))
        target = self.target()
        self.assertEqual(target['confirmedAt'], '2026-10-10T05:00:00Z')
        self.assertEqual(target['expiresAt'], '2026-11-09T05:00:00Z')
    def test_utc_timestamps_remain_unchanged(self):
        target = self.target()
        self.assertEqual(target['confirmedAt'], '2026-10-10T00:00:00Z')
        self.assertEqual(target['expiresAt'], '2026-11-09T00:00:00Z')
    def test_network_failure_cannot_generate_target(self):
        def offline(_): raise OSError('offline')
        with self.assertRaises(OSError): verified_target(123, self.receipt, self.info, offline, self.now)

if __name__ == '__main__': unittest.main()

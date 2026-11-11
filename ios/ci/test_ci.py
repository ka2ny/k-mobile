import copy
import datetime as dt
import unittest
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch
from signing import cleanup
from signing import validate_profile
from preflight import select_device


class SigningChecks(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 11, 11, tzinfo=dt.timezone.utc)
        self.profile = {
            'UUID': '01234567-89AB-CDEF-0123-456789ABCDEF',
            'TeamIdentifier': ['ABCDEFGHIJ'],
            'ApplicationIdentifierPrefix': ['OLDPREFIX1'],
            'ExpirationDate': dt.datetime(2027, 1, 1),
            'ProvisionedDevices': ['synthetic-device'],
            'DeveloperCertificates': [b'synthetic-certificate'],
            'Entitlements': {'application-identifier': 'OLDPREFIX1.app.khole.mobile',
                             'com.apple.developer.team-identifier': 'ABCDEFGHIJ', 'get-task-allow': False},
        }

    def validate(self, profile, method='ad-hoc'):
        return validate_profile(profile, 'ABCDEFGHIJ', 'app.khole.mobile', method, self.now)

    def test_ad_hoc_allows_distinct_legacy_app_prefix(self):
        self.assertEqual(self.validate(self.profile)['uuid'], self.profile['UUID'])

    def test_store_rejects_device_profile(self):
        with self.assertRaises(ValueError): self.validate(self.profile, 'app-store')
        del self.profile['ProvisionedDevices']
        self.assertEqual(self.validate(self.profile, 'app-store')['method'], 'app-store')
        with self.assertRaises(ValueError): self.validate(self.profile)

    def test_rejects_invalid_signing_material(self):
        for field, value in [('TeamIdentifier', ['OTHERTEAM1']), ('UUID', '../../wrong'),
                             ('ExpirationDate', dt.datetime(2026, 1, 1)), ('DeveloperCertificates', []),
                             ('ProvisionsAllDevices', True)]:
            with self.subTest(field=field):
                profile = copy.deepcopy(self.profile)
                profile[field] = value
                with self.assertRaises(ValueError): self.validate(profile)

    def test_rejects_wrong_app_and_development_entitlements(self):
        for field, value in [('application-identifier', 'OLDPREFIX1.*'),
                             ('application-identifier', 'OLDPREFIX1.app.other'),
                             ('com.apple.developer.team-identifier', 'OTHERTEAM1'), ('get-task-allow', True)]:
            with self.subTest(field=field, value=value):
                profile = copy.deepcopy(self.profile)
                profile['Entitlements'][field] = value
                with self.assertRaises(ValueError): self.validate(profile)


class SimulatorSelection(unittest.TestCase):
    def test_uses_newest_available_iphone_with_supported_runtime(self):
        devices = {'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [dict(name='iPhone 17', udid='old', isAvailable=True)],
                   'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [dict(name='iPhone 18', udid='valid', isAvailable=True)],
                   'com.apple.CoreSimulator.SimRuntime.iOS-27-1': [dict(name='iPhone 18', udid='missing', isAvailable=False),
                                                                dict(name='iPad Pro', udid='ipad', isAvailable=True)]}
        self.assertEqual(select_device(devices), 'valid')

    def test_missing_simulator_is_actionable_failure(self):
        with self.assertRaisesRegex(ValueError, 'iOS 27'): select_device({})


class SigningCleanup(unittest.TestCase):
    def test_partial_install_restores_search_list_and_removes_owned_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            directory = root / "signing"
            directory.mkdir()
            keychain = directory / "build.keychain-db"
            keychain.touch()
            profile = root / "owned.mobileprovision"
            profile.touch()
            unrelated = root / "unrelated.mobileprovision"
            unrelated.touch()
            state = root / "k-mobile-signing-state.json"
            state.write_text(json.dumps(dict(directory=str(directory), keychain=str(keychain),
                                            profiles=[str(profile)], search_list=["original.keychain-db"])))
            with patch.dict(os.environ, {"RUNNER_TEMP": temp}), patch('signing.security') as security:
                cleanup()
                security.assert_any_call('list-keychains', '-d', 'user', '-s', 'original.keychain-db')
                security.assert_any_call('delete-keychain', str(keychain))
            self.assertFalse(directory.exists())
            self.assertFalse(profile.exists())
            self.assertFalse(state.exists())
            self.assertTrue(unrelated.exists())

    def test_cleanup_before_any_install_is_harmless(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.dict(os.environ, {"RUNNER_TEMP": temp}), patch('signing.security') as security:
                cleanup()
                security.assert_not_called()

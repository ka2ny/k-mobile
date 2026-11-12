"""Packaging checks use synthetic Mach-O fixtures, not a compiled app."""
import os
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from package_unsigned import pack, validate_app


class UnsignedPackaging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / 'Fixture.xcarchive'
        self.app = self.archive / 'Products/Applications/KMobile.app'
        self.app.mkdir(parents=True)
        self.output = Path(self.temp.name) / 'Fixture-unsigned.ipa'
        self.info = dict(DTPlatformName='iphoneos', CFBundleSupportedPlatforms=['iPhoneOS'], CFBundleExecutable='Fixture')
        self.write_info()
        # Thin arm64 executable header + LC_BUILD_VERSION for iOS. Test-only bytes.
        (self.app / 'Fixture').write_bytes(struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
                                          + struct.pack('<6I', 0x32, 24, 2, 0, 0, 0))
        (self.app / 'Fixture').chmod(0o755)

    def write_info(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_payload_and_unix_permissions_survive(self):
        (self.app / 'resource.txt').write_text('synthetic fixture')
        (self.app / 'resource-link').symlink_to('resource.txt')
        pack(self.archive, self.output)
        with zipfile.ZipFile(self.output) as bundle:
            self.assertIsNone(bundle.testzip())
            executable = bundle.getinfo('Payload/KMobile.app/Fixture')
            self.assertTrue(executable.external_attr >> 16 & 0o111)
            link = bundle.getinfo('Payload/KMobile.app/resource-link')
            self.assertTrue(stat.S_ISLNK(link.external_attr >> 16))
            self.assertEqual(bundle.read(link), b'resource.txt')
            self.assertTrue(all(name.startswith('Payload/KMobile.app/') for name in bundle.namelist()))

    def test_rejects_simulator_even_if_plist_claims_device(self):
        binary = self.app / 'Fixture'
        data = bytearray(binary.read_bytes())
        struct.pack_into('<I', data, 40, 7)  # PLATFORM_IOSSIMULATOR
        binary.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'physical iOS'):
            pack(self.archive, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_simulator_plist(self):
        self.info['DTPlatformName'] = 'iphonesimulator'
        self.write_info()
        with self.assertRaisesRegex(ValueError, 'device app'): validate_app(self.app)

    def test_rejects_executable_path_traversal(self):
        self.info['CFBundleExecutable'] = '../Fixture'
        self.write_info()
        with self.assertRaisesRegex(ValueError, 'executable name'): validate_app(self.app)

    def test_rejects_external_symlinks_before_creating_zip(self):
        (self.app / 'outside').symlink_to('../../../../external')
        with self.assertRaisesRegex(ValueError, 'outside its bundle'): pack(self.archive, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_invalid_macho_and_permissions(self):
        binary = self.app / 'Fixture'
        binary.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'permission'): validate_app(self.app)
        binary.chmod(0o755)
        binary.write_bytes(b'not a Mach-O')
        with self.assertRaisesRegex(ValueError, 'Mach-O'): validate_app(self.app)

    def test_rejects_invalid_load_command_bounds(self):
        binary = self.app / 'Fixture'
        data = bytearray(binary.read_bytes())
        struct.pack_into('<I', data, 36, 4096)
        binary.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'length'): validate_app(self.app)

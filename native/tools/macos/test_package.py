import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
import package


class PackagePreflightTest(unittest.TestCase):
    def inspect(self, arch='arm64', minimum='12.0', dependency='@rpath/libtest.dylib'):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'helper'
            binary.write_bytes(bytes.fromhex('cffaedfe'))

            def run(*args, **kwargs):
                if args[0] == 'lipo':
                    return arch
                if '-l' in args:
                    return f'cmd LC_BUILD_VERSION\n cmdsize 32\n minos {minimum}\n'
                return f'{binary}:\n {dependency} (compatibility version 1.0.0, current version 1.0.0)\n'

            with patch.object(package, 'run', side_effect=run):
                return package.check_binaries(Path(directory), 'arm64', '12.0')

    def test_rejects_newer_os_dependency(self):
        with self.assertRaisesRegex(RuntimeError, 'requires macOS 27.0'):
            self.inspect(minimum='27.0')

    def test_rejects_wrong_architecture(self):
        with self.assertRaisesRegex(RuntimeError, 'requires arm64'):
            self.inspect(arch='x86_64')

    def test_rejects_homebrew_runtime_dependency(self):
        with self.assertRaisesRegex(RuntimeError, 'Non-portable dependency'):
            self.inspect(dependency='/opt/homebrew/lib/libtest.dylib')

    def test_accepts_compatible_bundle(self):
        self.assertEqual(len(self.inspect()), 1)

    def test_rejected_notarization_is_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            item = Path(directory) / 'EasyNode.dmg'
            with patch.object(package, 'run', return_value='{"id":"test-id","status":"Invalid"}'):
                with self.assertRaisesRegex(RuntimeError, 'Notarization failed'):
                    package.notarize(item, 'profile')
            self.assertTrue(item.with_suffix('.dmg.notary.json').exists())


if __name__ == '__main__':
    unittest.main()

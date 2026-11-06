#!/usr/bin/env python3
"""Offline contract checks; inputs are fixtures, no APK/exe is built or run."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(os.environ.get('RELEASE_TOOLS_DIR', ROOT / 'tools'))


class ReleaseManifestsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / 'qa')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.notes = self.root / 'notes.txt'
        self.notes.write_text('Исправления 1.5.9', encoding='utf-8')
        self.base = 'https://example.org/releases/download/v1.5.9'

    def asset(self, name, content):
        path = self.root / name
        path.write_bytes(content)
        return path

    def check_asset(self, actual, name, source):
        self.assertEqual(actual['url'], f'{self.base}/{name}')
        self.assertEqual(actual['sha256'], hashlib.sha256(source.read_bytes()).hexdigest())

    def test_android_uses_canonical_urls_even_for_versioned_build_inputs(self):
        aapt = self.root / 'sdk/build-tools/35.0.0/aapt'
        aapt.parent.mkdir(parents=True)
        aapt.write_text("#!/bin/sh\necho \"package: name='test' versionCode='159' versionName='1.5.9'\"\n")
        aapt.chmod(0o755)
        arm64 = self.asset('cattunnel-1.5.9-arm64.apk', b'fixture-arm64')
        universal = self.asset('cattunnel-1.5.9-universal.apk', b'fixture-universal')
        result = subprocess.check_output(['bash', str(TOOLS / 'make_latest_json.sh'), self.base,
            str(arm64), str(universal), str(self.notes)],
            env={**os.environ, 'ANDROID_HOME': str(self.root / 'sdk')}, text=True)
        manifest = json.loads(result)
        self.check_asset(manifest['apks']['arm64-v8a'], 'cattunnel-arm64.apk', arm64)
        self.check_asset(manifest['apks']['universal'], 'cattunnel-universal.apk', universal)
        self.assertEqual(manifest['version'], '1.5.9')
        self.assertEqual(manifest['build'], 159)
        self.assertIn('expires', manifest)

    def test_windows_uses_canonical_url_even_for_versioned_build_input(self):
        setup = self.asset('cattunnel-1.5.9-windows-setup.exe', b'fixture-windows')
        result = subprocess.check_output(['bash', str(TOOLS / 'make_latest_windows_json.sh'), self.base,
            str(setup), '1.5.9', '159', str(self.notes)], text=True)
        manifest = json.loads(result)
        self.check_asset(manifest['apks']['windows-x64'], 'cattunnel-windows-setup.exe', setup)
        self.assertEqual(manifest['notes'], 'Исправления 1.5.9')


if __name__ == '__main__':
    unittest.main()

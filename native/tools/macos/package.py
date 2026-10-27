#!/usr/bin/env python3
"""Build, verify, sign and optionally notarize a macOS DMG. Never launches the app."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from datetime import datetime

NATIVE = Path(__file__).resolve().parents[2]
TEAM = '5BQLRCF2QW'
BUNDLE_ID = 'io.github.chaoszhu.easynode.macos'
MACH_MAGIC = {bytes.fromhex(v) for v in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def run(*args, capture=False):
    result = subprocess.run([str(a) for a in args], cwd=NATIVE, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def version(value):
    return tuple((list(map(int, value.split('.'))) + [0, 0])[:3])


def binaries(root):
    for item in root.rglob('*'):
        if item.is_symlink() or not item.is_file():
            continue
        with item.open('rb') as stream:
            if stream.read(4) in MACH_MAGIC:
                yield item


def check_binaries(root, arch, minimum):
    items = list(binaries(root))
    if not items:
        raise RuntimeError(f'No Mach-O binaries found in {root}')
    for item in items:
        arches = run('lipo', '-archs', item, capture=True).split()
        if arch not in arches:
            raise RuntimeError(f'{item.name} has {arches}, requires {arch}')
        load = run('otool', '-arch', arch, '-l', item, capture=True)
        minimums = re.findall(r'^\s*minos\s+([\d.]+)', load, re.M)
        minimums += re.findall(r'cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)', load)
        if not minimums:
            raise RuntimeError(f'Cannot determine minimum macOS version: {item}')
        for value in minimums:
            if version(value) > version(minimum):
                raise RuntimeError(f'{item.name} requires macOS {value}, exceeds {minimum}. '
                                   'Rebuild this dependency against the intended deployment target.')
        deps = run('otool', '-arch', arch, '-L', item, capture=True)
        for line in deps.splitlines():
            if ' (compatibility version' not in line:
                continue
            name = line.strip().split(' (compatibility version')[0]
            if not name.startswith(('/System/Library/', '/usr/lib/', '@rpath/', '@loader_path/', '@executable_path/')):
                raise RuntimeError(f'Non-portable dependency in {item.name}: {name}')
        for entry in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', load):
            if not entry.startswith(('@loader_path', '@executable_path', '/System/Library/', '/usr/lib/')):
                raise RuntimeError(f'Non-portable rpath in {item.name}: {entry}')
    return items


def identity(development):
    prefix = 'Apple Development:' if development else 'Developer ID Application:'
    output = run('security', 'find-identity', '-v', '-p', 'codesigning', capture=True)
    found = [(sha, name) for sha, name in re.findall(r'\) ([A-F0-9]{40}) "([^"]+)"', output)
             if name.startswith(prefix) and (development or f'({TEAM})' in name)]
    if len(found) != 1:
        raise RuntimeError(f'Expected one usable {prefix} identity; found {len(found)}. '
                           'Install the certificate and private key in Xcode / Keychain Access.')
    return found[0]


def verify_signature(app, expected, items):
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
    if expected.startswith('Developer ID Application:'):
        entitlements = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                                      capture_output=True, check=True).stdout
        if plistlib.loads(entitlements).get('com.apple.security.get-task-allow', False):
            raise RuntimeError('Distribution app must not allow debugger attachment')
    for item in [app, *items]:
        result = subprocess.run(['codesign', '-d', '--verbose=4', str(item)],
                                capture_output=True, text=True, check=True)
        details = result.stderr
        if f'TeamIdentifier={TEAM}' not in details or f'Authority={expected}' not in details:
            raise RuntimeError(f'Unexpected signing identity: {item}')
        if item == app and 'runtime' not in details:
            raise RuntimeError('Main app is missing Hardened Runtime')
        if expected.startswith('Developer ID Application:') and 'Timestamp=' not in details:
            raise RuntimeError(f'Missing secure timestamp: {item}')


def remove_build_rpaths(app, sha, development):
    """Remove SDK / Flutter build-machine fallback paths, then re-sign inside out."""
    changed = set()
    for item in binaries(app):
        load = run('otool', '-l', item, capture=True)
        paths = set(re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', load))
        for entry in paths:
            if entry.startswith(('@loader_path', '@executable_path', '/System/Library/', '/usr/lib/')):
                continue
            print(f'Removing build-machine rpath from {item.name}: {entry}', flush=True)
            run('install_name_tool', '-delete_rpath', entry, item)
            target = next((p for p in item.parents if p.suffix == '.framework'), item)
            changed.add(target)
    if not changed:
        return
    # The outer app seal must be regenerated after changing any nested code.
    changed.add(app)
    for target in sorted(changed, key=lambda p: len(p.parts), reverse=True):
        run('codesign', '--force', '--sign', sha,
            '--timestamp=none' if development else '--timestamp',
            '--preserve-metadata=identifier,entitlements,flags,runtime', target)


def notarize(item, profile):
    output = run('xcrun', 'notarytool', 'submit', item, '--keychain-profile', profile,
                 '--wait', '--output-format', 'json', capture=True)
    result = json.loads(output)
    item.with_suffix(item.suffix + '.notary.json').write_text(json.dumps(result, indent=2) + '\n')
    if result.get('status') != 'Accepted':
        raise RuntimeError(f'Notarization failed: {result}. Fetch details with notarytool log.')
    return result['id']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--development', action='store_true', help='Local-only Apple Development signature, no notarization')
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default='arm64')
    parser.add_argument('--min-macos', default='12.0', help='Enforced for every embedded binary; never inferred from the host')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; no passwords in arguments')
    parser.add_argument('--app', type=Path, help='Package an already built, correctly signed Release app')
    args = parser.parse_args()
    if args.development and args.notary_profile:
        parser.error('Apple Development signatures cannot be notarized')
    if not re.fullmatch(r'\d+(\.\d+){0,2}', args.min_macos):
        parser.error('Invalid --min-macos version')
    sha, name = identity(args.development)
    print(f'Signing identity: {name}', flush=True)
    if args.app:
        app = args.app.resolve()
    else:
        check_binaries(NATIVE / 'build/rdp/macos/bundle', args.arch, args.min_macos)
        run(os.environ.get('FLUTTER', 'flutter'), 'build', 'macos', '--release', '--config-only')
        build = NATIVE / 'build' / f'macos-release-{args.arch}'
        run('xcodebuild', '-workspace', 'macos/Runner.xcworkspace', '-scheme', 'Runner',
            '-configuration', 'Release', '-derivedDataPath', build,
            '-destination', f'platform=macOS,arch={args.arch}', '-allowProvisioningUpdates',
            *(['-allowProvisioningDeviceRegistration'] if args.development else []),
            f'ARCHS={args.arch}', 'ONLY_ACTIVE_ARCH=YES', f'MACOSX_DEPLOYMENT_TARGET={args.min_macos}',
            f'DEVELOPMENT_TEAM={TEAM}',
            f'CODE_SIGN_IDENTITY={"Apple Development" if args.development else name}',
            f'CODE_SIGN_STYLE={"Automatic" if args.development else "Manual"}', 'build')
        app = build / 'Build/Products/Release/EasyNode.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != BUNDLE_ID:
        raise RuntimeError('Unexpected app Bundle ID')
    if version(info['LSMinimumSystemVersion']) != version(args.min_macos):
        raise RuntimeError('App minimum OS does not match --min-macos')
    verify_signature(app, name, list(binaries(app)))
    label = 'development' if args.development else 'notarized' if args.notary_profile else 'signed-unnotarized'
    output = NATIVE / 'build/macos-dist' / datetime.now().strftime('%Y%m%d-%H%M%S')
    output.mkdir(parents=True, exist_ok=False)
    stage = output / 'staging'
    stage.mkdir()
    bundled = stage / 'EasyNode.app'
    run('ditto', app, bundled)
    remove_build_rpaths(bundled, sha, args.development)
    items = check_binaries(bundled, args.arch, args.min_macos)
    verify_signature(bundled, name, items)
    submissions = []
    if args.notary_profile:
        archive = output / 'EasyNode.zip'
        run('ditto', '-c', '-k', '--keepParent', bundled, archive)
        submissions.append(notarize(archive, args.notary_profile))
        run('xcrun', 'stapler', 'staple', bundled)
        run('xcrun', 'stapler', 'validate', bundled)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', bundled)
    (stage / 'Applications').symlink_to('/Applications')
    dmg = output / f'EasyNode-{info["CFBundleShortVersionString"]}-{args.arch}-{label}.dmg'
    run('hdiutil', 'create', '-volname', 'EasyNode', '-srcfolder', stage,
        '-format', 'UDZO', '-ov', dmg)
    signing = ['codesign', '--force', '--sign', sha]
    if not args.development:
        signing.append('--timestamp')
    run(*signing, dmg)
    run('hdiutil', 'verify', dmg)
    run('codesign', '--verify', '--strict', '--verbose=2', dmg)
    if args.notary_profile:
        submissions.append(notarize(dmg, args.notary_profile))
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)
    manifest = dict(file=dmg.name, bundleId=BUNDLE_ID, team=TEAM, identity=name,
                    architecture=args.arch, minimumMacOS=args.min_macos, status=label,
                    version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                    notarizationIds=submissions)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Created: {dmg}\nStatus: {label}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        sys.exit(str(error))

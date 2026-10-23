#!/usr/bin/env python3
"""Close the Mach-O dependency graph and rewrite it to a relocatable bundle."""
from pathlib import Path
import shutil
import subprocess
import sys

build, bundle, source = map(lambda s: Path(s).resolve(), sys.argv[1:])
if bundle.exists():
    shutil.rmtree(bundle)
(bundle / 'lib').mkdir(parents=True)
licenses = bundle / 'licenses'
licenses.mkdir()
for name in ['LICENSE', 'NOTICE']:
    if (source / name).exists():
        shutil.copy2(source / name, licenses / f'FreeRDP-{name}')
shutil.copy2(source / 'resources/font/OFL.txt', licenses / 'OpenSans-OFL.txt')
shutil.copy2(source / 'client/SDL/SDL3/dialogs/font/OFL.txt', licenses / 'SDL-dialog-font-OFL.txt')
shutil.copy2(build / 'client/SDL/SDL3/easynode-rdp', bundle / 'easynode-rdp')
queue = [(build / 'client/SDL/SDL3/easynode-rdp', bundle / 'easynode-rdp')]
seen = set()


def output(*args):
    return subprocess.check_output(args, text=True)


def rpaths(binary):
    lines = output('otool', '-l', str(binary)).splitlines()
    return [lines[i + 2].strip().split(' (offset')[0].removeprefix('path ')
            for i, line in enumerate(lines) if line.strip() == 'cmd LC_RPATH']


def resolve(name, original):
    if name.startswith('@loader_path/'):
        return (original.parent / name.removeprefix('@loader_path/')).resolve()
    if name.startswith('@rpath/'):
        filename = name.removeprefix('@rpath/')
        # Installed FreeRDP libs and Homebrew dependencies have these rpaths.
        paths = [build / 'libfreerdp', original.parent]
        for entry in rpaths(original):
            paths.append(Path(entry.replace('@loader_path', str(original.parent))))
        for path in paths:
            if (path / filename).exists():
                return (path / filename).resolve()
        raise RuntimeError(f'Unresolved dependency {name} of {original}')
    return Path(name).resolve()


while queue:
    original, target = queue.pop(0)
    if target in seen:
        continue
    seen.add(target)
    target.chmod(0o755)
    # Strip any old ad-hoc signature before changing load commands.
    subprocess.run(['codesign', '--remove-signature', str(target)], capture_output=True)
    lines = output('otool', '-L', str(original)).splitlines()[1:]
    for line in lines:
        name = line.strip().split(' (compatibility')[0]
        if name.startswith(('/System/', '/usr/lib/')):
            continue
        dependency = resolve(name, original)
        if dependency == original.resolve():
            continue
        destination = bundle / 'lib' / dependency.name
        if not destination.exists():
            shutil.copy2(dependency, destination)
            queue.append((dependency, destination))
            # Include upstream formula-provided notices (including SDL/font libs).
            parts = dependency.parts
            if 'Cellar' in parts:
                i = parts.index('Cellar')
                prefix = Path(*parts[:i + 3])
                for file in prefix.rglob('*'):
                    if file.is_file() and file.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE', 'FTL.TXT')):
                        dest = licenses / parts[i + 1] / file.relative_to(prefix)
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(file, dest)
        subprocess.run(['install_name_tool', '-change', name, f'@rpath/{dependency.name}', str(target)], check=True)
    if target != bundle / 'easynode-rdp':
        subprocess.run(['install_name_tool', '-id', f'@rpath/{target.name}', str(target)], check=True)
    for entry in rpaths(target):
        subprocess.run(['install_name_tool', '-delete_rpath', entry, str(target)], check=True)
    subprocess.run(['install_name_tool', '-add_rpath', '@loader_path/lib' if target == bundle / 'easynode-rdp' else '@loader_path', str(target)], check=True)
# Xcode signs these again with the app identity after embedding.
for target in sorted(seen, key=lambda p: p == bundle / 'easynode-rdp'):
    subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
(bundle / 'engine-version.txt').write_text('FreeRDP 3.32.2 + EasyNode SDL3 IPC\n')

#!/usr/bin/env python3
"""Fetch a hash-pinned FreeRDP source and apply a small, fail-closed IPC patch."""
import hashlib
from pathlib import Path
import shutil
import sys
import tarfile
import urllib.request

VERSION = '3.32.2'
SHA256 = '9ccb8357bf0188044a460de775c7ea289ca7d2a2a917eca0f0a7c4dc9c8b08ea'
TOOLS = Path(__file__).resolve().parent


def replace_once(file, old, new):
    text = file.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise RuntimeError(f'FreeRDP patch context changed: {file.name}: {old!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def prepare(root):
    root.mkdir(parents=True, exist_ok=True)
    source = root / f'FreeRDP-{VERSION}'
    stamp = source / '.easynode-patch'
    digest = hashlib.sha256(Path(__file__).read_bytes() + (TOOLS / 'easynode_ipc.hpp').read_bytes()).hexdigest()
    if stamp.exists() and stamp.read_text(encoding='utf-8') == digest:
        return source
    archive = root / f'freerdp-{VERSION}.tar.gz'
    if not archive.exists():
        urllib.request.urlretrieve(f'https://github.com/FreeRDP/FreeRDP/archive/refs/tags/{VERSION}.tar.gz', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError(f'FreeRDP source checksum mismatch: remove {archive} and retry')
    if source.exists():
        shutil.rmtree(source)
    with tarfile.open(archive) as tar:
        # This archive has already been verified against a fixed SHA-256.
        tar.extractall(root)
    sdl = source / 'client/SDL/SDL3'
    shutil.copy2(TOOLS / 'easynode_ipc.hpp', sdl)
    replace_once(sdl / 'sdl_freerdp.cpp', 'int main(int argc, char* argv[])', '#include "easynode_ipc.hpp"\n\nint main(int argc, char* argv[])')
    # Do not detach Windows standard handles: they are private parent/child pipes.
    replace_once(sdl / 'sdl_freerdp.cpp', 'sdl::win32::release_transient_console();', '// EasyNode keeps inherited IPC pipe handles.')
    replace_once(sdl / 'sdl_freerdp.cpp', '\tif (!SDL_SetHint(SDL_HINT_ALLOW_ALT_TAB_WHILE_GRABBED',
                 '\tif (!easynode::read_password(settings)) return 1;\n\n\tif (!SDL_SetHint(SDL_HINT_ALLOW_ALT_TAB_WHILE_GRABBED')
    replace_once(sdl / 'sdl_freerdp.cpp', '\t/* Redirect SDL log messages to wLog */',
                 '\teasynode::control(sdl->context());\n\n\t/* Redirect SDL log messages to wLog */')
    replace_once(sdl / 'sdl_context.cpp', '#include "sdl_config.hpp"', '#include "sdl_config.hpp"\n#include "easynode_ipc.hpp"')
    replace_once(sdl / 'sdl_context.cpp', 'sdl->setConnected(true);', 'sdl->setConnected(true);\n\teasynode::connected();')
    replace_once(sdl / 'CMakeLists.txt', 'set(SDL_CLIENT_UUID "com.freerdp.client.sdl3")',
                 'set(SDL_CLIENT_UUID "com.easynode.rdp")\nset(SDL_CLIENT_BINARY_NAME "EasyNode Remote Desktop")\nset_target_properties(${MODULE_NAME} PROPERTIES OUTPUT_NAME "easynode-rdp")')
    replace_once(source / 'client/SDL/common/sdl_prefs.cpp',
                 'std::string SdlPref::get_default_file(bool systemConfigOnly)\n{',
                 'std::string SdlPref::get_default_file(bool systemConfigOnly)\n{\n'
                 '\tif (const char* config = std::getenv("EASYNODE_RDP_CONFIG"))\n'
                 '\t\treturn (fs::path(config) / "sdl-freerdp.json").string();')
    stamp.write_text(digest, encoding='utf-8')
    return source


if __name__ == '__main__':
    print(prepare(Path(sys.argv[1]).resolve()))

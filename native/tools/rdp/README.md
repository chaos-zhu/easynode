# EasyNode local RDP helper

FreeRDP **3.32.2**, upstream Apache-2.0, SHA-256:
`9ccb8357bf0188044a460de775c7ea289ca7d2a2a917eca0f0a7c4dc9c8b08ea`.

`prepare.py` downloads the fixed source archive and adds `easynode_ipc.hpp` to
its official SDL3 frontend. Patch contexts must match exactly. Upstream rendering,
keyboard/mouse, clipboard, TLS/NLA and certificate confirmation remain in use.

Each connection launches our bundled `easynode-rdp` helper, creating its own
native window. Stdin starts with a four-byte big-endian UTF-8 password length,
followed by those bytes. Remaining lines are `focus` or `close` commands. EOF
terminates an orphan helper. Stdout emits `EASYNODE_RDP connected` only after
PostConnect succeeds. The parent also observes the process exit status. No
password is passed in arguments, environment variables or temporary files.

`EASYNODE_RDP_CONFIG` identifies EasyNode's application-support `rdp` directory;
it contains the helper's certificate records and optional SDL preferences.
This environment value is a path, not a credential. The helper does not reuse
an external client's configuration. Proxy/jump connections use a loopback relay
and preserve the destination name for RDP authentication and certificate checks.
FreeRDP keys its certificate store by host and port; a new loopback port may
require certificate confirmation again for a tunneled connection.

## Build and embed

See `../../DESKTOP.md` for platform commands. Build outputs stay in ignored
`native/build/rdp/`. The macOS script follows the Mach-O dependency graph, copies
runtime libraries and notices, removes build-machine rpaths, and adds only bundle
relative paths. Xcode embeds and signs the helper after Flutter's embed phase.
Windows copies FreeRDP and vcpkg runtime DLLs into the installed `rdp/` directory.
Release packaging fails if the prepared engine is absent.

These scripts prepare a development engine for the current host architecture.
For distribution, build dependencies against the intended minimum OS version;
Homebrew bottles may require the development machine's macOS version. macOS
universal builds require matching universal dependencies and helper. Windows
requires its matching runtime and a build on Windows. Sign/notarize the final
application and nested code as part of the later distribution work.

FreeRDP, SDL, crypto/font dependency licenses and embedded font OFL notices travel
with the helper in `licenses/`. Sources remain available from the pinned upstream
archive plus the patch script and header in this directory. Dependencies supplied
by Homebrew/vcpkg are not version locked by this initial development workflow.

## Validation boundary

Unit/widget tests use fake engine processes and a loopback-only transport test.
They never open a remote desktop window or connect to an external machine.
The macOS helper has been compiled and its dependency paths/signatures checked.
App launch, real RDP interoperability, certificate dialogs, keyboard shortcuts,
clipboard, graphics performance and Windows execution require user acceptance.

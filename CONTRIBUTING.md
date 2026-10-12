# Contributing to Vela

Start with an issue describing the behavior or improvement you want. For bugs, include your macOS version, Vela version, steps to reproduce and the expected result. A short public sample file is useful when a codec or subtitle issue depends on input data.

Do not post personal media, credentials, private network addresses or unredacted logs. Report security problems privately as described in SECURITY.md.

## Development

Use the requirements and build commands in README.md. Vela uses SwiftUI/AppKit for the interface, libVLC for playback, ScreenCaptureKit for screen input, and a separate FFmpeg process for supported export inputs. The Lua host includes adapted VLC bindings and a frontend playlist/dialog adapter.

- Keep changes focused and preserve existing user data and privacy preferences.
- Do not update VLC private ABI headers independently of the bundled engine.
- Test media behavior with generated fixtures and independently inspect exported files.
- For UI changes, inspect the actual native window and relevant keyboard/accessibility behavior.
- Extend tests for new behavior, not merely to repeat implementation details.
- Keep release claims consistent with observed results.

Run `scripts/check-repository.py`, the syntax checks in the CI workflow, and relevant integration checks before opening a pull request. Record what you tested and any remaining limits. You do not need physical hardware for an ordinary contribution; say when a change has only software coverage.

## Pull requests

Explain the problem, resulting behavior and validation. Avoid unrelated refactors. Contributions are distributed under the project's GPL-2.0-or-later license; preserve third-party notices. Follow CODE_OF_CONDUCT.md.

# Publishing a release

1. Update CFBundleShortVersionString and increment CFBundleVersion in Info.plist. Update CHANGELOG.md and relevant documentation.
2. Verify the pinned engine, dependency provenance and redistribution notices. Rebuild after any code, runtime or artwork change.
3. Run repository/syntax checks and the integration suite. Inspect native UI behavior affected by the change. Record hardware/service limits honestly.
4. Run `python3 scripts/package-release.py VERSION`. This packages `dist/Vela.app`, the committed source tree and verification results. Build caches and private configuration are excluded.
5. Extract and verify the app archive. Run the media suite against the extracted binary with the same fixtures; independently inspect its outputs.
6. If Developer ID credentials are available, sign with hardened runtime, notarize and staple before packaging. Otherwise label the release locally signed and not notarized. Never claim notarization based on an ad-hoc signature.
7. Commit, tag `vVERSION`, push, and use `gh release create` with the release notes and checked assets from dist/releases. Attach runtime source archives and provenance matching the shipped binaries.
8. Verify the published tag, source and uploaded checksums. Test the download instructions.

The initial public release is v1.1. Use new version tags for subsequent releases; do not silently replace an existing public binary or move its tag. Keep historical sources and checksums available.

Update the README download link and `docs/images/download.svg` to the new version when publishing a release. The source-check badge remains automatic.

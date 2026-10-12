# Runtime sources and redistribution

Release binaries include the official VLC 3.0.24 ARM64 runtime and a separately bundled FFmpeg 8.1.1 helper. Their components retain their original licenses.

The release's runtime-source archive contains the official VLC source distribution, its fetched and checksum-verified contrib source archives, the FFmpeg helper's matching source archives, and the preserved Homebrew formula/build provenance. A manifest records upstream URLs, versions, revisions and archive checksums. Vela's adapted bindings and build scripts are in the repository and tagged source archive.

The helper manifest in the app lists every bundled non-system library. macOS system frameworks and libarchive are system dependencies rather than bundled binaries. No community reference images, exported icons or fonts are part of the public app.

When changing a runtime or library, update provenance, preserve applicable notices and collect sources corresponding to the actual distributed binaries. Keep dependency sources available alongside the release. The original upstream licensing pages are [VideoLAN](https://www.videolan.org/legal.html) and [FFmpeg](https://ffmpeg.org/legal.html).

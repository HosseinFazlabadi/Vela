# Vela third-party notices

Vela is an independent macOS player. It is not a VideoLAN product.

The bundled libVLC engine and VLC runtime plugins are copied without source changes from the user's official VLC 3.0.24 Apple Silicon installation. Copyright VideoLAN and the respective contributors. The libVLC headers carry their original LGPL notices. VLC's plugins and dependencies have their respective licenses, including GPL/LGPL components. Corresponding VLC source: https://download.videolan.org/vlc/3.0.24/vlc-3.0.24.tar.xz . Full official source and license information: https://code.videolan.org/videolan/vlc . Keep the applicable license notices and corresponding-source obligations if redistributing this build.

Design inspiration: VLC Redesign community file, https://www.figma.com/community/file/1691465999134370980/vlc-redesign . The public release uses macOS system symbols and Vela's original logo; no exported community icons, reference images or fonts are distributed. System symbols are rendered by macOS, not bundled as standalone artwork.

Lua 5.1.5 is compiled from the official Lua.org source. Copyright 1994–2012 Lua.org, PUC-Rio, MIT license; see COPYING-LUA.txt. dkjson 2.8 copyright 2010–2024 David Heiko Kolf, MIT license; the complete notice is retained in ExtensionRuntime/dkjson.lua.

VLSub was downloaded from the original exebetche/vlsub repository only as a local compatibility test. It is not bundled or installed by this release.

FFmpeg 8.1.1 export helper and its Homebrew library dependencies are bundled as a separate executable process. This build enables GPL/version-3 components. FFmpeg source and licensing: https://ffmpeg.org/download.html and https://ffmpeg.org/legal.html . The export helper manifest identifies every bundled library and Homebrew formula/version; bundled formula files retain upstream source URLs and license expressions under Frameworks/Export/Notices. Relevant notices and GPL license text are included. Playback remains in libVLC.

The extension host compiles the GPL VLC 3.0.24 Lua bindings against the pinned engine, with small adapters for Vela input/audio objects. Original sources and private ABI headers are retained in Vendor/vlc-3.0.24; adaptations are in Sources/CLibVLC/VLCLua. Lua includes VideoLAN's fixed-width bytecode, vararg stack fix, and disabled native dynamic-module loading patches, retained under Vendor/vlc-3.0.24/contrib/src/lua. The original Lua modules are included as source. Vela source is provided under GPL-2.0-or-later; redistribution must comply with the GPL bindings and bundled dependencies.

libarchive 3.7.7 headers retain their BSD notices under Vendor/libarchive/include. Package extraction links the macOS system libarchive rather than shipping another binary. Source: https://github.com/libarchive/libarchive/tree/v3.7.7 .

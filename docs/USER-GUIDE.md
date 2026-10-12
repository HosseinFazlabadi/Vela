# User guide

## Open and control media

Use File → Open File(s), Open Folder or Open Network Stream. Drag files or a playlist onto the window. Space toggles playback. Playback, Audio and Video menus expose tracks, speed, timing, image and chapter controls. Seek with the timeline; choose the time display to jump to a specific position.

## Library and playlists

Open the sidebar and select Media Library. Add files to retain them independently of history. Queue and Recent have separate views. Use item context menus to add to the library or remove an entry. Saved playlists, bookmarks and resume positions remain local to your Mac.

## Capture, record and convert

File → Open Capture Source offers camera, microphone, screen and Test Pattern. Choose a real source to trigger the relevant macOS permission request. Screen input offers an optional system-audio toggle; Vela's own audio is excluded to prevent feedback. Test Pattern exercises video and audio without capturing a device.

Use the record/export controls and choose an output different from your source. MP4/WAV conversion and MKV recording of supported file/network inputs use the separate bundled FFmpeg helper. Live raw capture uses VLC's output pipeline. Export status and failures are shown in the interface.

## Discs, streaming and renderers

File → Open Disc accepts disc paths and authored disc folders. Tools → Disc Controls exposes titles, chapters and menu navigation. Use arrow keys and Return for disc menus.

Tools → Stream Media configures HTTP, UDP or RTP delivery. The default HTTP loopback address serves only this Mac; use an appropriate local interface address for another device. Tools → Casting scans for compatible renderers when requested. Select Local Output to return to this Mac. Device and network compatibility depends on the environment; software fixtures do not certify every physical receiver.

## Lua extensions

Tools → Extensions installs `.lua`, VLC-compatible `.luac`, VLE/ZIP packages, or a folder containing `script.lua`. Activate an installed extension to open its native Vela window. The bundled Media Tools example provides a simple starting point. Deactivate or remove extensions through the manager.

Extensions can read files and use network services. The pinned engine API, supported methods and layout bounds are documented in EXTENSION-API.md. A valid extension can still depend on an unavailable service or a different VLC version.

## Data and removal

Data and engine configuration live in `~/Library/Application Support/Vela`; app preferences use `local.vela.player`. Removing the app does not delete your media. Quit before installing an update. Keep a backup of the application-support folder if you want to preserve your library when changing machines.

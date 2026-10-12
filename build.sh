#!/bin/bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_ROOT="${VELA_OUTPUT_DIR:-$SOURCE_ROOT/dist}"
mkdir -p "$OUTPUT_ROOT"
mkdir -p "$SOURCE_ROOT/.build"
APP="$(mktemp -d "$SOURCE_ROOT/.build/VelaBundle.XXXXXX")"
DELIVERABLE="$OUTPUT_ROOT/Vela.app"
VLC_APP="${VELA_VLC_APP:-/Applications/VLC.app}"
if [[ ! -f "$VLC_APP/Contents/MacOS/lib/libvlc.dylib" ]]; then
  echo "Install VLC for this Mac, or set VELA_VLC_APP to the VLC.app path." >&2
  exit 1
fi
python3 - "$VLC_APP/Contents/Info.plist" <<'ENGINE_VERSION'
import plistlib,sys
with open(sys.argv[1],'rb') as file: version=plistlib.load(file)['CFBundleShortVersionString']
if version!='3.0.24':raise SystemExit('Vela extension ABI requires the pinned official VLC 3.0.24 runtime; set VELA_VLC_APP to that installation.')
ENGINE_VERSION
mkdir -p "$SOURCE_ROOT/.build" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks/VLC"
/usr/bin/ditto "$VLC_APP/Contents/MacOS/lib" "$APP/Contents/Frameworks/VLC/lib"
/usr/bin/ditto "$VLC_APP/Contents/MacOS/plugins" "$APP/Contents/Frameworks/VLC/plugins"
/usr/bin/ditto "$VLC_APP/Contents/MacOS/share" "$APP/Contents/Frameworks/VLC/share"
/usr/bin/ditto "$SOURCE_ROOT/Assets" "$APP/Contents/Resources/Assets"
/usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -target arm64-apple-macosx14.0 -I "$SOURCE_ROOT/Sources/CLibVLC/include" \
  -c "$SOURCE_ROOT/Sources/CLibVLC/RendererBridge.c" -o "$SOURCE_ROOT/.build/RendererBridge.o"
/usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -target arm64-apple-macosx14.0 -I "$SOURCE_ROOT/Sources/CLibVLC/include" -c "$SOURCE_ROOT/Sources/CLibVLC/CaptureBridge.c" -o "$SOURCE_ROOT/.build/CaptureBridge.o"
mkdir -p "$SOURCE_ROOT/.build/lua"
for src in "$SOURCE_ROOT"/Vendor/lua-5.1.5/src/*.c; do
  case "$(basename "$src")" in lua.c|luac.c) continue;; esac
  if [[ -f "$SOURCE_ROOT/.build/lua/$(basename "$src" .c).o" && "$SOURCE_ROOT/.build/lua/$(basename "$src" .c).o" -nt "$src" ]]; then continue; fi
  /usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -O2 -DLUA_USE_MACOSX -DLUA_COMPAT_MODULE -DLUA_COMPAT_APIINTCASTS -target arm64-apple-macosx14.0 -I "$SOURCE_ROOT/Vendor/lua-5.1.5/src" -c "$src" -o "$SOURCE_ROOT/.build/lua/$(basename "$src" .c).o"
done
/usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -O2 -target arm64-apple-macosx14.0 -I "$SOURCE_ROOT/Vendor/lua-5.1.5/src" -I "$SOURCE_ROOT/Sources/CLibVLC/include" -DENABLE_VLM -DHAVE_POLL -DHAVE_POLL_H -DMODULE_STRING=\"vela\" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/include" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/lib" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/modules/lua" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/modules/lua/libs" -c "$SOURCE_ROOT/Sources/CLibVLC/ExtensionBridge.c" -o "$SOURCE_ROOT/.build/ExtensionBridge.o"
/usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -O2 -target arm64-apple-macosx14.0 -I "$SOURCE_ROOT/Vendor/lua-5.1.5/src" -I "$SOURCE_ROOT/Sources/CLibVLC/include" -DENABLE_VLM -DHAVE_POLL -DHAVE_POLL_H -DMODULE_STRING=\"vela\" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/include" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/lib" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/modules/lua" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/modules/lua/libs" -c "$SOURCE_ROOT/Sources/CLibVLC/DiscoveryBridge.c" -o "$SOURCE_ROOT/.build/DiscoveryBridge.o"
/usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -O2 -target arm64-apple-macosx14.0 -I "$SOURCE_ROOT/Sources/CLibVLC/include" -I "$SOURCE_ROOT/Vendor/libarchive/include" -c "$SOURCE_ROOT/Sources/CLibVLC/ExtensionArchive.c" -o "$SOURCE_ROOT/.build/ExtensionArchive.o"
mkdir -p "$SOURCE_ROOT/.build/vlclua"
for src in "$SOURCE_ROOT"/Sources/CLibVLC/VLCLua/*.c; do
  /usr/bin/xcrun clang -ffile-prefix-map="$SOURCE_ROOT"=. -O2 -target arm64-apple-macosx14.0 -DENABLE_VLM -DHAVE_POLL -DHAVE_POLL_H -DMODULE_STRING=\"vela\" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/include" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/lib" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/modules/lua" -I "$SOURCE_ROOT/Vendor/vlc-3.0.24/modules/lua/libs" -I "$SOURCE_ROOT/Vendor/lua-5.1.5/src" -I "$SOURCE_ROOT/Sources/CLibVLC/include" -c "$src" -o "$SOURCE_ROOT/.build/vlclua/$(basename "$src" .c).o"
done
/usr/bin/ditto "$SOURCE_ROOT/ExtensionRuntime" "$APP/Contents/Resources/ExtensionRuntime"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -O -file-prefix-map "$SOURCE_ROOT=." -debug-prefix-map "$SOURCE_ROOT=." \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$SOURCE_ROOT/.build/ModuleCache" \
  -I "$SOURCE_ROOT/Sources/CLibVLC" \
  -I "$SOURCE_ROOT/Sources/CLibVLC/include" \
  -L "$APP/Contents/Frameworks/VLC/lib" -lvlc -lvlccore -larchive \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks/VLC/lib' \
  -framework AppKit -framework SwiftUI -framework MediaPlayer -framework AVFoundation -framework ScreenCaptureKit -framework CoreMedia -framework CoreVideo \
  "$SOURCE_ROOT"/Sources/Vela/*.swift "$SOURCE_ROOT/.build/RendererBridge.o" "$SOURCE_ROOT/.build/CaptureBridge.o" "$SOURCE_ROOT/.build/ExtensionBridge.o" "$SOURCE_ROOT/.build/DiscoveryBridge.o" "$SOURCE_ROOT/.build/ExtensionArchive.o" "$SOURCE_ROOT"/.build/lua/*.o "$SOURCE_ROOT"/.build/vlclua/*.o -o "$APP/Contents/MacOS/Vela"
/usr/bin/xcrun actool "$SOURCE_ROOT/Assets.xcassets" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --target-device mac \
  --app-icon AppIcon \
  --output-partial-info-plist "$SOURCE_ROOT/.build/assets-info.plist" > "$SOURCE_ROOT/.build/assets.log"
/bin/cp "$SOURCE_ROOT/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$SOURCE_ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
/bin/cp "$SOURCE_ROOT"/COPYING-*.txt "$APP/Contents/Resources/"
python3 "$SOURCE_ROOT/bundle-export-helper.py" "$APP/Contents/Frameworks/Export"
/usr/bin/xattr -cr "$APP"
if ! /usr/bin/codesign --force --deep --sign - "$APP" > /dev/null; then
  /usr/bin/xattr -cr "$APP"
  /usr/bin/codesign --force --deep --sign - "$APP" > /dev/null
fi
if [[ -e "$DELIVERABLE" ]]; then
  PREVIOUS="$(mktemp -d "$SOURCE_ROOT/.build/previous.XXXXXX")"
  /bin/mv "$DELIVERABLE" "$PREVIOUS/Vela.app"
fi
/usr/bin/ditto --noacl --extattr "$APP" "$DELIVERABLE"
printf "%s\n" "$APP" > "$SOURCE_ROOT/.build/bundle-path.txt"
/usr/bin/xattr -d com.apple.FinderInfo "$DELIVERABLE" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict "$DELIVERABLE"
echo "Built $DELIVERABLE"

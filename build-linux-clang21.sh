#!/bin/bash
# Builds SmartClicker on Linux without Theos (rootless + rootful debs).
# Needs clang-21, an iPhoneOS SDK, dpkg-deb, and ld64/lipo/ldid in TOOLBIN (lld can't link arm64e).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${SDK:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUT=${OUT:-$HERE/build}
VERSION=$(sed -n 's/^Version: //p' "$HERE/control")
rm -rf "$OUT"; mkdir -p "$OUT"
CFLAGS="-isysroot $SDK -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter $EXTRA_CFLAGS"
LDFLAGS="-isysroot $SDK -fuse-ld=$TOOLBIN/ld -Wl,-dead_strip"

# tweak
for a in arm64 arm64e; do
  for f in Tweak Engine Shared/SCMaterial; do
    clang-21 -target $a-apple-ios15.0 $CFLAGS -I"$HERE" -c "$HERE/$f.m" -o "$OUT/$(basename $f).$a.o"
  done
  clang-21 -target $a-apple-ios15.0 $LDFLAGS -dynamiclib -o "$OUT/SmartClicker.$a.dylib" "$OUT/Tweak.$a.o" "$OUT/Engine.$a.o" "$OUT/SCMaterial.$a.o" \
    -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreFoundation -lobjc \
    -install_name /var/jb/Library/MobileSubstrate/DynamicLibraries/SmartClicker.dylib
done
"$TOOLBIN/lipo" -create "$OUT/SmartClicker.arm64.dylib" "$OUT/SmartClicker.arm64e.dylib" -output "$OUT/SmartClicker.dylib"
"$TOOLBIN/ldid" -S "$OUT/SmartClicker.dylib"

# app (arm64 is enough)
for f in main Backup; do
  clang-21 -target arm64-apple-ios15.0 $CFLAGS -I"$HERE" -c "$HERE/App/$f.m" -o "$OUT/$f.o"
done
clang-21 -target arm64-apple-ios15.0 $LDFLAGS -o "$OUT/SmartClicker" "$OUT/main.o" "$OUT/Backup.o" "$OUT/Engine.arm64.o" "$OUT/SCMaterial.arm64.o" \
  -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreFoundation \
  -framework UniformTypeIdentifiers -lz -lobjc
"$TOOLBIN/ldid" -S"$HERE/App/entitlements.plist" "$OUT/SmartClicker"

# rootless (/var/jb, iphoneos-arm64) and rootful (/, iphoneos-arm)
package() { # $1 = install prefix ("" or /var/jb), $2 = dpkg architecture, $3 = file suffix
  local P="$OUT/pkg$3" PFX="$1"
  rm -rf "$P"
  mkdir -p "$P/DEBIAN" "$P$PFX/Library/MobileSubstrate/DynamicLibraries" "$P$PFX/Applications/SmartClicker.app"
  sed "s/^Architecture: .*/Architecture: $2/" "$HERE/control" > "$P/DEBIAN/control"
  for s in postinst prerm; do
    sed "s#/var/jb/Applications#$PFX/Applications#g" "$HERE/$s" > "$P/DEBIAN/$s"
    chmod 755 "$P/DEBIAN/$s"
  done
  cp "$OUT/SmartClicker.dylib" "$HERE/SmartClicker.plist" "$P$PFX/Library/MobileSubstrate/DynamicLibraries/"
  local A="$P$PFX/Applications/SmartClicker.app"
  cp "$OUT/SmartClicker" "$HERE/App/Info.plist" "$HERE"/App/res/*.png "$A/"
  chmod 755 "$A/SmartClicker"
  printf 'APPL????' > "$A/PkgInfo"
  dpkg-deb -Zxz --root-owner-group -b "$P" "$HERE/com.wmhakuifan.smartclicker_${VERSION}_$2.deb"
}
package /var/jb iphoneos-arm64 -rootless
package "" iphoneos-arm -rootful

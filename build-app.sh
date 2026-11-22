#!/bin/zsh
# Builds Nabız.app in this folder.
#
# İmza. SIGN_IDENTITY tanımlı değilse eskisi gibi ad hoc imzalanır (ilk açılışta macOS uyarı verir).
#   SIGN_IDENTITY="Developer ID Application: Ad Soyad (TAKIMID)"  → hardened runtime ile Developer ID imzası
#   NOTARY_PROFILE=<ad>  (xcrun notarytool store-credentials ile kaydedilmiş) → ayrıca Apple onayı ve staple;
#                        dağıtım için dist/Nabiz-macOS.zip de üretilir.
set -e
cd "$(dirname "$0")"
swift build -c release

# Paket geçici bir klasörde kurulup imzalanır: bu klasör eşitlendiği için Finder/iCloud ekleri (xattr)
# hemen geri gelir ve imzayı geçersiz kılar.
WORK="$(mktemp -d /tmp/nabiz-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Nabız.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/tr.lproj"
cp .build/release/SystemMonitor "$APP/Contents/MacOS/SystemMonitor"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Nabız</string>
  <key>CFBundleDisplayName</key><string>Nabız</string>
  <key>CFBundleIdentifier</key><string>local.systemmonitor</string>
  <key>CFBundleExecutable</key><string>SystemMonitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleLocalizations</key><array><string>tr</string></array>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
  echo "İmza: $SIGN_IDENTITY"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --keepParent "$APP" "$WORK/Nabiz.zip"
    echo "Apple'a onaya gönderiliyor (birkaç dakika sürebilir)…"
    xcrun notarytool submit "$WORK/Nabiz.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/sonuc.json"
    DURUM="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$WORK/sonuc.json")"
    if [[ "$DURUM" != "Accepted" ]]; then
      KIMLIK="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$WORK/sonuc.json")"
      echo "Hata: Apple onayı reddetti (durum: ${DURUM:-bilinmiyor}). Ayrıntı: xcrun notarytool log $KIMLIK --keychain-profile $NOTARY_PROFILE" >&2
      exit 1
    fi
    xcrun stapler staple "$APP"
    spctl --assess --type execute "$APP"
    mkdir -p dist
    rm -f dist/Nabiz-macOS.zip
    ditto -c -k --keepParent "$APP" dist/Nabiz-macOS.zip
    echo "Onay: Apple onaylı. Dağıtım dosyası: $(pwd)/dist/Nabiz-macOS.zip"
  fi
fi

rm -rf "Nabız.app"
ditto "$APP" "Nabız.app"
echo "Built $(pwd)/Nabız.app"

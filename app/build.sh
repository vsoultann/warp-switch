#!/data/data/com.termux/files/usr/bin/bash
# Builds WarpSwitch.apk with aapt2/javac/d8/apksigner (works inside Termux).
# Signing: WS_KS=<keystore> WS_KS_PASS=<pass> WS_ALIAS=<alias>, else the debug keystore.
set -e
cd "$(dirname "$0")"
AJ=${ANDROID_JAR:-$HOME/android-sdk/platforms/android-36/android.jar}
KS=${WS_KS:-$HOME/.android/debug.keystore}; PASS=${WS_KS_PASS:-android}; ALIAS=${WS_ALIAS:-androiddebugkey}
rm -rf out && mkdir -p out/classes out/dex
aapt2 compile --dir res -o out/res.zip
aapt2 link -I "$AJ" --manifest AndroidManifest.xml -o out/unsigned.apk --java out/gen out/res.zip
javac --release 17 -cp "$AJ" -d out/classes $(find src out/gen -name '*.java') -Xlint:-options
d8 --release --min-api 29 --lib "$AJ" --output out/dex $(find out/classes -name '*.class')
(cd out/dex && jar uf0 ../unsigned.apk classes.dex)
apksigner sign --ks "$KS" --ks-pass "pass:$PASS" --key-pass "pass:$PASS" --ks-key-alias "$ALIAS" \
  --out WarpSwitch.apk out/unsigned.apk
echo "built $PWD/WarpSwitch.apk"

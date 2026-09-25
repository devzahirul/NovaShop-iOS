#!/usr/bin/env bash
# Cold-launch benchmark using the app's own os_signpost / Logger timeline (App.init → first frame
# → home content). Complements Instruments' App Launch template and XCTApplicationLaunchMetric.
set -euo pipefail
SIM="${1:?simulator udid}"
BUNDLE=com.novashop.app
xcrun simctl boot "$SIM" 2>/dev/null || true
xcodebuild -project NovaShop.xcodeproj -scheme NovaShop -configuration Release \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build/bench build -quiet
xcrun simctl install "$SIM" build/bench/Build/Products/Release-iphonesimulator/NovaShop.app
for _ in 1 2 3 4 5 6; do
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$SIM" "$BUNDLE" -no-latency >/dev/null
  sleep 4
done
xcrun simctl spawn "$SIM" log show --last 2m --info --style compact \
  --predicate "subsystem == \"$BUNDLE\" AND category == \"performance\"" | grep -oE "(First frame|Home content ready) after [0-9]+ ms"

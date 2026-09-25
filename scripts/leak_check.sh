#!/usr/bin/env bash
# Device leak check over the full purchase flow.
#
# On a physical device the Leaks instrument can't attach to a running app (its memory scanner must
# hook libmalloc at launch), so Instruments LAUNCHES the app and a UI test (LeakFlowTests) DRIVES it.
# Exit code is non-zero if any leak is reported.
#
#   DEVICE_ID=<xctrace device id> TEAM=<team id> make leak-check
set -euo pipefail
DEVICE_ID="${DEVICE_ID:?set DEVICE_ID (xcrun xctrace list devices)}"
TEAM="${TEAM:?set TEAM (your Apple development team id)}"
OUT=build/traces/leaks-flow-$(date +%Y%m%d-%H%M%S).trace
mkdir -p build/traces

xcodebuild build-for-testing -project NovaShop.xcodeproj -scheme NovaShop -destination "id=$DEVICE_ID" \
  -derivedDataPath DerivedData -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -quiet

xcrun xctrace record --instrument Leaks --device "$DEVICE_ID" --time-limit 90s --output "$OUT" \
  --launch -- com.novashop.app -ui-testing -signed-in > build/traces/xctrace.log 2>&1 &
TRACE_PID=$!
sleep 12  # let Instruments launch the app

xcodebuild test-without-building -project NovaShop.xcodeproj -scheme NovaShop -destination "id=$DEVICE_ID" \
  -derivedDataPath DerivedData -only-testing:NovaShopUITests/LeakFlowTests/testDrivePurchaseFlowInRunningApp -quiet
wait "$TRACE_PID" || true

LEAKS=$(xcrun xctrace export --input "$OUT" --xpath '//track[@name="Leaks"]/details/detail[@name="Leaks"]' | grep -c "<row" || true)
echo "Leaked allocations: $LEAKS  (trace: $OUT)"
[ "$LEAKS" -eq 0 ]

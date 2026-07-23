#!/bin/zsh
# The SKIE-route packaging receipt, end to end:
#   1. assemble the shipped kernel's XCFramework (all Apple slices), and
#   2. replay the committed kotlin-corpus fixtures across the boundary through
#      the DuetReceipt consumer framework (kernel + the lamp receipt feature).
# Not part of the default test lane (Kotlin/Native compilation is the cost);
# run on demand and before releases.
set -euo pipefail
cd "$(dirname "$0")/.."

./gradlew :kernel:assembleDuetKernelDebugXCFramework \
          :consumer-receipt:assembleDuetReceiptDebugXCFramework --console=plain
(cd consumer-receipt/swift-consumer && swift test)
echo "xcframework-receipt: PASS"

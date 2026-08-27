#!/bin/zsh
# Runs the unit tests. With a full Xcode install this is just `swift test`.
# With Command Line Tools alone, SwiftPM does not find Testing.framework
# (it lives under the CLT's own Frameworks directory and its Foundation
# cross-import overlay is an empty stub there), so those paths are supplied.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" "$@"
fi
exec swift test "$@"

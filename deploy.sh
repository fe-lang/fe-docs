#!/usr/bin/env bash
# Deploy a new version of Fe docs to the doc site.
#
# Usage: ./deploy.sh <docs-json-path> <bundle-dir>
#
# The version is read from compiler_version in docs.json.
# The bundle-dir should contain: fe-web.js, fe-highlight.css, styles.css

set -euo pipefail

DOCS_JSON="${1:?Usage: deploy.sh <docs-json-path> <bundle-dir>}"
BUNDLE_DIR="${2:?Usage: deploy.sh <docs-json-path> <bundle-dir>}"

if [ ! -f "$DOCS_JSON" ]; then
  echo "Error: $DOCS_JSON not found" >&2
  exit 1
fi

# Read version from the docs.json envelope
VERSION=$(python3 -c "
import json, sys
with open('$DOCS_JSON') as f:
    d = json.load(f)
v = d.get('compiler_version')
if not v:
    print('Error: docs.json missing compiler_version', file=sys.stderr)
    sys.exit(1)
print(v)
")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Deploying Fe $VERSION docs..."

# 1. Update shared assets (always latest)
for f in fe-web.js fe-highlight.css styles.css; do
  if [ -f "$BUNDLE_DIR/$f" ]; then
    cp "$BUNDLE_DIR/$f" "./$f"
    echo "  Updated $f"
  else
    echo "  Warning: $BUNDLE_DIR/$f not found, skipping"
  fi
done

# 2. Create version directory with docs.json
mkdir -p "$VERSION"
cp "$DOCS_JSON" "$VERSION/docs.json"
echo "  Created $VERSION/docs.json"

# 3. Generate per-version index.html from template
sed "s|{{VERSION}}|$VERSION|g" _template/index.html > "$VERSION/index.html"
echo "  Created $VERSION/index.html"

# 4. Update versions.json
python3 - "$VERSION" << 'PYEOF'
import json, sys

version = sys.argv[1]
try:
    with open("versions.json") as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {"latest": "", "versions": []}

if version not in data["versions"]:
    data["versions"].insert(0, version)

data["versions"].sort(key=lambda v: [int(x) for x in v.split(".")], reverse=True)
data["latest"] = data["versions"][0]

with open("versions.json", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"  Updated versions.json (latest: {data['latest']}, {len(data['versions'])} versions)")
PYEOF

echo "Done. Review changes, then commit and push."

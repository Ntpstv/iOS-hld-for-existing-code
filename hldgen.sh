#!/usr/bin/env bash
# Usage: bash Tools/hldgen.sh <ModuleDir> [-o output.json]
# Example: bash Tools/hldgen.sh Calendar
#   → writes Tools/HLDFigmaPlugin/bundle.json, next to the plugin that reads it
#
# Auto-discovers: scene dirs, the repo root to scan for APIs, the stub mapping, and the flow file.
# Run from repo root.

set -euo pipefail

MODULE_DIR="${1:?Usage: $0 <ModuleDir> [-o output.json]}"
shift
OUTPUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUTPUT="${2:?-o needs a path}"; shift 2 ;;
    *)  echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Module name = last path component without trailing slash
MODULE_NAME="$(basename "$MODULE_DIR")"

# Package path is resolved from this script's own location, so the checkout can be named
# anything (Tools/, MyApp/HLDGen/, …) without the caller passing a path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default output sits beside the Figma plugin's manifest: the one folder a user already has open
# when pasting it in, and unlike /tmp it survives a restart.
[ -z "$OUTPUT" ] && OUTPUT="$SCRIPT_DIR/HLDFigmaPlugin/bundle.json"
PKG="$SCRIPT_DIR/HLDGen"

# ── Build tool (fast no-op if already built) ─────────────────────────────────
swift build --package-path "$PKG" 2>&1 | tail -2

# ── Auto-discover scene dirs ──────────────────────────────────────────────────
# Screens usually sit under a container folder whose name is some spelling of Scene(s)/Screen(s).
# Its absence is normal (many MVC / MVVM / SwiftUI modules have none), so fall back to the module.
SCENE_ROOT="$(find "$MODULE_DIR" -maxdepth 2 -type d \( -iname "scene" -o -iname "scenes" \
  -o -iname "screen" -o -iname "screens" \) 2>/dev/null | head -1 || true)"
if [ -z "$SCENE_ROOT" ]; then
  SCENE_ROOT="$MODULE_DIR"
  echo "No Scenes/ folder found — scanning $SCENE_ROOT directly"
fi

# One scene = one directory holding a *ViewController.swift. Nested folders each count separately:
# a container like Scenes/Home holds its own VC *and* a subfolder per sibling screen, and collapsing
# those into one entry is what turns ten screens into a single unreadable card.
# Read line-by-line (never `$( )` word-splitting) so directory names containing spaces survive.
SCENE_DIRS=()
while IFS= read -r d; do
  SCENE_DIRS+=("$d")
done < <(find "$SCENE_ROOT" -name "*ViewController.swift" -exec dirname {} \; | sort -u)

# SwiftUI / MVVM modules have no ViewControllers — fall back to View / ViewModel files
if [ ${#SCENE_DIRS[@]} -eq 0 ]; then
  while IFS= read -r d; do
    SCENE_DIRS+=("$d")
  done < <(find "$SCENE_ROOT" \( -name "*ViewModel.swift" -o -name "*View.swift" \) -exec dirname {} \; | sort -u)
fi

if [ ${#SCENE_DIRS[@]} -eq 0 ]; then
  # Last resort: pass the module dir itself
  SCENE_DIRS=("$MODULE_DIR")
  echo "No ViewController/ViewModel found — passing $MODULE_DIR as scene"
fi

echo "Found ${#SCENE_DIRS[@]} scene(s):"
for s in "${SCENE_DIRS[@]}"; do echo "  $s"; done

# ── API scan roots ───────────────────────────────────────────────────────────
# A screen calls a Service, which names an API class, which calls a Router case that finally
# holds the path. Those three layers routinely live in three different frameworks, so scanning
# only the module's own API folder resolves nothing. Hand the analyzer the whole repo.
API_FLAGS=()
SCAN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
API_FLAGS+=(--services-dir "$SCAN_ROOT")
echo "API scan root: $SCAN_ROOT"

# ── Stub server mapping, for real response examples ──────────────────────────
STUB_FLAGS=()
# A stub mapping is any YAML pairing a url with the file returned for it. Look for one by the
# shape of its contents rather than by a project's chosen filename.
STUB_FILE=""
while IFS= read -r candidate; do
  if grep -q "url:" "$candidate" 2>/dev/null && grep -q "file:" "$candidate" 2>/dev/null; then
    STUB_FILE="$candidate"; break
  fi
done < <(find "$SCAN_ROOT" -maxdepth 3 \( -name "*.yaml" -o -name "*.yml" \) \
  -not -path "*/.git/*" -not -path "*/.build/*" 2>/dev/null | head -40)
if [ -n "$STUB_FILE" ]; then
  STUB_FLAGS+=(--stubs "$STUB_FILE")
  echo "Stub map:   $STUB_FILE"
else
  echo "No stub server mapping found (API panels show fields only, no example)"
fi

# ── Auto-discover flow file ───────────────────────────────────────────────────
FLOW_FLAGS=()
FLOW_FILE="$(find "$MODULE_DIR" -maxdepth 3 -type d -iname "flow" -exec find {} -maxdepth 1 -name "*.swift" \; \
  2>/dev/null | head -1 || true)"
if [ -n "$FLOW_FILE" ]; then
  FLOW_FLAGS+=(--flow-file "$FLOW_FILE")
  echo "Flow file:  $FLOW_FILE"
else
  echo "No flow file found (skipping --flow-file)"
fi

# ── Run ───────────────────────────────────────────────────────────────────────
echo ""
echo "Generating → $OUTPUT"
swift run --package-path "$PKG" hldgen \
  "${SCENE_DIRS[@]}" \
  --module "$MODULE_NAME" \
  ${API_FLAGS[@]+"${API_FLAGS[@]}"} \
  ${FLOW_FLAGS[@]+"${FLOW_FLAGS[@]}"} \
  ${STUB_FLAGS[@]+"${STUB_FLAGS[@]}"} \
  -o "$OUTPUT"

echo ""
echo "✓ Done: $OUTPUT"
echo "  Paste into Figma plugin (Plugins → Development → iOS-hld-for-existing-code)"

# ── Keep the host repo clean ─────────────────────────────────────────────────
# Both the generated bundle and this checkout itself (~50MB once .build exists) are
# throwaway, so neither should ever end up in the host repo's history.
GITIGNORE=".gitignore"
IGNORE_ENTRIES=("$(basename "$OUTPUT")")

# The checkout's path relative to the repo root, when it sits inside this repo at all
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
case "$SCRIPT_DIR/" in
  # Leading slash anchors the pattern, so a bare `Tools/` cannot also swallow
  # an unrelated `SomeModule/Tools/` elsewhere in the repo.
  "$REPO_ROOT"/*) IGNORE_ENTRIES+=("/${SCRIPT_DIR#"$REPO_ROOT"/}/") ;;
esac

if [ -n "$REPO_ROOT" ] && [ -f "$GITIGNORE" ]; then
  for entry in "${IGNORE_ENTRIES[@]}"; do
    grep -qxF "$entry" "$GITIGNORE" && continue
    printf '\n# iOS-hld-for-existing-code\n%s\n' "$entry" >> "$GITIGNORE"
    echo "  Added '$entry' to .gitignore"
  done
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"

mkdir -p "$HOOKS_DIR"

cat >"$HOOKS_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

# Block committing generated artifacts (traces/results/third_party/champsim) by mistake.
blocked_regex='^(traces/|results/|third_party/champsim/|bin/|\.ipynb_checkpoints/).*$'

while read -r path; do
  if [[ "$path" =~ $blocked_regex ]]; then
    echo "ERROR: refusing to commit generated/third-party artifact: $path" >&2
    echo "Hint: artifacts live in traces/ and results/ and are intentionally not tracked." >&2
    exit 1
  fi
done < <(git diff --cached --name-only)

exit 0
HOOK

chmod +x "$HOOKS_DIR/pre-commit"

echo "[hooks] Installed pre-commit hook to block committing traces/results/third_party artifacts."

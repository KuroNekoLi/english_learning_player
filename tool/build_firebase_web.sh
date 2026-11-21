#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_file="${ELP_WEB_CONFIG_FILE:-.env.firebase-web}"
if [[ ! -r "$source_file" ]]; then
  printf 'Firebase Web config is missing or unreadable: %s\n' "$source_file" >&2
  exit 1
fi

defines_file="$(mktemp "${TMPDIR:-/tmp}/elp-web-defines.XXXXXX")"
trap 'rm -f "$defines_file"' EXIT

python3 - "$source_file" "$defines_file" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
allowed = {
    "ELP_FIREBASE_PROJECT",
    "ELP_FIREBASE_API_KEY",
    "ELP_FIREBASE_BUCKET",
    "ELP_FIREBASE_WEB_APP_ID",
    "ELP_FIREBASE_MESSAGING_SENDER_ID",
    "ELP_FIREBASE_AUTH_DOMAIN",
    "ELP_FIREBASE_PROGRESS_REGION",
}
values = {}
for raw_line in source.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if "=" not in line:
        raise SystemExit("Invalid config line; expected KEY=VALUE")
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if key not in allowed:
        continue
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    values[key] = value

required = {
    "ELP_FIREBASE_PROJECT",
    "ELP_FIREBASE_API_KEY",
    "ELP_FIREBASE_WEB_APP_ID",
    "ELP_FIREBASE_MESSAGING_SENDER_ID",
}
missing = sorted(key for key in required if not values.get(key))
if missing:
    raise SystemExit("Firebase Web config is missing: " + ", ".join(missing))

target.write_text(json.dumps(values, ensure_ascii=False), encoding="utf-8")
PY

flutter build web --release --no-pub --dart-define-from-file="$defines_file"

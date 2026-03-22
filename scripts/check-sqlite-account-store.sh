#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT_DIR="${APP_SUPPORT_DIR:-$HOME/Library/Application Support/com.novainfra.cx-switch}"
DB_PATH="${DB_PATH:-$APP_SUPPORT_DIR/cx-switch.db}"
AUTH_PATH="${AUTH_PATH:-$HOME/.codex/auth.json}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "[1/5] Build smoke check"
(
  cd "$ROOT"
  DEVELOPER_DIR="$DEVELOPER_DIR" swift build >/dev/null
  DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -project "$ROOT/CXSwitch.xcodeproj" \
    -target CXSwitch \
    -configuration Debug \
    build >/dev/null
)
echo "  build ok"

echo "[2/5] SQLite file"
if [[ -f "$DB_PATH" ]]; then
  echo "  db: $DB_PATH"
  sqlite3 "$DB_PATH" ".tables"
  echo "--- pragmas ---"
  sqlite3 "$DB_PATH" "PRAGMA journal_mode; PRAGMA foreign_keys;"
  echo "--- account rows ---"
  sqlite3 "$DB_PATH" "SELECT id, email, is_current FROM accounts ORDER BY added_at;"
  echo "--- counts ---"
  sqlite3 "$DB_PATH" "SELECT 'credentials', COUNT(*) FROM credentials;"
  sqlite3 "$DB_PATH" "SELECT 'usage_snapshots', COUNT(*) FROM usage_snapshots;"
else
  echo "  db missing: $DB_PATH"
fi

echo "[3/5] auth.json projection"
if [[ -f "$AUTH_PATH" ]]; then
  echo "  auth: $AUTH_PATH"
  plutil -p "$AUTH_PATH" 2>/dev/null || cat "$AUTH_PATH"
else
  echo "  auth.json missing: $AUTH_PATH"
fi

echo "[4/5] migrated registry marker"
if [[ -f "$APP_SUPPORT_DIR/registry.json.migrated" ]]; then
  echo "  found: $APP_SUPPORT_DIR/registry.json.migrated"
else
  echo "  registry.json.migrated not found"
fi

echo "[5/5] manual follow-up"
echo "  - Launch app and verify current account loads."
echo "  - Delete auth.json, relaunch, and verify it is restored from DB."
echo "  - Rapidly switch accounts and confirm only one is_current row remains."

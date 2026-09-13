#!/usr/bin/env bash
# Guard against committing credentials in n8n workflow exports.
#
# n8n references credentials by id, which is safe to commit:
#     "credentials": { "warehanceApi": { "id": "7", "name": "Warehance" } }
#
# What is NOT safe is a key pasted directly into a node parameter — a header value, a
# query string, an HTTP node's auth field. That is what this catches.
#
# Usage:  scripts/check-secrets.sh [path ...]     (defaults to workflows/)
# Exits non-zero if anything suspicious is found.

set -uo pipefail

targets=("${@:-workflows}")
found=0

# Vendor key formats. Kept specific rather than broad: a noisy guard gets bypassed,
# which is worse than no guard.
patterns=(
  'xox[baprs]-[A-Za-z0-9-]{10,}'          # Slack
  'SG\.[A-Za-z0-9_-]{16,}'                # SendGrid
  'sk_(live|test)_[A-Za-z0-9]{16,}'       # Stripe-style secret key
  'pk_(live|test)_[A-Za-z0-9]{16,}'       # Stripe-style publishable key
  'AC[0-9a-fA-F]{32}'                     # Twilio account SID
  'SK[0-9a-fA-F]{32}'                     # Twilio API key SID
  'pk_[A-Za-z0-9]{20,}'                   # Klaviyo private key
  'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'  # JWT (Supabase service keys included)
  'AKIA[0-9A-Z]{16}'                      # AWS access key id
  'ghp_[A-Za-z0-9]{20,}'                  # GitHub PAT
)

# Literal assignments to auth-ish JSON keys. Allows n8n expressions ({{...}}, ={{...}})
# and empty strings, which are the legitimate forms.
assignment='"(apiKey|api_key|accessToken|access_token|password|secret|clientSecret|privateKey|authorization)"[[:space:]]*:[[:space:]]*"[^"{=][^"]{7,}"'

scan() {
  local label="$1" pattern="$2"
  local hits
  hits=$(grep -rInE --include='*.json' --include='*.yml' --include='*.yaml' \
           -- "$pattern" "${targets[@]}" 2>/dev/null) || return 0
  [ -z "$hits" ] && return 0
  echo "FOUND — $label"
  echo "$hits" | sed 's/^/    /'
  echo
  found=1
}

for p in "${patterns[@]}"; do
  scan "vendor key pattern" "$p"
done
scan "literal value assigned to an auth field" "$assignment"

if [ "$found" -ne 0 ]; then
  cat <<'EOF'
Refusing to pass: possible credentials above.

Fix by moving the value into the n8n credential store and referencing it from the node,
so the export carries only a credential id.

If a match is a false positive, narrow the pattern in this script rather than skipping
the check — a guard that gets routinely bypassed stops being a guard.

If a real key was already committed, rotate it. Removing it from git history does not
un-leak it.
EOF
  exit 1
fi

echo "check-secrets: clean (${targets[*]})"

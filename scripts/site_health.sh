#!/usr/bin/env bash
# Smoke-test a single URL: DNS resolves, TLS handshake, HTTP 2xx/3xx, page title.
#
# Usage:
#   scripts/site_health.sh <url> <label> <required>
#     required=true  -> non-2xx/3xx or TLS failure fails the job
#     required=false -> failures are reported as warnings, exit 0
#
# No secrets. Read-only.

set -uo pipefail

URL="${1:?url required}"
LABEL="${2:?label required}"
REQUIRED="${3:-true}"

# Strip scheme to get the host for dig.
host="${URL#https://}"
host="${host#http://}"
host="${host%%/*}"

echo "── Probing $LABEL ($URL)"
echo "Host: $host  Required: $REQUIRED"

WARNINGS=0

fail() {
  local msg="$1"
  if [ "$REQUIRED" = "true" ]; then
    echo "::error::[$LABEL] $msg"
    exit 1
  else
    echo "::warning::[$LABEL] $msg (non-required target)"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# 1) DNS resolution.
echo
echo "── 1) DNS"
if ! command -v dig >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends dnsutils >/dev/null
fi
dns_a=$(dig +short +time=5 +tries=2 "$host" A    | tr '\n' ' ')
dns_aaaa=$(dig +short +time=5 +tries=2 "$host" AAAA | tr '\n' ' ')
dns_cname=$(dig +short +time=5 +tries=2 "$host" CNAME | tr '\n' ' ')
echo "A:     ${dns_a:-<none>}"
echo "AAAA:  ${dns_aaaa:-<none>}"
echo "CNAME: ${dns_cname:-<none>}"
if [ -z "${dns_a// /}" ] && [ -z "${dns_aaaa// /}" ] && [ -z "${dns_cname// /}" ]; then
  fail "DNS resolution returned no records"
fi

# 2) TLS handshake + certificate inspection.
echo
echo "── 2) TLS"
tls_out=$(echo \
  | openssl s_client -servername "$host" -connect "$host:443" -brief 2>&1 \
  | head -40 || true)
echo "$tls_out"
if echo "$tls_out" | grep -qiE "verification error|alert|handshake failure"; then
  fail "TLS handshake / verification failed"
fi

# 3) HTTP status + title.
echo
echo "── 3) HTTP"
tmp_body=$(mktemp)
# -L follow redirects, 15s timeout. Do NOT use -k: TLS errors should surface.
http_code=$(curl -sS -L --max-time 15 \
  -A "LGLenz-SiteHealth/1.0 (+https://github.com/${GITHUB_REPOSITORY:-LGLenz/LGLenz.github.io})" \
  -o "$tmp_body" -w "%{http_code}" "$URL" 2>/dev/null)
curl_rc=$?
# Sanitise: if curl printed nothing or non-numeric, force 000.
if ! [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
  http_code="000"
fi
echo "HTTP status: $http_code (curl exit $curl_rc)"

if [ "$http_code" = "000" ]; then
  fail "Could not connect to $URL (curl exit $curl_rc)"
elif [ "$http_code" -lt 200 ] || [ "$http_code" -ge 400 ]; then
  fail "HTTP $http_code"
fi

# 4) Page title sanity.
echo
echo "── 4) Title"
title=$(tr '\n' ' ' < "$tmp_body" \
  | grep -oiE '<title[^>]*>[^<]*</title>' | head -1 \
  | sed -E 's#<title[^>]*>##i; s#</title>##i' \
  | tr -s '[:space:]' ' ' \
  | sed -E 's/^ +//; s/ +$//')
echo "Title: ${title:-<none>}"
if [ -z "$title" ]; then
  fail "No <title> found in response body"
elif ! echo "$title" | grep -qiE "elias lenz|lglenz"; then
  fail "Title '$title' does not mention 'Elias Lenz' or 'LGLenz'"
fi

rm -f "$tmp_body"
echo
if [ "$WARNINGS" -eq 0 ]; then
  echo "OK: $LABEL ($URL) — DNS, TLS, HTTP $http_code, title looks correct."
else
  echo "WARN: $LABEL ($URL) finished with $WARNINGS warning(s) — see annotations."
fi

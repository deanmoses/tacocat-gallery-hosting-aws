#!/bin/bash
# Integration tests for the hosting infrastructure
# Verifies expected behavior of CloudFront distribution

DOMAIN="${1:-staging-pix.tacocat.com}"
FAILED=0
CURL_OPTS=(--max-time 10 --silent)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "Running integration tests against https://$DOMAIN"
echo "================================================="

# Test 1: robots.txt keeps the site crawlable, which is what makes the SPA's
# noindex work. Blocking here reads like tighter privacy but does the opposite.
echo -n "Test: robots.txt allows crawling... "
STATUS=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://$DOMAIN/robots.txt")
ROBOTS=$(curl "${CURL_OPTS[@]}" "https://$DOMAIN/robots.txt")
# Group-aware: the AI-training group ends in a legitimate "Disallow: /", so
# only a block on the wildcard group is a failure.
STAR_BLOCKED=$(echo "$ROBOTS" | tr '[:upper:]' '[:lower:]' | awk '
    BEGIN { star = 0; inrules = 0; hit = 0 }
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    /^[ \t]*user-agent:/ {
        if (inrules) { star = 0; inrules = 0 }
        val = $0
        sub(/^[ \t]*user-agent:[ \t]*/, "", val)
        gsub(/[ \t]/, "", val)
        if (val == "*") star = 1
        next
    }
    {
        inrules = 1
        if (star && $0 ~ /^[ \t]*disallow:[ \t]*\/[ \t]*$/) hit = 1
    }
    END { print hit }
')
if [ "$STATUS" != "200" ]; then
    echo -e "${RED}FAIL (expected 200, got $STATUS)${NC}"
    FAILED=1
elif [ "$STAR_BLOCKED" = "1" ]; then
    echo -e "${RED}FAIL (wildcard group is disallowed; that hides the noindex)${NC}"
    FAILED=1
elif ! echo "$ROBOTS" | grep -qE '^[[:space:]]*Allow:[[:space:]]*/'; then
    echo -e "${RED}FAIL (no 'Allow: /' rule)${NC}"
    FAILED=1
elif ! echo "$ROBOTS" | grep -qiE '^[[:space:]]*User-agent:[[:space:]]*GPTBot[[:space:]]*$'; then
    echo -e "${RED}FAIL (AI-training crawlers no longer listed)${NC}"
    FAILED=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# Test 2: Root returns 200
echo -n "Test: Root path returns 200... "
STATUS=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://$DOMAIN/")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (got $STATUS)${NC}"
    FAILED=1
fi

# Test 3: SPA routing works (a deep link is served index.html), including one
# that looks like a file, which is what every media page's URL looks like
echo -n "Test: SPA routing returns 200 for deep links... "
STATUS=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://$DOMAIN/2024/01-01/nonexistent")
MEDIA_STATUS=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://$DOMAIN/2024/01-01/nonexistent.jpg")
if [ "$STATUS" = "200" ] && [ "$MEDIA_STATUS" = "200" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (got $STATUS and $MEDIA_STATUS)${NC}"
    FAILED=1
fi

# Test 3b: a missing file the site would have deployed is an error, not the app.
# The routing function serves index.html for app routes only; if this returns
# 200, the allowlist has stopped matching what the build deploys.
echo -n "Test: a missing static file is not served as index.html... "
STATUS=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "https://$DOMAIN/images/nonexistent.png")
if [ "$STATUS" = "403" ] || [ "$STATUS" = "404" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (expected 403/404, got $STATUS)${NC}"
    FAILED=1
fi

# Test 4: HTTPS is enforced (HTTP redirects to HTTPS)
echo -n "Test: HTTP redirects to HTTPS... "
# Don't follow redirects, just check we get a 301/302 redirect
STATUS=$(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "http://$DOMAIN/" 2>/dev/null || echo "000")
if [ "$STATUS" = "301" ] || [ "$STATUS" = "302" ]; then
    echo -e "${GREEN}PASS${NC}"
elif [ "$STATUS" = "000" ]; then
    echo -e "${YELLOW}SKIP${NC} (HTTP connection failed)"
else
    echo -e "${RED}FAIL (expected 301/302, got $STATUS)${NC}"
    FAILED=1
fi

# Test 5: Immutable assets have correct cache headers
echo -n "Test: Immutable assets have 1-year cache headers... "
# Fetch homepage and extract an immutable asset URL
HOMEPAGE=$(curl "${CURL_OPTS[@]}" "https://$DOMAIN/")
IMMUTABLE_PATH=$(echo "$HOMEPAGE" | grep -oE '/_app/immutable/[^"]+' | head -1)
if [ -z "$IMMUTABLE_PATH" ]; then
    echo -e "${RED}FAIL (homepage references no /_app/immutable/ assets)${NC}"
    FAILED=1
else
    CACHE_HEADER=$(curl "${CURL_OPTS[@]}" -I "https://$DOMAIN$IMMUTABLE_PATH" | grep -i "cache-control" | tr -d '\r')
    if echo "$CACHE_HEADER" | grep -q "max-age=31536000" && echo "$CACHE_HEADER" | grep -q "immutable"; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL (got: $CACHE_HEADER)${NC}"
        FAILED=1
    fi
fi

# Test 6: opt-out headers. They live on the CloudFront policy, not in the SPA
# build, so nothing in the sveltekit repo would catch their loss.
echo -n "Test: crawler opt-out headers present... "
HEADERS=$(curl "${CURL_OPTS[@]}" -I "https://$DOMAIN/" | tr -d '\r')
MISSING=""
echo "$HEADERS" | grep -qiE '^x-robots-tag:.*noindex' || MISSING="$MISSING x-robots-tag/noindex"
echo "$HEADERS" | grep -qiE '^x-robots-tag:.*noai' || MISSING="$MISSING x-robots-tag/noai"
echo "$HEADERS" | grep -qiE '^tdm-reservation:[[:space:]]*1' || MISSING="$MISSING tdm-reservation"
if [ -z "$MISSING" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (missing:$MISSING)${NC}"
    FAILED=1
fi

# Test 7: security headers. The same assertions run over every response rather
# than diffing one field, because HSTS is written into two policies and a flag
# flipped in only one of them -- includeSubDomains, or a stray preload -- is as
# real a drift as a mismatched max-age.
SEC_MISSING=""
assert_sec() { # label, headers, scope(full|subresource)
    _l="$1"; _h="$2"; _s="$3"
    echo "$_h" | grep -qiE '^strict-transport-security:.*max-age=[0-9]+' || SEC_MISSING="$SEC_MISSING $_l/hsts"
    echo "$_h" | grep -qiE '^strict-transport-security:.*includesubdomains' || SEC_MISSING="$SEC_MISSING $_l/includeSubDomains"
    # preload cannot be withdrawn on our own schedule, so it is asserted absent
    # on every response, not just the one that happened to be checked first.
    echo "$_h" | grep -qiE '^strict-transport-security:.*preload' && SEC_MISSING="$SEC_MISSING $_l/UNEXPECTED-preload"
    echo "$_h" | grep -qiE '^x-content-type-options:[[:space:]]*nosniff' || SEC_MISSING="$SEC_MISSING $_l/nosniff"
    if [ "$_s" = "full" ]; then
        echo "$_h" | grep -qiE '^referrer-policy:' || SEC_MISSING="$SEC_MISSING $_l/referrer-policy"
        echo "$_h" | grep -qiE '^x-frame-options:[[:space:]]*DENY' || SEC_MISSING="$SEC_MISSING $_l/x-frame-options"
        echo "$_h" | grep -qiE '^permissions-policy:' || SEC_MISSING="$SEC_MISSING $_l/permissions-policy"
    fi
}
maxage_of() { echo "$1" | grep -iE '^strict-transport-security:' | grep -oE 'max-age=[0-9]+' | head -1; }

echo -n "Test: security headers present and consistent... "
assert_sec html "$HEADERS" full
if [ -z "$IMMUTABLE_PATH" ]; then
    # Test 5 already failed loudly in this case; say so rather than passing a
    # check that never ran.
    SEC_MISSING="$SEC_MISSING asset/no-path-to-test"
else
    ASSET_HEADERS=$(curl "${CURL_OPTS[@]}" -I "https://$DOMAIN$IMMUTABLE_PATH" | tr -d '\r')
    assert_sec asset "$ASSET_HEADERS" subresource
    if [ "$(maxage_of "$ASSET_HEADERS")" != "$(maxage_of "$HEADERS")" ]; then
        SEC_MISSING="$SEC_MISSING hsts-drift($(maxage_of "$HEADERS")-vs-$(maxage_of "$ASSET_HEADERS"))"
    fi
fi
ROBOTS_HEADERS=$(curl "${CURL_OPTS[@]}" -I "https://$DOMAIN/robots.txt" | tr -d '\r')
assert_sec robots "$ROBOTS_HEADERS" subresource
if [ -z "$SEC_MISSING" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (issues:$SEC_MISSING)${NC}"
    FAILED=1
fi

# Test 8: every SPA deep link is served as index.html by the routing function,
# so this is most real page views.
echo -n "Test: headers reach SPA deep links... "
SEC_MISSING=""
DEEP_HEADERS=$(curl "${CURL_OPTS[@]}" -I "https://$DOMAIN/2024/01-01/nonexistent" | tr -d '\r')
assert_sec deeplink "$DEEP_HEADERS" full
echo "$DEEP_HEADERS" | grep -qiE '^x-robots-tag:.*noindex' || SEC_MISSING="$SEC_MISSING deeplink/x-robots-tag"
echo "$DEEP_HEADERS" | grep -qiE '^tdm-reservation:[[:space:]]*1' || SEC_MISSING="$SEC_MISSING deeplink/tdm-reservation"
if [ -z "$SEC_MISSING" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (missing:$SEC_MISSING)${NC}"
    FAILED=1
fi

# Test 9: the API is served on this domain. The root album is JSON, from the
# API rather than the app, and it went through CloudFront's cache logic.
echo -n "Test: /api/album is the API... "
API_HEADERS=$(curl "${CURL_OPTS[@]}" -D - -o /dev/null "https://$DOMAIN/api/album" | tr -d '\r')
API_STATUS=$(echo "$API_HEADERS" | grep -oE '^HTTP/[0-9.]+ [0-9]+' | tail -1 | awk '{print $2}')
if [ "$API_STATUS" != "200" ]; then
    echo -e "${RED}FAIL (got $API_STATUS)${NC}"
    FAILED=1
elif ! echo "$API_HEADERS" | grep -qiE '^content-type:.*application/json'; then
    echo -e "${RED}FAIL (not JSON)${NC}"
    FAILED=1
elif ! echo "$API_HEADERS" | grep -qiE '^x-cache:'; then
    echo -e "${RED}FAIL (no x-cache header)${NC}"
    FAILED=1
else
    echo -e "${GREEN}PASS${NC}"
fi

# Test 9b: where albums are cached, the cache serves them. The root album is
# the one every visit asks for, so it is versioned and cached within a few
# requests of any deploy; three tries cover the store's propagation. Where the
# environment serves albums uncached the API says no-store, and this is moot.
if echo "$API_HEADERS" | grep -qiE '^cache-control:.*public'; then
    echo -n "Test: the root album is served from the edge cache... "
    HIT=""
    for _ in 1 2 3; do
        if curl "${CURL_OPTS[@]}" -D - -o /dev/null "https://$DOMAIN/api/album" | grep -qiE '^x-cache:.*hit'; then
            HIT=1
            break
        fi
        sleep 3
    done
    if [ -n "$HIT" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL (no hit in three tries)${NC}"
        FAILED=1
    fi
fi

# Test 10: an unknown API path is the API's error, not the app. Without the
# routing function's allowlist doing its job, or with a distribution-wide
# error mapping, this would come back as index.html with a 200.
echo -n "Test: an unknown API path is answered by the API... "
API_404=$(curl "${CURL_OPTS[@]}" -D - -o /dev/null "https://$DOMAIN/api/no-such-endpoint" | tr -d '\r')
API_404_STATUS=$(echo "$API_404" | grep -oE '^HTTP/[0-9.]+ [0-9]+' | tail -1 | awk '{print $2}')
if { [ "$API_404_STATUS" = "403" ] || [ "$API_404_STATUS" = "404" ]; } && ! echo "$API_404" | grep -qiE '^content-type:.*text/html'; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (expected the API's 403/404, got '$API_404_STATUS')${NC}"
    FAILED=1
fi

echo "================================================="
if [ "$FAILED" = "1" ]; then
    echo -e "${RED}Some tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests PASSED${NC}"
    exit 0
fi

#!/bin/bash
# Integration tests for the hosting infrastructure
# Verifies expected behavior of CloudFront distribution

DOMAIN="${1:-staging-pix.tacocat.com}"
FAILED=0
CURL_OPTS="--max-time 10 --silent"

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
STATUS=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "https://$DOMAIN/robots.txt")
ROBOTS=$(curl $CURL_OPTS "https://$DOMAIN/robots.txt")
# Group-aware: the AI-training group ends in a legitimate "Disallow: /", so
# only a block on the wildcard group is a failure.
STAR_BLOCKED=$(echo "$ROBOTS" | tr 'A-Z' 'a-z' | awk '
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
STATUS=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "https://$DOMAIN/")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (got $STATUS)${NC}"
    FAILED=1
fi

# Test 3: SPA routing works (unknown path returns 200 with index.html)
echo -n "Test: SPA routing returns 200 for unknown paths... "
STATUS=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "https://$DOMAIN/2024/01-01/nonexistent")
if [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (got $STATUS)${NC}"
    FAILED=1
fi

# Test 4: HTTPS is enforced (HTTP redirects to HTTPS)
echo -n "Test: HTTP redirects to HTTPS... "
# Don't follow redirects, just check we get a 301/302 redirect
STATUS=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "http://$DOMAIN/" 2>/dev/null || echo "000")
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
HOMEPAGE=$(curl $CURL_OPTS "https://$DOMAIN/")
IMMUTABLE_PATH=$(echo "$HOMEPAGE" | grep -oE '/_app/immutable/[^"]+' | head -1)
if [ -z "$IMMUTABLE_PATH" ]; then
    echo -e "${RED}FAIL (homepage references no /_app/immutable/ assets)${NC}"
    FAILED=1
else
    CACHE_HEADER=$(curl $CURL_OPTS -I "https://$DOMAIN$IMMUTABLE_PATH" | grep -i "cache-control" | tr -d '\r')
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
HEADERS=$(curl $CURL_OPTS -I "https://$DOMAIN/" | tr -d '\r')
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

echo "================================================="
if [ "$FAILED" = "1" ]; then
    echo -e "${RED}Some tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests PASSED${NC}"
    exit 0
fi

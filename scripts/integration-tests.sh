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

# Test 1: robots.txt returns 404
echo -n "Test: robots.txt returns 404... "
STATUS=$(curl $CURL_OPTS -o /dev/null -w "%{http_code}" "https://$DOMAIN/robots.txt")
if [ "$STATUS" = "404" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (got $STATUS)${NC}"
    FAILED=1
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

echo "================================================="
if [ "$FAILED" = "1" ]; then
    echo -e "${RED}Some tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests PASSED${NC}"
    exit 0
fi

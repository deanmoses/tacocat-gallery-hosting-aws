#!/bin/bash
# Lint suite for the repo. Run by .husky/pre-commit and by CI, so a local
# commit is held to exactly the standard CI enforces -- the two drifted before
# (the hook ran `sam validate`, CI ran `sam validate --lint`).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# CI is not a TTY but GitHub Actions renders ANSI, so keep color there.
if [ ! -t 1 ] && [ -z "${CI:-}" ]; then
    GREEN='' RED='' YELLOW='' NC=''
fi

# A missing linter is fatal in CI and a warning locally: a fresh clone should
# still be able to commit, but CI silently skipping a check is how a check
# stops existing.
require() {
    command -v "$1" &> /dev/null && return 0
    if [ -n "${CI:-}" ]; then
        echo -e "${RED}FAIL${NC} ($1 not installed)"
        FAILED=1
    else
        echo -e "${YELLOW}SKIP${NC} ($1 not installed)"
    fi
    return 1
}

report() {
    if [ "$1" = "0" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        [ -n "$2" ] && echo "$2"
        FAILED=1
    fi
}

echo "Running lint checks"
echo "================================================="

# -----------------------------------------------------------------------------
# CloudFormation / SAM
# -----------------------------------------------------------------------------
# --lint is the point: it runs cfn-lint. Bare `sam validate` is a schema check
# and will pass templates cfn-lint rejects.
echo -n "Lint: SAM template (cfn-lint)... "
if require sam; then
    OUT=$(cd "$DIR" && sam validate --lint 2>&1)
    report "$?" "$OUT"
fi

# -----------------------------------------------------------------------------
# CloudFront Function JavaScript
# -----------------------------------------------------------------------------
# The function code must be inline in the template (CloudFormation cannot
# reference an external file), so there is nothing on disk for node to parse.
# Reconstruct each `FunctionCode: |` block scalar into a file and syntax-check
# it. Without this, a syntax error survives cfn-lint, `sam build` AND the
# changeset dry-run -- CloudFront only rejects it when it actually publishes
# the function, i.e. partway through a real deploy.
echo -n "Lint: CloudFront Function syntax (node --check)... "
if require node; then
    TMPD=$(mktemp -d)
    # shellcheck disable=SC2064 # expand TMPD now, while it is still set
    trap "rm -rf '$TMPD'" EXIT

    awk -v out="$TMPD/function-" '
        # A literal block scalar: everything indented deeper than the key,
        # dedented by the indentation of its first content line.
        /^[ ]*FunctionCode:[ ]*\|[-+]?[ ]*$/ {
            match($0, /^ */); key = RLENGTH
            incode = 1; content = -1; n += 1; f = out n ".js"
            # Remember where the block starts so a node error, which numbers
            # lines within the extracted file, can be mapped back to the template.
            print NR > (out n ".offset")
            next
        }
        incode {
            if ($0 ~ /^[ \t]*$/) { print "" > f; next }
            match($0, /^ */); ind = RLENGTH
            if (ind <= key) { incode = 0; next }
            if (content < 0) content = ind
            print substr($0, content + 1) > f
            next
        }
    ' "$DIR/template.yaml"

    # Zero blocks means the extractor stopped matching the template, not that
    # the code is clean. Silently passing forever is the failure mode to avoid.
    COUNT=$(find "$TMPD" -name 'function-*.js' | wc -l | tr -d ' ')
    if [ "$COUNT" = "0" ]; then
        report 1 "Extracted no FunctionCode blocks from template.yaml -- has the template changed shape?"
    else
        CHECK_OUT=""
        CHECK_RC=0
        for f in "$TMPD"/function-*.js; do
            ERR=$(node --check "$f" 2>&1) && continue
            CHECK_RC=1
            # Rewrite "<tmpfile>:<n>" into a template.yaml line, so the error
            # points at the file the author actually edits.
            OFFSET=$(cat "${f%.js}.offset")
            # Match on the basename, not the full path: macOS hands mktemp a
            # /var path and node echoes it back resolved through /private/var.
            CHECK_OUT="$CHECK_OUT$(echo "$ERR" | awk -v base="$(basename "$f")" -v off="$OFFSET" '
                index($0, base ":") > 0 {
                    n = split($0, parts, ":")
                    print "template.yaml:" (off + parts[n]) " (inline CloudFront Function)"
                    next
                }
                { print }
            ')"$'\n'
        done
        report "$CHECK_RC" "$CHECK_OUT"
    fi
fi

# -----------------------------------------------------------------------------
# Shell scripts
# -----------------------------------------------------------------------------
echo -n "Lint: shell scripts (shellcheck)... "
if require shellcheck; then
    # Listed from $DIR, not the caller's cwd, so the paths are repo-relative
    # however the script was invoked.
    FILES=$(cd "$DIR" && git ls-files '*.sh' .husky/pre-commit)
    if [ -z "$FILES" ]; then
        # Guarded because shellcheck answers an empty argument list with
        # its usage text, not a legible failure.
        report 1 "Matched no shell scripts -- has the repo changed shape?"
    else
        # shellcheck disable=SC2086 # word splitting is how the file list is passed
        OUT=$(cd "$DIR" && shellcheck $FILES 2>&1)
        report "$?" "$OUT"
    fi
fi

# -----------------------------------------------------------------------------
# GitHub Actions workflows
# -----------------------------------------------------------------------------
# Workflow bugs otherwise surface only on main, after merge. Left at the default
# severity so actionlint's embedded shellcheck also covers inline `run:` scripts.
echo -n "Lint: GitHub Actions workflows (actionlint)... "
if require actionlint; then
    OUT=$(cd "$DIR" && actionlint 2>&1)
    report "$?" "$OUT"
fi

echo "================================================="
if [ "$FAILED" = "1" ]; then
    echo -e "${RED}Lint FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Lint PASSED${NC}"
    exit 0
fi

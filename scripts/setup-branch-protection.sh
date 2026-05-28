#!/usr/bin/env bash
#
# Configure GitHub branch protection for the UniverZAP repo. Idempotent —
# run as many times as you want. Requires:
#   - `gh` CLI logged in OR `GITHUB_TOKEN` env with `repo:admin` scope
#   - You're a repo administrator (rule writes need that scope)
#
# Usage:
#   ./scripts/setup-branch-protection.sh
#
# What it enforces on `main` and `univerzap/phase-0-saneamento`:
#   - Pull requests required (no direct pushes)
#   - At least 1 approving review
#   - Stale reviews dismissed when new commits land
#   - Required status check: "CI pass" (the aggregator job)
#   - No force pushes
#   - No branch deletions
#   - Conversation resolution required before merge

set -euo pipefail

REPO="EuKennedy/UniverZAP"
BRANCHES=("main" "univerzap/phase-0-saneamento")
REQUIRED_CHECKS=("CI pass")

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found. Install from https://cli.github.com" >&2
  exit 1
fi

for branch in "${BRANCHES[@]}"; do
  echo "→ Configuring protection for $REPO branch=$branch"

  # Build the required status check JSON from the array.
  checks_json=$(printf '"%s",' "${REQUIRED_CHECKS[@]}" | sed 's/,$//')

  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO/branches/$branch/protection" \
    --input - <<JSON || echo "warning: protection update failed for $branch (does the branch exist?)"
{
  "required_status_checks": {
    "strict": true,
    "contexts": [$checks_json]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON

  echo "  ✓ branch=$branch configured"
done

echo ""
echo "Done. Run \`gh api repos/$REPO/branches/main/protection | jq\` to verify."

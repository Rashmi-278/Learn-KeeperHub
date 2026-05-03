#!/usr/bin/env bash
# demo.sh - walk through the three Safe guardians live on this org.
#
# Requires ORG_KH_API_KEY in .env (kh_... organization-scoped key).
# Usage: ./demo.sh

set -euo pipefail

if [[ -f .env ]]; then
  set -a; . ./.env; set +a
fi

: "${ORG_KH_API_KEY:?ORG_KH_API_KEY missing - put a kh_ key in .env}"

API="https://app.keeperhub.com/api"
AUTH=(-H "Authorization: Bearer ${ORG_KH_API_KEY}")

# The three guardians deployed in this engagement.
WORKFLOWS=(
  "vzhk455chprgjm1ccqzwa:Threshold Guardian (ChangedThreshold)"
  "oigd9650le4ki8peda9xd:Owner Change Guardian (AddedOwner)"
  "b9z9utqbr1oqt5tx1pwvt:Module Install Guardian (EnabledModule)"
)

echo "== ENS Multisig watched: 0x91c32893216dE3eA0a55ABb9851f581d4503d39b on chain 1"
echo

echo "== /api/workflows (full org listing)"
curl -s "${AUTH[@]}" "${API}/workflows" \
  | jq -r '.[] | "  \(.id)  \(.name)  enabled=\(.enabled)"' || true
echo

for entry in "${WORKFLOWS[@]}"; do
  id="${entry%%:*}"
  label="${entry#*:}"
  echo "== ${label}"
  echo "   id: ${id}"
  curl -s "${AUTH[@]}" "${API}/workflows/${id}" \
    | jq -r '"   enabled: \(.enabled)\n   trigger: \(.nodes[] | select(.type==\"trigger\") | .data.actionType // .data.eventName // \"?\")\n   nodes: \(.nodes | length)  edges: \(.edges | length)"' \
    || echo "   (fetch failed)"
  echo
done

echo "== Manually fire a guardian (will deliver to Discord):"
echo "   curl -X POST ${API}/workflows/<id>/execute \\"
echo "        -H \"Authorization: Bearer \$ORG_KH_API_KEY\""
echo
echo "Done."

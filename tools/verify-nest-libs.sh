#!/usr/bin/env bash
# Verify a vault's NestVault*Logic libraries on Plume's Blockscout explorer.
#
# Why this exists (not a plain `forge verify-contract`):
#   1. Plume's explorer is behind Cloudflare; forge's HTTP client gets blocked on
#      POST. We submit the standard-json via curl to the v2 API instead.
#   2. The libs were compiled at the vault's DEPLOY commit (source has since
#      changed), so we recompile in a worktree pinned to that commit.
#   3. Libraries call each other -> each carries link refs to the other libs'
#      addresses. We must pass ALL 6 --libraries or the bytecode won't match.
#
# Result is a PARTIAL match (body identical, metadata IPFS hash differs) — that
# is expected and means the source is fully proven.
#
# Usage:  tools/verify-nest-libs.sh <VAULT_SYMBOL> [CHAIN_ID]
#   e.g.  tools/verify-nest-libs.sh nCLOA          # defaults to 98866 (Plume)
set -euo pipefail

VAULT="${1:?usage: verify-nest-libs.sh <VAULT_SYMBOL> [CHAIN_ID]}"
CHAIN="${2:-98866}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
COMPILER='v0.8.30+commit.73712a01'

# --- load env (PLUME_VERIFIER_URL etc.) + dummy etherscan keys so --show-standard-json-input
#     doesn't choke on the [etherscan] table at older commits ---
set -a; source "$REPO/.env" 2>/dev/null || true; set +a
export ETHERSCAN_API_KEY_1=dummy ETHERSCAN_API_KEY_56=dummy \
       ETHERSCAN_API_KEY_42161=dummy ETHERSCAN_API_KEY_480=dummy
EXPLORER="$(printf '%s' "${PLUME_VERIFIER_URL:-https://explorer.plume.org/api/}" | sed 's#/api/\?$##')"

OUT="$REPO/script/output/$VAULT/$CHAIN-$VAULT.json"
[ -f "$OUT" ] || { echo "no deployment output: $OUT"; exit 1; }

# --- find the broadcast run that deployed this vault (match by share address) ---
SHARE="$(python3 -c "import json;print(json.load(open('$OUT'))['contracts']['share'])")"
RUN="$(grep -rl -i "$SHARE" "$REPO"/broadcast/DeployAndSetup.s.sol/"$CHAIN"/run-1*.json 2>/dev/null | head -1)"
[ -n "$RUN" ] || { echo "no broadcast run found for share $SHARE"; exit 1; }
COMMIT="$(python3 -c "import json;print(json.load(open('$RUN'))['commit'])")"
mapfile -t LIBPAIRS < <(python3 -c "import json;[print(l) for l in json.load(open('$RUN')).get('libraries',[]) or []]")
[ "${#LIBPAIRS[@]}" -gt 0 ] || { echo "no libraries recorded in $RUN"; exit 1; }
echo ">> $VAULT deployed at commit $COMMIT with ${#LIBPAIRS[@]} libs (run $(basename "$RUN"))"

# --- isolated worktree at the deploy commit, deps from main ---
WT="$(mktemp -d -t nest-verify-XXXX)"
trap 'cd "$REPO"; git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true' EXIT
git -C "$REPO" worktree add -f "$WT" "$COMMIT" >/dev/null
ln -sfn "$REPO/node_modules" "$WT/node_modules"
cd "$WT"
forge build >/dev/null 2>&1 || { echo "forge build failed at $COMMIT"; exit 1; }

# --- build the --libraries arg set (all libs, every call) ---
LIBARGS=(); for p in "${LIBPAIRS[@]}"; do LIBARGS+=("--libraries" "$p"); done

submit() { # <addr> <contract> <stdjson>
  curl -s -A "$UA" -X POST \
    "$EXPLORER/api/v2/smart-contracts/$1/verification/via/standard-input" \
    -H "Origin: $EXPLORER" -H "Referer: $EXPLORER/" \
    -F "compiler_version=$COMPILER" -F "license_type=none" \
    -F "files[0]=@$3;type=application/json"
}
status() { # <addr>
  curl -s -A "$UA" "$EXPLORER/api/v2/smart-contracts/$1" \
    | python3 -c "import json,sys;d=json.load(sys.stdin,strict=False);print('verified' if d.get('is_verified') else 'pending', '(partial)' if d.get('is_partially_verified') else '')" 2>/dev/null || echo "pending"
}

for p in "${LIBPAIRS[@]}"; do
  ADDR="${p##*:}"; CN="${p%:*}"; SHORT="${CN##*:}"
  JSON="$WT/$SHORT.std.json"
  forge verify-contract "$ADDR" "$CN" --compiler-version "$COMPILER" "${LIBARGS[@]}" \
    --show-standard-json-input > "$JSON" 2>/dev/null
  [ -s "$JSON" ] || { echo "!! $SHORT: empty std-json (forge error)"; continue; }
  R="$(submit "$ADDR" "$CN" "$JSON")"
  echo ">> $SHORT @ $ADDR -> $R"
done

echo ">> polling..."; sleep 12
for p in "${LIBPAIRS[@]}"; do
  ADDR="${p##*:}"; SHORT="${p%:*}"; SHORT="${SHORT##*:}"
  echo "   $SHORT @ $ADDR : $(status "$ADDR")"
done

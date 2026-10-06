#!/usr/bin/env bash
# tests/claude-account.sh — bin/claude-account in a sandbox: fake saved accounts, a fake live login, a stub
# `claude` and a stub `sudo`. Nothing touches a real login, a real job token or Anthropic (offline mode: the
# script trusts ~/.claude.json for who is logged in). Run by tests/smoke.sh; on its own: bash tests/claude-account.sh
# shellcheck disable=SC2016,SC2034  # each condition is a single-quoted string that t eval's later
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=${CLAUDE_ACCOUNT_BIN:-$here/bin/claude-account}   # a different copy, to show the tests can fail
top=$(mktemp -d) || exit 2
# The stubs below must be able to run. On a noexec /tmp (the NAS) bash skips them and finds the REAL claude and
# sudo further down PATH (NAS 2026-10-05: the real sudo wrote a factagent-owned file into the sandbox). So test
# for exec, and fall back to the cache folder.
printf '#!/bin/sh\n' > "$top/x" && chmod +x "$top/x"
if ! "$top/x" 2>/dev/null; then
    rm -rf -- "$top"; mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
    top=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/claude-account-test.XXXXXX") || exit 2
fi
rm -f -- "$top/x"
trap 'rm -rf -- "$top"' EXIT
fails=0
ok()   { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
t()    { if eval "$2"; then ok "$1"; else bad "$1"; fi; }   # <name> <condition, eval'd>

# new_sb <n accounts> [live account] — a fresh sandbox in $S; account k has id uk and login {"tok":"loginK"}
new_sb() {
    S=$(mktemp -d "$top/sb.XXXXXX"); mkdir -p "$S/cfg" "$S/acc" "$S/bin" "$S/jobs"
    local k
    for ((k = 1; k <= $1; k++)); do
        echo "{\"tok\":\"login$k\"}" > "$S/acc/$k.login.json"
        echo "{\"accountUuid\":\"u$k\",\"emailAddress\":\"a$k@example.com\"}" > "$S/acc/$k.account.json"
        echo "$k=Label $k" >> "$S/acc/labels"
    done
    if [[ -n ${2-} ]]; then
        cp "$S/acc/$2.login.json" "$S/cfg/.credentials.json"
        jq -n --slurpfile a "$S/acc/$2.account.json" '{keep: "me", oauthAccount: $a[0]}' > "$S/cfg/.claude.json"
    fi
    # stub claude: "ok" when it has a login file or a token; logs its argv; renews a login by adding a mark
    cat > "$S/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "argv: $*" >> "$STUB_LOG"
if [[ -n ${CLAUDE_CODE_OAUTH_TOKEN-} ]]; then echo "token: $CLAUDE_CODE_OAUTH_TOKEN" >> "$STUB_LOG"; echo ok; exit 0; fi
f=$CLAUDE_CONFIG_DIR/.credentials.json
[[ -s $f ]] || { echo "Not logged in"; exit 1; }
# a dead login: like the real one, blank the tokens in the file, then fail
grep -q dead "$f" && { echo '{"claudeAiOauth":{"accessToken":"","refreshToken":""}}' > "$f"; echo "Failed to authenticate: OAuth session expired"; exit 1; }
[[ -n ${STUB_RENEW-} ]] && jq -c '. + {renewed: true}' "$f" > "$f.n" && mv "$f.n" "$f"
echo ok
EOF
    # stub sudo: drops -n, and install's -o/-g (the sandbox cannot chown); logs what it ran
    cat > "$S/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -n ]] && shift
echo "sudo $*" >> "$STUB_LOG"
if [[ $1 == install ]]; then a=(); shift; while (( $# )); do case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done; exec install "${a[@]}"; fi
exec "$@"
EOF
    chmod +x "$S/bin/claude" "$S/bin/sudo"
    export CLAUDE_CONFIG_DIR=$S/cfg CLAUDE_ACCOUNTS_DIR=$S/acc CLAUDE_ACCOUNT_OFFLINE=1 STUB_LOG=$S/stub.log PATH=$S/bin:$PATH
    unset CLAUDE_ACCOUNT_YES STUB_RENEW
    [[ $(command -v claude) == "$S/bin/claude" && $(command -v sudo) == "$S/bin/sudo" ]] \
        || { echo "FAIL  the stubs cannot run here, so the real claude and sudo would; stopping"; exit 2; }
}
live() { jq -r '.oauthAccount.accountUuid' "$S/cfg/.claude.json"; }
cred() { jq -r '.tok' "$S/cfg/.credentials.json"; }
run() { "$T" "$@" 2>&1 </dev/null; }

# 1. other walks 1, 2, 3, 1 and leaves the rest of ~/.claude.json alone
new_sb 3 1; seq=""
for _ in 1 2 3 4; do run other >/dev/null; seq+="$(live):$(cred) "; done
t "other cycles 1, 2, 3, 1 (login and account move together)" '[ "$seq" = "u2:login2 u3:login3 u1:login1 u2:login2 " ]'
t "other keeps the rest of ~/.claude.json" '[ "$(jq -r .keep "$S/cfg/.claude.json")" = me ]'
t "other writes the history log" '[ "$(wc -l < "$S/acc/history.log")" -eq 4 ]'

# 2. two accounts flip; one account refuses
new_sb 2 2; run other >/dev/null; a=$(live); run other >/dev/null
t "other with two accounts flips back and forth" '[ "$a:$(live)" = "u1:u2" ]'
new_sb 1 1; out=$(run other); rc=$?
t "other with one account refuses" '[ $rc -ne 0 ] && grep -q "at least two" <<<"$out"'

# 3. it switches while Claude is open (no refusal, unlike the laptop's old copy)
new_sb 2 1; out=$(run use 2)
t "use switches without asking for Claude to be closed" '[ "$(live)" = u2 ] && grep -q "next message" <<<"$out"'

# 4. the live login is saved into its own slot before the switch (a renewal is kept)
new_sb 2 1; echo '{"tok":"login1","renewed":true}' > "$S/cfg/.credentials.json"; run use 2 >/dev/null
t "switching first saves the live login's renewal into its slot" '[ "$(jq -r .renewed "$S/acc/1.login.json")" = true ]'

# 5. an unsaved live login is never thrown away
new_sb 2 1; jq '.oauthAccount = {accountUuid: "zzz", emailAddress: "new@example.com"}' "$S/cfg/.claude.json" > "$S/x" && mv "$S/x" "$S/cfg/.claude.json"
out=$(run use 2)
t "use refuses to switch away from an unsaved login" '[ "$(live)" = zzz ] && grep -q "would be lost" <<<"$out"'

# 6. save: wrong number refused; a first save asks, or needs CLAUDE_ACCOUNT_YES without a terminal
new_sb 2 2; out=$(run save 1); rc=$?
t "save refuses to file account 2's login as account 1" '[ $rc -ne 0 ] && grep -q "not account 1" <<<"$out"'
jq '.oauthAccount = {accountUuid: "u9", emailAddress: "new@example.com"}' "$S/cfg/.claude.json" > "$S/x" && mv "$S/x" "$S/cfg/.claude.json"
out=$(setsid "$T" save 3 "Outlook (Alt 2)" 2>&1 </dev/null); rc=$?
t "a first save with no terminal refuses and says how" '[ $rc -ne 0 ] && [ ! -e "$S/acc/3.login.json" ] && grep -q CLAUDE_ACCOUNT_YES <<<"$out"'
out=$(CLAUDE_ACCOUNT_YES=1 run save 3 "Outlook (Alt 2)")
t "a confirmed first save stores the login, its owner and the name" '[ "$(jq -r .accountUuid "$S/acc/3.account.json"):$(sed -n '\''s/^3=//p'\'' "$S/acc/labels")" = "u9:Outlook (Alt 2)" ]'
t "saved files are private (0600, folder 0700)" '[ "$(stat -c %a "$S/acc/3.login.json"):$(stat -c %a "$S/acc")" = 600:700 ]'

# 7. the jobs: only with jobs.conf; every token file follows, the owned one through sudo; metrics written
new_sb 3 1
for k in 1 2; do echo "token$k" > "$S/acc/$k.token"; done
cp "$S/acc/1.token" "$S/jobs/main"; cp "$S/acc/1.token" "$S/jobs/fa"
printf 'token %s\ntoken %s factagent   # owned by another user\nprom %s\n' "$S/jobs/main" "$S/jobs/fa" "$S/jobs/m.prom" > "$S/acc/jobs.conf"
out=$(run use 2)
t "use moves every job token file" '[ "$(cat "$S/jobs/main"):$(cat "$S/jobs/fa")" = token2:token2 ] && grep -q "unattended jobs from Label 1" <<<"$out"'
t "the owned copy is written through sudo" 'grep -q "sudo install" "$S/stub.log"'
t "the metrics say account 2, copies match" 'grep -q '\''claude_account_active{account="2",label="Label 2"} 1'\'' "$S/jobs/m.prom"'
t "the metrics say the copies match" 'grep -q "claude_account_copies_match 1" "$S/jobs/m.prom"' 
out=$(run use 3)
t "an account with no job token leaves the jobs alone but still switches Claude" '[ "$(cat "$S/jobs/main"):$(live)" = token2:u3 ] && grep -q "no job token saved" <<<"$out"'
out=$(run)
t "status names a jobs/Claude mismatch" 'grep -q "jobs use account 2" <<<"$out"'
echo other > "$S/jobs/fa"; out=$(run)
t "status catches a copy that does not match" 'grep -q "does NOT match" <<<"$out"'
rm "$S/acc/jobs.conf"; out=$(run)
t "tokens without jobs.conf are pointed out" 'grep -q "jobs.conf is missing" <<<"$out"'

# 8. check: one line each; a renewal is kept (slot and live); a dead login says so; the token never in argv
new_sb 3 1; echo '{"tok":"dead"}' > "$S/acc/3.login.json"
echo "token2" > "$S/acc/2.token"; printf 'token %s\n' "$S/jobs/main" > "$S/acc/jobs.conf"; cp "$S/acc/2.token" "$S/jobs/main"
tmpbefore=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -user "$(id -u)" -name 'tmp.*' 2>/dev/null | wc -l)
out=$(STUB_RENEW=1 run check)
t "check prints no shell error and leaves no temp folder behind" \
    '! grep -qE "unbound|command not found" <<<"$out" && [ "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -user "$(id -u)" -name "tmp.*" 2>/dev/null | wc -l)" -le "$tmpbefore" ]'
t "check reports each account" '[ "$(grep -c works <<<"$out")" -eq 2 ] && grep -q "3  Label 3 .*expired" <<<"$out"'
t "check tests the job token too, where jobs run" 'grep -q "2  Label 2 .*login works, job token works" <<<"$out"'
t "check keeps a renewal for the slot and the live login" '[ "$(jq -r .renewed "$S/acc/1.login.json"):$(jq -r .renewed "$S/cfg/.credentials.json"):$(jq -r .renewed "$S/acc/2.login.json")" = true:true:true ]'
t "check never saves the blanked file a dead login leaves" '[ "$(jq -r .tok "$S/acc/3.login.json")" = dead ]'
t "check passes the job token in the environment, never in argv" 'grep -q "token: token2" "$S/stub.log" && ! grep -q "argv:.*token2" "$S/stub.log"'

# 9. it never prints a token or a login
new_sb 2 1; echo token1 > "$S/acc/1.token"; out=$(run; run help; run use 2; run check)
t "no output shows a login or a token" '! grep -qE "login[12]|token1" <<<"$out"'

if (( fails == 0 )); then echo "claude-account: all passed"; else echo "claude-account: $fails failed"; exit 1; fi

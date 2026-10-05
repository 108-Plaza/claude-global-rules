#!/usr/bin/env bash
# test-pretooluse-guard.sh — run BEFORE pushing any edit to pretooluse-guard.sh (autopull ships it to every machine).
# Builds a throwaway git repo, pipes synthetic hook payloads through the guard, and checks the wrapper command
# from claude-rules-install-guard fails open when the guard itself is broken. Exit 0 = all pass.
set -u
D=$(cd "$(dirname "$0")" && pwd)
G="$D/pretooluse-guard.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0

bash -n "$G" || { echo "FAIL syntax: $G"; exit 1; }

R="$T/repo"; mkdir "$R"; cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo a > a && git add a && git commit -qm init

t() { # name cwd command want(allow|deny)
  local out rc got s=OK
  out=$(jq -n --arg c "$3" --arg d "$2" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' | "$G" 2>&1); rc=$?
  got=allow; [[ $out == *'"deny"'* ]] && got=deny
  if [ "$got" != "$4" ] || [ $rc -ne 0 ]; then s=FAIL; fail=1; fi
  printf '%s [%s] rc=%s got=%s want=%s\n' "$s" "$1" "$rc" "$got" "$4"
}

t plain-ls "$R" 'ls -la' allow
t status "$R" 'git status' allow
t commit-on-main "$R" 'git commit -m "x"' deny
t push-on-main "$R" 'git push origin HEAD' deny
t skipci "$R" 'git commit -m "docs [skip ci]"' deny
t skipci-case "$R" 'git commit -m "x [CI Skip]"' deny
git checkout -qb feat/x
t commit-on-feature "$R" 'git commit -m "x"' allow
t skipci-chained "$R" 'git add a && git commit -m "x [skip ci]"' deny
t push-feature "$R" 'git push -u origin feat/x' allow
t push-branch-named-main-thing "$R" 'git push -u origin fix/main-thing' allow
t push-to-main "$R" 'git push origin main' deny
t push-head-main "$R" 'git push origin HEAD:main' deny
t push-then-echo-main "$R" 'git push origin feat/x && echo main' allow
t gitC "$R" "git -C $R commit -m x" allow
t gitC-unresolved-var "$R" 'git -C $SOME_DIR commit -m x' allow
t gitC-unresolved-var-skipci "$R" 'git -C $SOME_DIR commit -m "x [skip ci]"' deny
git -C "$R" checkout -q main
t gitC-unresolved-var-on-main-cwd "$R" 'git -C $SOME_DIR commit -m x' allow
t gitC-real-path-on-main "$R" "git -C $R commit -m x" deny
git -C "$R" checkout -q feat/x 2>/dev/null || git -C "$R" checkout -q -b feat/x
t cd-redundant "$R" "cd $R && ls" deny
t cd-elsewhere "$R" "cd /tmp && ls" allow
t add-env "$R" 'git add .env' deny
t add-env-example "$R" 'git add .env.example' allow
t add-env-override "$R" 'GUARD_ALLOW_SECRET_FILES=1 git add .env' allow
echo "TQ_TOKEN=abcdefghijklmnop1234" > cfg.txt; git add cfg.txt
t staged-token "$R" 'git commit -m x' deny
t staged-token-override "$R" 'GUARD_ALLOW_SECRET_FILES=1 git commit -m x' allow
git reset -q cfg.txt; echo k > id_rsa; git add -f id_rsa
t staged-keyfile "$R" 'git commit -m x' deny
git reset -q id_rsa
mkdir -p "$T/home/.claude/x" && git -C "$T/home/.claude/x" init -q -b main && git -C "$T/home/.claude/x" config user.email t@t
HOME="$T/home" t exempt-under-claude-dir "$T/home/.claude/x" 'git commit -m x' allow

# robustness: garbage input must not block
out=$(echo 'not json' | "$G"); rc=$?; [ $rc -eq 0 ] && [ -z "$out" ] || { echo "FAIL garbage-stdin rc=$rc"; fail=1; }
out=$(echo '{}' | "$G"); rc=$?; [ $rc -eq 0 ] && [ -z "$out" ] || { echo "FAIL empty-json rc=$rc"; fail=1; }

# wrapper: a guard with a syntax error (bash exits 2) must NOT block; a missing guard must NOT block
CMD=$("$D/claude-rules-install-guard" --print-command)
mkdir -p "$T/w/.claude/rules-repo/bin"
printf '#!/usr/bin/env bash\nif [[ then\n' > "$T/w/.claude/rules-repo/bin/pretooluse-guard.sh"; chmod +x "$T/w/.claude/rules-repo/bin/pretooluse-guard.sh"
echo '{}' | HOME="$T/w" bash -c "$CMD" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && echo "OK [wrapper-broken-guard] rc=0" || { echo "FAIL [wrapper-broken-guard] rc=$rc"; fail=1; }
echo '{}' | HOME="$T/none" bash -c "$CMD" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && echo "OK [wrapper-missing-guard] rc=0" || { echo "FAIL [wrapper-missing-guard] rc=$rc"; fail=1; }
# wrapper passes a real deny through
out=$(jq -n --arg d "$R" '{cwd:$d,tool_input:{command:"git commit -m \"x [skip ci]\""}}' | HOME="$HOME" bash -c "$CMD")
[[ $out == *'"deny"'* ]] && echo "OK [wrapper-passes-deny]" || { echo "FAIL [wrapper-passes-deny]"; fail=1; }

[ $fail -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail

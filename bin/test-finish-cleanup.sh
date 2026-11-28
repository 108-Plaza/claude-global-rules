#!/usr/bin/env bash
# test-finish-cleanup.sh — run BEFORE pushing any edit to finish-cleanup (autopull ships it to every machine,
# and it is the one delete command AI sessions may run without a prompt).
# Builds a throwaway origin + clone + linked worktrees under this user's claude-<uid> temp dir (a scratch root
# the script accepts), runs the script against them, and checks what it removed and what it kept. Exit 0 = all pass.
#   FC=<path> bash bin/test-finish-cleanup.sh   # test another copy of the script
set -u
D=$(cd "$(dirname "$0")" && pwd)
FC=${FC:-$D/finish-cleanup}
base="/tmp/claude-$(id -u)"
mkdir -p "$base" || exit 1
T=$(mktemp -d "$base/test-finish-cleanup.XXXXXX") || exit 1
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
cd / || exit 1
fail=0

bash -n "$FC" || { echo "FAIL syntax: $FC"; exit 1; }

g() { git -c user.email=t@t -c user.name=t "$@"; }
g init -q --bare -b main "$T/origin.git"
g clone -q "$T/origin.git" "$T/main" 2>/dev/null
echo a > "$T/main/a" && g -C "$T/main" add a && g -C "$T/main" commit -qm init && g -C "$T/main" push -q origin HEAD:main
g -C "$T/main" worktree add -q -b feat/live "$T/wt-live"
g -C "$T/main" worktree add -q -b feat/stale "$T/wt-stale"

check() { # name want-rc out rc
  local s=OK
  [ "$3" = "$2" ] || { s=FAIL; fail=1; }
  printf '%s [%s] rc=%s want=%s\n' "$s" "$1" "$3" "$2"
}
present() { # name path...
  local n=$1 p; shift
  for p in "$@"; do [ -e "$p" ] || { echo "FAIL [$n] $p is gone"; fail=1; }; done
}
absent() { # name path
  [ -e "$2" ] && { echo "FAIL [$1] $2 still exists"; fail=1; }
}

# 1. A clone whose linked worktree still exists is refused, and both folders survive.
out=$(bash "$FC" "$T/main" 2>&1); rc=$?
check clone-with-live-worktree 1 "$rc"
present clone-with-live-worktree "$T/main/.git" "$T/main/a" "$T/wt-live/a" "$T/wt-live/.git"
case "$out" in *"linked worktrees:"*"$T/wt-live"*) ;; *) echo "FAIL [clone-with-live-worktree] refusal does not name the linked path: $out"; fail=1 ;; esac

# 2. --dry-run refuses the same way.
out=$(bash "$FC" --dry-run "$T/main" 2>&1); rc=$?
check dry-run-clone-with-live-worktree 1 "$rc"
case "$out" in *"linked worktrees:"*) ;; *) echo "FAIL [dry-run] no refusal: $out"; fail=1 ;; esac

# 3. The linked worktree itself (.git is a file) is still removable; the clone forgets it.
out=$(bash "$FC" "$T/wt-live" 2>&1); rc=$?
check linked-worktree-removable 0 "$rc"
absent linked-worktree-removable "$T/wt-live"
present linked-worktree-removable "$T/main/.git"

# 4. A stale entry (folder deleted by hand, never pruned) does not block the clone.
rm -rf "$T/wt-stale"
out=$(bash "$FC" "$T/main" 2>&1); rc=$?
check clone-with-only-stale-entry 0 "$rc"
absent clone-with-only-stale-entry "$T/main"

# --- gitignored secrets (2026-11-28: the only ScreenLink board config was deleted with its worktree) ---
g clone -q "$T/origin.git" "$T/c2" 2>/dev/null
printf 'target/\nesp32s3-rs/src/config.rs\n.secret.key\nsecrets/\n' > "$T/c2/.gitignore"
mkdir -p "$T/c2/esp32s3-rs/src" && echo 'fn main() {}' > "$T/c2/esp32s3-rs/src/main.rs"
g -C "$T/c2" add -A && g -C "$T/c2" commit -qm ignore && g -C "$T/c2" push -q origin HEAD:main
mkwt() { # name — a clean linked worktree of c2 on a fresh branch at origin/main
  g -C "$T/c2" worktree add -q -b "feat/$1" "$T/$1" origin/main 2>/dev/null
  mkdir -p "$T/$1/target/debug" && echo junk > "$T/$1/target/debug/build.key"  # a cache: never searched
}
mkwt wt-secret; echo 'pub const WIFI_PASS: &str = "x";' > "$T/wt-secret/esp32s3-rs/src/config.rs"
mkwt wt-cache
mkwt wt-nested; mkdir -p "$T/wt-nested/secrets" && echo K=v > "$T/wt-nested/secrets/.env"
mkwt wt-bank; head -c 32 /dev/urandom > "$T/wt-bank/.secret.key"

# 5. An ignored esp32s3-rs/src/config.rs keeps the worktree, and the reason names it.
out=$(bash "$FC" "$T/wt-secret" 2>&1); rc=$?
check ignored-secret-kept 1 "$rc"
present ignored-secret-kept "$T/wt-secret/esp32s3-rs/src/config.rs"
case "$out" in *"kept $T/wt-secret: holds ignored secret esp32s3-rs/src/config.rs"*"--allow-secret"*) ;; *) echo "FAIL [ignored-secret-kept] no reason: $out"; fail=1 ;; esac

# 6. --dry-run reports the same refusal and deletes nothing.
out=$(bash "$FC" --dry-run "$T/wt-secret" 2>&1); rc=$?
check dry-run-ignored-secret 1 "$rc"
present dry-run-ignored-secret "$T/wt-secret/esp32s3-rs/src/config.rs"
case "$out" in *"holds ignored secret: esp32s3-rs/src/config.rs"*) ;; *) echo "FAIL [dry-run-ignored-secret] not reported: $out"; fail=1 ;; esac

# 7. Only ignored caches (target/, even holding a *.key) ⇒ removed.
out=$(bash "$FC" "$T/wt-cache" 2>&1); rc=$?
check only-target-removed 0 "$rc"
absent only-target-removed "$T/wt-cache"

# 8. A secret inside an ignored non-cache folder is found too.
out=$(bash "$FC" "$T/wt-nested" 2>&1); rc=$?
check secret-in-ignored-folder-kept 1 "$rc"
present secret-in-ignored-folder-kept "$T/wt-nested/secrets/.env"

# 9. --allow-secret <file> removes it (after the caller checked a copy exists outside).
cp "$T/wt-secret/esp32s3-rs/src/config.rs" "$T/config.rs.copy"
out=$(bash "$FC" --allow-secret "$T/wt-secret/esp32s3-rs/src/config.rs" "$T/wt-secret" 2>&1); rc=$?
check allow-secret-removed 0 "$rc"
absent allow-secret-removed "$T/wt-secret"

# 10. A throwaway bank-bot .secret.key: kept by default, removed with --allow-secret (relative path works).
out=$(bash "$FC" "$T/wt-bank" 2>&1); rc=$?
check throwaway-key-kept-by-default 1 "$rc"
out=$( (cd "$T" && bash "$FC" --allow-secret wt-bank/.secret.key wt-bank) 2>&1); rc=$?
check throwaway-key-allowed 0 "$rc"
absent throwaway-key-allowed "$T/wt-bank"

[ "$fail" = 0 ] && echo "all pass" || echo "FAILED"
exit "$fail"

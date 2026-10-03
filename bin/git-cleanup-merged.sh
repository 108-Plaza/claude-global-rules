#!/bin/bash
# git-cleanup-merged.sh — ลบ branch ที่ merge เข้า default branch แล้ว (local + optional remote)
#
#   git-cleanup-merged.sh [--remote] [--dry-run] [REPO ...]
#
# ไม่มี REPO = ใช้ repo ปัจจุบัน (cwd)
# --remote   ลบ branch บน origin ด้วย (ต้องมี gh + สิทธิ์เขียน)
# --dry-run  แสดงอย่างเดียว ไม่ลบ
#
# เกณฑ์ปลอดภัย — ลบเฉพาะ branch ที่พิสูจน์ได้ว่าไม่มี commit หาย:
#   A = tip เป็น ancestor ของ origin/<default>            (merge commit ปกติ)
#   B = ทุก commit มี patch-equivalent อยู่ใน default แล้ว (squash / rebase merge)
# branch ที่มี commit เฉพาะตัว (C) จะไม่ถูกแตะ
set -uo pipefail

PROTECTED_RE='^(main|master|develop|dev|prod|production|staging|gh-pages|(release|deploy|sync|auto|backup|archive)/.*)$'

DO_REMOTE=0; DRY=0; REPOS=()
for a in "$@"; do
  case "$a" in
    --remote) DO_REMOTE=1;;
    --dry-run|-n) DRY=1;;
    -*) echo "unknown flag: $a" >&2; exit 2;;
    *) REPOS+=("$a");;
  esac
done
[ ${#REPOS[@]} -eq 0 ] && REPOS=(".")

default_branch() {
  local r=$1 d
  d=$(git -C "$r" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); d=${d#origin/}
  if [ -z "$d" ]; then
    for c in main master; do git -C "$r" show-ref -q --verify "refs/remotes/origin/$c" && { d=$c; break; }; done
  fi
  echo "$d"
}

# $1=repo $2=ref-to-test $3=origin/default  → prints A, B, or nothing
classify() {
  local r=$1 ref=$2 base=$3
  if git -C "$r" merge-base --is-ancestor "$ref" "$base" 2>/dev/null; then echo A; return; fi
  local u; u=$(git -C "$r" cherry "$base" "$ref" 2>/dev/null | grep -c '^+')
  [ "${u:-1}" -eq 0 ] && echo B
}

for r in "${REPOS[@]}"; do
  git -C "$r" rev-parse --git-dir >/dev/null 2>&1 || { echo "skip (not a repo): $r"; continue; }
  git -C "$r" remote | grep -q . || { echo "skip (no remote): $r"; continue; }
  echo "=== $r"
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15" \
    git -C "$r" fetch origin --prune --quiet 2>/dev/null
  def=$(default_branch "$r"); [ -z "$def" ] && { echo "  ! no default branch"; continue; }
  cur=$(git -C "$r" rev-parse --abbrev-ref HEAD)
  wt=$(git -C "$r" worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2); print $2}')

  # ---------- local ----------
  while read -r b; do
    [ -z "$b" ] && continue
    [[ "$b" =~ $PROTECTED_RE ]] && continue
    [ "$b" = "$def" ] || [ "$b" = "$cur" ] && continue
    grep -qx "$b" <<<"$wt" && continue
    cls=$(classify "$r" "$b" "origin/$def"); [ -z "$cls" ] && continue
    sha=$(git -C "$r" rev-parse --short "$b")
    if [ $DRY -eq 1 ]; then echo "  [dry] local  $b ($cls, $sha)"
    else git -C "$r" branch -D "$b" >/dev/null && echo "  del local  $b ($cls, $sha)"; fi
  done < <(git -C "$r" for-each-ref --format='%(refname:short)' refs/heads/)

  # ---------- remote ----------
  [ $DO_REMOTE -eq 0 ] && continue
  url=$(git -C "$r" remote get-url origin); case "$url" in *github.com*) ;; *) echo "  ! remote skip (not github)"; continue;; esac
  slug=$(sed -E 's#.*github.com[:/]##; s#\.git$##' <<<"$url")
  # canonicalize: GitHub redirects a renamed repo's old slug to the same repo
  canon=$(gh api "repos/$slug" -q .full_name 2>/dev/null)
  [ -n "$canon" ] && slug=$canon
  # ของเราเท่านั้น — ห้ามแตะ repo ของคนอื่น (upstream clone)
  case "$slug" in 108-Plaza/*|yuthstyle88/*) ;; *) echo "  ! remote skip (not ours: $slug)"; continue;; esac
  if [ "$(gh api "repos/$slug" -q .archived 2>/dev/null)" = "true" ]; then echo "  ! remote skip (archived)"; continue; fi
  openpr=$(gh pr list -R "$slug" --state open --limit 300 --json headRefName -q '.[].headRefName' 2>/dev/null)
  while read -r b; do
    b=${b#refs/remotes/origin/}
    [ -z "$b" ] || [ "$b" = "HEAD" ] && continue
    [[ "$b" =~ $PROTECTED_RE ]] && continue
    [ "$b" = "$def" ] && continue
    grep -qx "$b" <<<"$openpr" && continue          # PR ยังเปิดอยู่
    cls=$(classify "$r" "origin/$b" "origin/$def"); [ -z "$cls" ] && continue
    sha=$(git -C "$r" rev-parse --short "origin/$b")
    if [ $DRY -eq 1 ]; then echo "  [dry] remote $b ($cls, $sha)"
    else gh api -X DELETE "repos/$slug/git/refs/heads/$b" >/dev/null 2>&1 \
           && echo "  del remote $b ($cls, $sha)" || echo "  ! remote fail $b"; fi
  done < <(git -C "$r" for-each-ref --format='%(refname)' refs/remotes/origin/)
done

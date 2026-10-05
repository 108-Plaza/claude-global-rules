#!/usr/bin/env bash
# PreToolUse(Bash) guardrail — turns rules from ~/.claude/CLAUDE.md into deterministic blocks.
#   1. [skip ci] (and variants) in a git commit      -> required checks never report, PR stuck BLOCKED
#   2. git commit / git push while on main|master     -> "Never work on main" (repos under ~/.claude are exempt)
#   3. git push whose refspec targets main|master     -> "Never push directly to main"
#   4. secrets in staged changes                      -> override: prefix the command with GUARD_ALLOW_SECRET_FILES=1
#   5. redundant `cd <cwd>` at the start of a command -> Bash Command Hygiene
# Fail-open: any internal error allows the command (exit 0, no output).
set -u
set -f

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd=$PWD

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

unquote() { local s=$1; s=${s//\"/}; s=${s//\'/}; s=${s/#\~/$HOME}; printf '%s' "$s"; }

re_git='git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+'
re_commit="(^|[;&|(]|[[:space:]])${re_git}commit([[:space:]]|\$)"
re_push="(^|[;&|(]|[[:space:]])${re_git}push([[:space:]]|\$)"
re_add="(^|[;&|(]|[[:space:]])${re_git}add([[:space:]]|\$)"
re_commit_all='commit[^;&|]*[[:space:]]-[a-zA-Z]*a'
re_cd_start='^[[:space:]]*cd[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];&|]+)'
re_cd_any='(^|[;&|][[:space:]]*)cd[[:space:]]+("[^"]+"|[^[:space:];&|]+)'
re_gitC='git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+)'

# 5. redundant cd
if [[ $cmd =~ $re_cd_start ]]; then
  d=$(unquote "${BASH_REMATCH[1]}")
  if [ -d "$d" ] && [ "$(cd "$d" 2>/dev/null && pwd -P)" = "$(cd "$cwd" 2>/dev/null && pwd -P)" ]; then
    deny "cwd is already $cwd — drop the leading 'cd $d' and run the command directly (use git -C <path> or path arguments for other folders). Rule: Bash Command Hygiene."
  fi
fi

is_commit=0; is_push=0; is_add=0
[[ $cmd =~ $re_commit ]] && is_commit=1
[[ $cmd =~ $re_push ]] && is_push=1
[[ $cmd =~ $re_add ]] && is_add=1
[ $((is_commit + is_push + is_add)) -eq 0 ] && exit 0

# which directory will git run in
dir=$cwd; unresolved=0
if [[ $cmd =~ $re_cd_any ]]; then d=$(unquote "${BASH_REMATCH[2]}"); if [ -d "$d" ]; then dir=$d; else unresolved=1; fi; fi
if [[ $cmd =~ $re_gitC ]]; then d=$(unquote "${BASH_REMATCH[1]}"); if [ -d "$d" ]; then dir=$d; else unresolved=1; fi; fi

# 1. [skip ci] — needs no repo
if [ $is_commit -eq 1 ] && printf '%s' "$cmd" | grep -qiE '\[(skip ci|ci skip|no ci|skip actions|actions skip)\]|skip-checks:[[:space:]]*true'; then
  deny "Commit message contains a CI-skip marker. GitHub then creates no jobs, required checks never report and the PR stays BLOCKED forever (park108#943). Remove it; save CI on doc-only PRs in the workflow, not in the message."
fi

# the target path is a shell variable / not created yet: the hook sees raw text, so do not guess from cwd
[ $unresolved -eq 1 ] && exit 0

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -z "$top" ] && exit 0

# 2 + 3. main / master
home_real=$(cd "$HOME" 2>/dev/null && pwd -P)
if [[ $top != "$HOME/.claude/"* && $top != "$home_real/.claude/"* ]]; then
  br=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
  if [ "$br" = main ] || [ "$br" = master ]; then
    if [ $is_commit -eq 1 ] || [ $is_push -eq 1 ]; then
      deny "You are on '$br' in $top. Rule: never work on or push directly to main/master. Run: git switch -c <feat|fix|chore|docs>/<name> (or work in a worktree), then retry."
    fi
  fi
  if [ $is_push -eq 1 ]; then
    seg=$(printf '%s' "$cmd" | sed -E 's/.*git[^;&|]*[[:space:]]push//; s/[;&|].*//')
    for w in $seg; do
      case $w in
        main|master|*:main|*:master|refs/heads/main|refs/heads/master|*:refs/heads/main|*:refs/heads/master)
          deny "This push targets '$w'. Rule: never push directly to main/master — push a feature branch and open a PR." ;;
      esac
    done
  fi
fi

# 4. secrets
if printf '%s' "$cmd" | grep -q 'GUARD_ALLOW_SECRET_FILES=1'; then exit 0; fi

secret_name() {
  local p=$1 b=${1##*/}
  case $b in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
    .env|.env.*|id_rsa|id_ed25519|id_ecdsa|key.properties|jev.env|*.pem|*.p12|*.pfx|*.p8|*.jks|*.keystore) return 0 ;;
  esac
  [[ $p == */tq/env || $p == tq/env ]] && return 0
  return 1
}

names=""
if [ $is_commit -eq 1 ]; then
  names=$(git -C "$dir" diff --cached --name-only 2>/dev/null)
  if [[ $cmd =~ $re_commit_all ]] || [[ $cmd == *"--all"* ]]; then
    names="$names"$'\n'"$(git -C "$dir" diff --name-only 2>/dev/null)"
  fi
fi
if [ $is_add -eq 1 ]; then
  seg=$(printf '%s' "$cmd" | sed -E 's/.*git[^;&|]*[[:space:]]add//; s/[;&|].*//')
  for w in $seg; do case $w in -*) ;; *) names="$names"$'\n'"$(unquote "$w")" ;; esac; done
fi
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if secret_name "$f"; then
    deny "'$f' looks like a secret/credential file. Rule: never commit tokens or keys. If it is a harmless fixture, prefix the command with GUARD_ALLOW_SECRET_FILES=1."
  fi
done <<< "$names"

if [ $is_commit -eq 1 ]; then
  hit=$(git -C "$dir" diff --cached -U0 --no-color 2>/dev/null | head -c 5000000 | grep -E '^\+' | grep -oE 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|TQ_TOKEN=[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}' | head -1 | sed -E 's/^(.{8}).*/\1…/')
  if [ -n "$hit" ]; then
    deny "Staged changes contain something shaped like a secret (starts with '$hit'). Unstage it. If it is a fake test value, prefix the command with GUARD_ALLOW_SECRET_FILES=1."
  fi
fi

exit 0

#!/usr/bin/env bash
# อัปเดต .github/public-sync.json หลัง "ตามไปแก้รีโปสาธารณะแล้วจริง"
# ปฏิเสธถ้ารีโปสาธารณะยังไม่ขยับ (กันการกด marker ให้เขียวโดยไม่แก้อะไร)
set -euo pipefail
cd "$(dirname "$0")/.."
M=.github/public-sync.json
REPO=$(python3 -c "import json;print(json.load(open('$M'))['public_repo'])")
OLD=$(python3 -c "import json;print(json.load(open('$M'))['public_head'])")
NEW=$(git ls-remote "https://github.com/$REPO" HEAD | cut -f1)
SEC=$(python3 scripts/public_sections.py)
if [ "$NEW" = "$OLD" ] && [ "${1:-}" != "--force" ]; then
  echo "🔴 $REPO ยังอยู่ที่ $OLD — ยังไม่ได้ตามไปแก้" >&2
  echo "   แก้ที่นั่นก่อน แล้วค่อยรันคำสั่งนี้ใหม่ (หรือ --force ถ้าจงใจว่าไม่ต้องแก้)" >&2
  exit 1
fi
python3 - "$M" "$SEC" "$NEW" <<'PY'
import json,sys,datetime
m,sec,head=sys.argv[1],sys.argv[2],sys.argv[3]
d=json.load(open(m)); d["sections_sha"]=sec; d["public_head"]=head
d["updated"]=datetime.date.today().isoformat()
json.dump(d,open(m,"w"),ensure_ascii=False,indent=2); open(m,"a").write("\n")
PY
echo "✅ อัปเดต $M แล้ว — อย่าลืม commit"

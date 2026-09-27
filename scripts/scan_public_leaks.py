#!/usr/bin/env python3
"""สแกนไฟล์ที่จะเผยแพร่ว่ามีรายละเอียดภายในหลุดไหม — ออก 1 ถ้าเจอ

ใช้กับเนื้อหาของ 108-Plaza/agent-working-rules (public)
"""
import re, sys, io, pathlib

CHECKS = {
    "IP address":            r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b",
    "โฮสต์/โดเมนภายใน":       r"[\w.-]*(?:108plaza|ibrowe|108jobs|108heros|typesafe)\.[a-z]{2,}",
    "ชื่อรีโป/org ภายใน":      r"(?i)108-?Plaza|yuthstyle88|pos108[\w-]*|park108|jh-api|108-agent-queue|claude-global-rules",
    "ชื่อเครื่อง/ผู้ใช้ระบบ":   r"(?i)Dell-server|macstudio|macmini|MacBook|Mac Studio|Mac mini|Lenovo|DESKTOP-[\w-]+|legion|/home/yuth|/data/yuth",
    "ชื่อผู้ให้บริการเฉพาะ":    r"(?i)\bJev\b|TypeSafe|Antigravity|\bGLM\b|z\.ai|Gemini|Codex|redis|tmux",
    "พาธความลับ / โทเคน":     r"(?i)~/\.config|\.env\b|authorized_keys|Bearer |TQ_TOKEN|ghp_|github_pat_|PRIVATE KEY",
    "พอร์ตภายใน":             r"\b(?:6381|8787|31440|3005|51775)\b",
    "image / bundle id / DB": r"ghcr\.io|com\.\w+\.\w+|db_\w+",
    "อีเมล":                  r"[\w.+-]+@[\w-]+\.[\w.]+",
    "เลขใบที่ผูกรีโปภายใน":    r"#\d{2,}",
}

def main(paths):
    bad = 0
    for p in paths:
        text = io.open(p, encoding="utf-8", errors="replace").read()
        for name, pat in CHECKS.items():
            hits = sorted({m if isinstance(m, str) else m[0] for m in re.findall(pat, text)})
            if hits:
                bad += len(hits)
                print(f"  🔴 {p}: {name} -> {hits[:8]}")
    print("  ✅ ไม่พบรายละเอียดภายใน" if not bad else f"\n🔴 พบ {bad} รายการ")
    return 1 if bad else 0

if __name__ == "__main__":
    args = sys.argv[1:]
    files = [str(f) for a in args for f in (pathlib.Path(a).rglob("*.md") if pathlib.Path(a).is_dir() else [pathlib.Path(a)])]
    sys.exit(main(files))

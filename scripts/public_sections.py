#!/usr/bin/env python3
"""พิมพ์ sha256 ของ "หัวข้อวิธีทำงาน" ใน CLAUDE.md — หัวข้อที่มีคู่แฝดในรีโปสาธารณะ

หัวข้อที่ไม่อยู่ในรายการนี้ = โครงสร้างพื้นฐาน/ธุรกิจ ซึ่ง**ตั้งใจ**ไม่มีในฉบับสาธารณะ
เพิ่ม/ลบหัวข้อที่นี่เมื่อขอบเขตของฉบับสาธารณะเปลี่ยนเท่านั้น
"""
import hashlib, io, re, sys

MIRRORED = [
    "# Division of Labour", "## 🟢 merge", "## 🔔", "## 🔬", "## ✍️", "## 🧾",
    "## 📌", "## 🌱", "## 🧩", "## 🔁", "## 🔭", "## 📋", "## 🔢", "## 🔀",
    "# Autonomous Execution Policy", "# Additional Global Rules", "# Context Handoff",
]

def blocks(text):
    lines = text.split("\n")
    starts = [i for i, l in enumerate(lines) if re.match(r"^#{1,2} ", l)]
    out = []
    for n, i in enumerate(starts):
        if any(lines[i].startswith(p) for p in MIRRORED):
            j = starts[n + 1] if n + 1 < len(starts) else len(lines)
            out.append("\n".join(lines[i:j]).rstrip())
    return out

def main():
    text = io.open("CLAUDE.md", encoding="utf-8").read()
    bs = blocks(text)
    missing = [p for p in MIRRORED if not any(b.startswith(p) for b in bs)]
    if missing:
        print("หัวข้อที่ระบุไว้แต่หาไม่เจอใน CLAUDE.md: " + ", ".join(missing), file=sys.stderr)
        return 2
    h = hashlib.sha256("\n\n".join(bs).encode("utf-8")).hexdigest()
    print(h)
    if "--list" in sys.argv:
        for b in bs:
            print(f"  {b.splitlines()[0][:70]}", file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main())

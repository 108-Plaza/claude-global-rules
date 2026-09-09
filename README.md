# claude-global-rules

ต้นทางเดียวของ `~/.claude/CLAUDE.md` — กฎกลางที่ Claude ทุกเซสชันบนทุกเครื่องโหลดตอนเริ่ม

## ใช้ยังไง

แต่ละเครื่องมีสำเนาที่ `~/.claude/rules-repo` และ `~/.claude/CLAUDE.md` เป็น **symlink** ชี้เข้ามา
⇒ เซสชันไหนแก้กฎ = แก้ในเวิร์กทรีนี้โดยอัตโนมัติ ไม่มีขั้นตอน "อย่าลืมก๊อปกลับ"

```bash
claude-rules status   # เทียบเครื่องนี้กับ origin/main
claude-rules pull     # ดึงกฎล่าสุดลงเครื่องนี้
claude-rules push     # ส่งกฎที่เพิ่งแก้ขึ้น origin (rebase ก่อนเสมอ)
claude-rules doctor   # ซ่อม symlink ที่ถูกเครื่องมืออื่นเขียนทับเป็นไฟล์ธรรมดา
```

## ทำไมต้องมี repo นี้

ก่อนหน้านี้ซิงก์ด้วย `scp` ไขว้กันสามเครื่อง · 2026-09-09 มีอย่างน้อย 3 เซสชันแก้ไฟล์นี้
ภายในสองชั่วโมง แล้วการ `scp` ทับ **ลบหัวข้อกฎของเจ้าของหายไป 32 บรรทัด** โดยไม่มีใครรู้
(กู้ได้เพราะบังเอิญสำรองไว้) · git จับการชนแบบนั้นได้เอง — push ที่ตามหลังจะถูกปฏิเสธ
แทนที่จะทับเงียบ ๆ

## เครื่องที่ต่ออยู่

| เครื่อง | ผู้ใช้ | สิทธิ์ที่ใช้ |
|---|---|---|
| MacBook Pro | `yongyutjantaboot` | ssh key ส่วนตัว (`yuthstyle88`) |
| Mac Studio | `yuth` | ssh key ส่วนตัว (`yuthstyle88`) |
| Mac mini | `yuth` | **deploy key ของ repo นี้** (`~/.ssh/claude_rules_deploy`, host alias `github-rules`) |

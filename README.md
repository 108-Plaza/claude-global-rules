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
| Mac mini | `yuth` | ⚠️ **ยังต่อ GitHub ตรงไม่ได้** — org `108-Plaza` ปิด deploy key (`deploy_keys_enabled_for_repositories=false`) และคีย์ ssh ของเครื่องนั้นเป็น deploy key ของ `pos108-core` ไม่ใช่ผู้ใช้ |

**ท่าสำรองของ Mac mini (ใช้อยู่ตอนนี้):** สำเนาตั้งต้นมาจาก `git bundle` และตั้ง
`receive.denyCurrentBranch=updateInstead` ⇒ MacBook/Studio ส่งกฎเข้าเครื่องนั้นได้ด้วย
`git -C ~/.claude/rules-repo push mini main` (remote `mini` = `ssh://yuth@macmini/Users/yuth/.claude/rules-repo`)
· working tree ของ mini อัปเดตตามเอง · **แต่ mini ยัง push กลับขึ้น origin เองไม่ได้**
⇒ ถ้าเซสชันบน mini แก้กฎ ต้องให้เครื่องอื่นดึงไปส่งแทน หรือเปิด deploy key ที่ org

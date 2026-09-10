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

## ดึงอัตโนมัติ

ทั้งสามเครื่องมี LaunchAgent `com.108ting.claude-rules-autopull` (ทุก 15 นาที + ตอนล็อกอิน)
เรียก `~/bin/claude-rules-autopull` ซึ่ง **fast-forward เท่านั้น** ไม่ rebase ไม่ stash ไม่ commit เอง
· เครื่องที่มีของค้างหรือมี commit ยังไม่ push = ข้ามและเขียนเหตุผลลง `~/.claude/rules-sync.log`
· **heartbeat วันละครั้ง** เมื่อไม่มีอะไรต้องดึง (`heartbeat: ตรงกับ origin (<sha>)`) ⇒ log เงียบ
  = เอเยนต์ตาย ไม่ใช่ "ไม่มีอะไรเปลี่ยน" · เหตุผล "ข้าม" ที่ซ้ำ ๆ ถูกจำกัดไว้ 6 ชม./ครั้ง
  ไม่งั้นเวิร์กทรีสกปรกค้างวันเดียวได้ 96 บรรทัด
· ดูสถานะ: `launchctl print gui/$(id -u)/com.108ting.claude-rules-autopull`
· สั่งให้รันเดี๋ยวนี้: `launchctl kickstart gui/$(id -u)/com.108ting.claude-rules-autopull`

⚠️ **ใช้ cron ไม่ได้** — `crontab` ผ่าน ssh บน macOS ตอบ `Operation not permitted`
(ต้องให้ sshd มี Full Disk Access) จึงใช้ launchd แทน

**MacBook หลับ = ไม่ดึง** ⇒ มี `bin/keep-awake` (`status|on|off`) ติดตั้งไว้ที่ `~/bin/keep-awake`
· `on` กางตัวกันหลับระดับผู้ใช้ (`caffeinate -s` ใน LaunchAgent `com.108ting.keep-awake`,
KeepAlive, **ไม่ต้อง sudo**) ซึ่งกันหลับเฉพาะตอนเสียบไฟ · ค่าที่ต้อง `sudo` (`pmset -c sleep 0` ฯลฯ)
สคริปต์ไม่แตะให้ แต่ `status` จะบอกว่าค่าไหนยังไม่ถูก · **ปิดฝา = หลับเสมอ กันไม่ได้**

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
| Mac mini | `yuth` | **deploy key ของ repo นี้** (`~/.ssh/claude_rules_deploy` · host alias `github-rules`) |
| Dell (`Dell-server`, Linux) | `yuth` | **HTTPS + `gh auth git-credential`** ตั้งไว้ใน config ของ clone เท่านั้น (ไม่แตะ global) |

Dell ต่อเข้าระบบ 2026-09-11 — ก่อนหน้านั้นเป็นไฟล์ที่ก๊อปมาทีละรอบ จึงไม่ได้กฎใหม่เอง
· ใช้ HTTPS เพราะ `~/.ssh/config` ของ Dell ผูก `github.com` ไว้กับ deploy key ของ `pos108-core`
· Linux ใช้ **cron** ได้ปกติ (ข้อห้าม cron ข้างบนเป็นเรื่องของ macOS): `*/15` เรียก
  `~/.claude/rules-repo/bin/claude-rules-autopull` ตรงจาก clone · สำรอง crontab เดิมไว้ที่ `~/crontab.bak-*`

Mac mini ใช้ deploy key เพราะคีย์ ssh เดิมของเครื่องนั้น (`id_ed25519`, `pos108_deploy`)
authenticate เป็น deploy key ของ `pos108-core` ไม่ใช่ผู้ใช้ · เจ้าของเปิด
`deploy_keys_enabled_for_repositories` ที่ org ให้เมื่อ 2026-09-09 คีย์นี้จึงเพิ่มได้
· คีย์เขียนได้ และแตะได้เฉพาะ repo นี้ repo เดียว

**ท่าสำรอง (ยังใช้ได้ ไม่ต้องพึ่ง GitHub):** mini ตั้ง `receive.denyCurrentBranch=updateInstead`
⇒ เครื่องอื่นส่งเข้าไปตรง ๆ ได้ด้วย `git -C ~/.claude/rules-repo push mini main`

# iOS-hld-for-existing-code

[English](README.md) | **ภาษาไทย**

- **iOS:** [github.com/Ntpstv/iOS-hld-for-existing-code](https://github.com/Ntpstv/iOS-hld-for-existing-code)
- **Android:** [github.com/opsst/android-hld-skill](https://github.com/opsst/android-hld-skill)
- **สไลด์ (Mobile Native Thailand Meetup #4):** [Mobile Native 2026 #1.pdf](Mobile%20Native%202026%20%231.pdf)

เครื่องมือสร้าง High-Level Design (HLD) อัตโนมัติสำหรับโปรเจกต์ iOS  
วิเคราะห์ซอร์สโค้ด Swift แล้วสร้าง canvas บน Figma ที่แสดงหน้าจอ ปลายทางของแต่ละหน้าจอ การเรียก API และ flow ระหว่างหน้าจอ — ใช้เวลาเป็นนาที ไม่ใช่เป็นชั่วโมง

รองรับสถาปัตยกรรม **CleanSwift / VIP**, **MVC**, **MVVM** และ **SwiftUI**

---

## วิธีใช้งาน

### ขั้นที่ 1 — Clone เครื่องมือเข้าโปรเจกต์

```bash
git clone https://github.com/Ntpstv/iOS-hld-for-existing-code.git Tools
```

รันครั้งเดียวที่ root ของโปรเจกต์ โฟลเดอร์ `Tools/` เพิ่มลง `.gitignore` ได้อย่างปลอดภัย

---

### ขั้นที่ 2 — รัน analyzer

```bash
bash Tools/hldgen.sh <ModuleDir>
```

`<ModuleDir>` คือโฟลเดอร์ module ของคุณ เช่น `Calendar`, `Shop`, `MyApp`
ต้องระบุแค่ค่านี้ค่าเดียว สคริปต์จะ build analyzer แล้วหาที่เหลือให้เอง:

- **หน้าจอ (Screens)** — ทุกโฟลเดอร์ใต้ `<Module>/<Module>/Scenes/` (หรือทั้ง module ถ้าไม่มี `Scenes/`)
  ที่มีไฟล์ `*ViewController.swift` ถ้า module ไม่มี view controller
  จะใช้โฟลเดอร์ที่มี `*ViewModel.swift` / `*View.swift` แทน
- **ชื่อ module** — ส่วนสุดท้ายของ `<ModuleDir>`
- **API endpoints** — สแกนทั้ง git repo เพราะ Service, API class และ Router
  ของหน้าจอหนึ่งมักอยู่คนละ framework
- **Flow file** — ไฟล์ `*.swift` ไฟล์แรกใน `<Module>/<Module>/Flow/` (ถ้ามีโฟลเดอร์นี้)

ผลลัพธ์ถูกเขียนเป็น `Tools/HLDFigmaPlugin/bundle.json` ข้างๆ manifest ของ plugin
ใช้ `-o <path>` ถ้าต้องการเก็บที่อื่น เมื่อเสร็จ สคริปต์จะเพิ่มชื่อไฟล์ bundle
และโฟลเดอร์ `Tools/` ลงใน `.gitignore` ของ repo หลักให้ด้วย

**ตัวอย่าง:**
```bash
bash Tools/hldgen.sh Shop
```
```
Found 12 scene(s):
  Shop/Shop/Scenes/Checkout/Card
  Shop/Shop/Scenes/Checkout/Card/CardCheckoutDetails
  …
API scan root: /path/to/your-repo
No flow file found (skipping --flow-file)

Generating → Tools/HLDFigmaPlugin/bundle.json
wrote 12 scene(s) → Tools/HLDFigmaPlugin/bundle.json

✓ Done: Tools/HLDFigmaPlugin/bundle.json
  Paste into Figma plugin (Plugins → Development → iOS-hld-for-existing-code)
```

<details>
<summary>รัน analyzer โดยตรง โดยไม่ใช้สคริปต์</summary>

ต้องระบุโฟลเดอร์ของแต่ละหน้าจอเองทีละตัว — หนึ่งโฟลเดอร์ได้หนึ่งหน้าจอ
ถ้าส่งโฟลเดอร์แม่ไปจะได้การ์ดใบเดียว ไม่ใช่ทั้ง module:

```bash
swift run --package-path Tools/HLDGen hldgen \
  <sceneDir> [<sceneDir> ...] \
  --module <ModuleName> \
  --services-dir . \
  [--flow-file <Module>/<Module>/Flow/<File>.swift] \
  -o Tools/HLDFigmaPlugin/bundle.json
```

`--services-dir` คือ root ที่ใช้สแกนหา class ประเภท Service/API/Router (ใส่ซ้ำได้หลายครั้ง)
ถ้าไม่ใส่ จะไม่มีการ resolve API endpoint

พิมพ์ `--module` ด้วยมือ อย่า copy จากสไลด์หรือเอกสาร — editor มักแปลง
double hyphen เป็น en dash ทำให้ `—module` ใช้ไม่ได้และ error ที่อ่านไม่รู้เรื่อง
</details>

---

### ขั้นที่ 3 — โหลด plugin ใน Figma

Plugin นี้ไม่ได้อยู่บน Figma marketplace ต้องโหลดจากดิสก์เอง และต้องใช้
**Figma desktop app** — เวอร์ชันเบราว์เซอร์ไม่มีเมนู Development

1. Figma desktop → **menu → Plugins → Development → Import plugin from manifest…**
2. เลือก `Tools/HLDFigmaPlugin/manifest.json`

ทำครั้งเดียว หลังจากนั้นจะอยู่ที่ **Plugins → Development → iOS-hld-for-existing-code**

---

### ขั้นที่ 4 — Generate

1. รัน **Plugins → Development → iOS-hld-for-existing-code**
2. วางเนื้อหาจาก `Tools/HLDFigmaPlugin/bundle.json`
3. กด **Generate**

canvas จะมีหนึ่งคอลัมน์ต่อหนึ่งหน้าจอ ประกอบด้วย:

- **Header** — ชื่อ navigation title ตามที่ผู้ใช้เห็น และชื่อ view controller class
- **Wireframe** — layout จาก storyboard/xib ตามตำแหน่งจริง
- **GOES TO** — ทุกปลายทางที่ action ของหน้าจอนั้นไปถึง `→` คือหน้าจอใน journey เดียวกัน
  `↗` คือหน้าจอใน journey อื่น หรือหน้าจอที่จับคู่ไม่ได้ แถวที่ชี้ไปยังหน้าจอที่วาดไว้เป็นลิงก์
  กดเพื่อกระโดดไปหน้านั้นได้
- **API** — endpoint ที่หน้าจอเรียก (method + path) พร้อม field ของ request และ response
- **NOTIFICATION CENTER** / **LOCAL STORAGE** — แสดงเฉพาะเมื่อหน้าจอนั้นใช้งาน

หน้าจอถูกจัดกลุ่มเป็น journey ที่มีป้ายชื่อ (หนึ่งโฟลเดอร์ใต้ `Scenes/` ต่อหนึ่ง journey)
และเรียงจากซ้ายไปขวาตามลำดับ flow ลูกศรวาดเฉพาะระหว่างคอลัมน์ที่อยู่ติดกัน พร้อมป้ายบอก
action ที่นำไปสู่หน้านั้น หน้าจอที่มีหน้าถัดไปหลายหน้าจะแตกกิ่งผ่านสี่เหลี่ยมข้าวหลามตัด (decision)
ส่วนการข้ามไกลกว่านั้นให้ดูจากแถว GOES TO

การรันซ้ำจะล้างผลลัพธ์เดิมก่อน board จึงไม่ซ้อนกันหลายรุ่น
สิ่งที่คุณวาดเองบนหน้านั้นจะไม่ถูกแตะต้อง

---

## ข้อกำหนด

- Xcode ที่มี Swift toolchain
- **Figma desktop app** (บัญชีฟรีใช้ได้ — เวอร์ชันเบราว์เซอร์โหลด plugin จากเครื่องไม่ได้)

## โครงสร้าง Repository

```
Tools/
├── HLDGen/          # Swift package — ตัววิเคราะห์ (analyzer)
│   └── Sources/HLDGen/
├── HLDFigmaPlugin/  # Figma plugin
│   ├── code.js
│   └── ui.html
└── hldgen.sh        # สคริปต์ห่อเพื่อความสะดวก (ไม่บังคับ)
```

## License

MIT — ดู [LICENSE](LICENSE)

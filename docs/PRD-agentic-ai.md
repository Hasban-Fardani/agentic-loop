# PRD — Agent Engineering Playbook (AEP) v2.1

**Status:** Revisi dari v0.2 — bukan buang total. Stack, role, branching, dan visual verification checkpoint dari v0.2 **dipertahankan** karena sudah solid dan relevan. Yang ditambahkan: 5 mekanisme baru yang secara eksplisit menjawab 5 pola gagal yang kamu alami (reinvent, langgar konvensi, overcomplex, popularity bias, overconfidence). v2.0 (redesign total) ditarik — terlalu jauh membuang hal yang sebenarnya sudah kepakai.
**Owner:** Hasban Fardani / Hustle Studio
**Stack:** Hermes Agent (orchestrator) + GitHub (state/gate) + agentic-loop (evidence gate) + Spec Kit (planning) — sama seperti v0.2.

---

## 0. Apa yang berubah dari v0.2, apa yang tidak

**Dipertahankan apa adanya dari v0.2:**
- Decision Log #1–#4 (scope project baru saja, reviewer final manusia, 5 role langsung, branching/worktree strategy).
- Arsitektur pipeline (AGENTS.md → Issue → Hermes → Worker → `al run` → PR → Reviewer/Security/QA paralel → Merge manusia).
- 6 file inti (AGENTS.md, WORKFLOW.md, TASK_TEMPLATE.md, CHECKLIST.md, METRICS.md, README.md).
- 5 role (Planner, Coder, Reviewer, Security, QA) dengan persona/tools/batas wewenang masing-masing.
- Branching & worktree strategy (section 6a).
- **Visual Verification Checkpoint (section 6c) — drawio-skill untuk ERD, Open Design untuk prototype UI.** Ini yang paling kamu tekankan tetap relevan, jadi tidak diubah strukturnya, hanya ditambah satu keterkaitan baru (lihat 4.2).

**Ditambahkan (baru di v2.1), semua sebagai *gate tambahan* yang menempel ke role yang sudah ada, bukan role baru:**
1. Discovery Phase — wajib sebelum Coder mulai kerja (P1: reinvent).
2. Convention Extraction — CONVENTIONS.md yang di-scan dari kode existing, bukan ditulis dari template (P2: langgar konvensi).
3. Complexity Budget — gate mekanis di `al run` (P3: overcomplex).
4. Decision Framework — DECISION.md wajib untuk pilihan tool/library signifikan (P4: popularity bias).
5. Verification-over-claim — diperluas dari sekadar "test lulus" ke semua jenis klaim role (P5: overconfidence).

Tidak ada file/role yang dihapus dari v0.2. Yang berubah cuma: beberapa role dapat tugas tambahan yang eksplisit, dan ada beberapa file baru.

---

## 1. Problem Statement (5 masalah, dengan bukti)

Lima masalah ini didokumentasikan luas di riset/industri sebagai pola gagal umum AI coding agent — bukan spesifik ke setup kamu. Penting supaya solusinya diarahkan ke akar masalah, bukan ke gejala permukaan.

**P1 — Reinvent daripada reuse.** Studi GitClear terhadap ratusan juta baris kode menunjukkan refactoring/reuse kode lama menurun tajam sejak AI coding tools meluas, sementara kode baru yang ditambahkan naik — polanya "tempel kode baru", bukan "pakai/rapikan yang lama". Studi akademik terpisah terhadap 15.451 operasi refactoring oleh AI agent (NAIST & Queen's University, 2025) menemukan agent hanya menyasar duplikasi kode di 1,1% refactoring dan modularitas/reuse di 4,6% — dibanding 13,7% dan 12,9% pada refactoring manusia. Akarnya struktural: agent tidak search codebase dulu sebelum generate, jadi kode yang sudah ada "tidak eksis" kalau tidak masuk context window saat itu.

**P2 — Melanggar konvensi/arsitektur project.** Agent coding bekerja dengan pattern-matching terhadap apa yang dia lihat di codebase kamu. Kalau constraint arsitektur (misal "tidak ada Service Layer di project ini") tidak pernah ditulis eksplisit di tempat yang dibaca agent, agent akan "membetulkan" dengan pola paling umum yang dia kenal dari training data — bukan pola project kamu.

**P3 — Kode terlalu rumit.** Ini bukan gejala acak: model AI dioptimasi untuk kebenaran fungsional, bukan kesederhanaan. Riset SoftwareSeni (2026) soal quality gate untuk AI-generated code mencatat pola konkret: nested conditional, loop tidak perlu, logika berbelit untuk masalah yang sebenarnya sederhana. Riset lain (SlopCodeBench) mencatat kompleksitas menumpuk saat agent patch berulang tanpa refactor — dan ironisnya paling parah justru saat model dikasih mode "high thinking" (overthink).

**P4 — Bias popularitas, bukan efektivitas, dalam memilih tool/library.** Kasus real kamu (Laravel-Excel vs PhpSpreadsheet langsung untuk export sheet kompleks dengan template existing) adalah instance dari masalah lama di software engineering: memilih library itu harus berbasis fakta terhadap constraint konkret, bukan suara terbanyak/GitHub stars. LLM (termasuk saya) punya bias frekuensi kuat ke opsi yang paling sering muncul di data training — itu bukan penilaian teknis, itu statistik token.

**P5 — Overconfidence.** Ini berakar di level training, bukan sekadar gaya bicara: skema RLHF standar secara sistematis mengganjar reward model yang condong ke output ber-confidence tinggi, dan miskalibrasi ini paling parah justru di titik batas pengetahuan model — titik paling berbahaya. Riset kalibrasi juga menunjukkan self-reflection model terhadap kerjanya sendiri **tidak cukup** memperbaiki ini — perlu verifikasi dari sumber independen, bukan model menilai ulang klaimnya sendiri.

**Kesimpulan:** akar dari kelima masalah ini sama — agent membuat keputusan/klaim tanpa verifikasi ke kenyataan project kamu. v0.2 sudah menangkap prinsip ini lewat `al run` ("evidence over claims") tapi hanya untuk klaim "test lulus". v2.1 memperluas prinsip yang sama ke 4 jenis klaim lain yang selama ini dipercaya mentah dari laporan agent.

---

## 2. Arsitektur (revisi dari v0.2 — pipeline sama, ditambah 4 gate baru)

```
AGENTS.md (context inti, ~150 baris) + CONVENTIONS.md (BARU — hasil scan, lihat 4.2)
        │
        ▼
GitHub Issue (task, scope, allowed/forbidden paths)
        │
        ▼
Hermes Agent (orchestrator)
        │
        ▼
Planner: Spec Kit + Visual Verification Checkpoint (6c, TETAP)
         + DECISION.md kalau ada pilihan tool/library signifikan (BARU, lihat 4.4)
        │
        ▼
Worker/Coder: di worktree terisolasi
         + Discovery Phase wajib sebelum implementasi (BARU, lihat 4.1)
         + tunduk ke CONVENTIONS.md hard constraint (BARU)
        │
        ▼
agentic-loop `al run standard` → PASS/FAIL/UNKNOWN
         + Complexity Budget check (BARU, lihat 4.3) — bisa jadi bagian dari `al run standard`
        │
        ▼
GitHub PR (Draft sampai PASS)
        │
        ▼
Reviewer/Security/QA (paralel, fresh context, TETAP dari v0.2)
         + mengecek klaim kepastian tanpa artifact rujukan (BARU, lihat 4.5)
        │
        ▼
Merge manusia (TETAP — agent tidak pernah merge kerjanya sendiri)
```

---

## 3. File Inti (6 file v0.2 + 4 file baru = 10 file)

| File | Isi | Status |
|---|---|---|
| `AGENTS.md` | Overview, build/test command, pointer ke file lain | **Tetap dari v0.2**, ~150 baris |
| `WORKFLOW.md` | SOP Issue → Plan → Approval → Implementation → `al run` → Review → Merge | **Tetap dari v0.2** |
| `TASK_TEMPLATE.md` | Template Issue: Objective, Allowed/Forbidden Files, Success Criteria | **Tetap dari v0.2** |
| `CHECKLIST.md` | Definition of Done, merujuk exit code `al run` | **Tetap dari v0.2** |
| `METRICS.md` | KPI (lihat section 5, digabung dengan metrik baru) | **Tetap dari v0.2**, isi ditambah |
| `README.md` | Entry point manusia | **Tetap dari v0.2** |
| `CONVENTIONS.md` | **BARU.** Hasil scan konvensi project (hard vs soft constraint), dikonfirmasi manusia — bukan ditulis dari ingatan/template | Baru, lihat 4.2 |
| `DECISION.md` (folder, satu file per keputusan) | **BARU.** Log keputusan tool/library/pendekatan signifikan | Baru, lihat 4.4 |
| `DISCOVERY.md` (per task, di komentar PR/Issue — tidak perlu file permanen) | **BARU.** Bukti pencarian reuse sebelum implementasi | Baru, lihat 4.1 |
| `COMPLEXITY.md` | **BARU.** Threshold yang dipakai + tool ukur + pengecualian disetujui | Baru, lihat 4.3 |

`AGENTS.md` tetap jadi pointer utama seperti v0.2 — bedanya sekarang dia menunjuk ke `CONVENTIONS.md` untuk detail konvensi, bukan mencoba memuat semuanya sendiri.

---

## 4. Empat Mekanisme Baru — menempel ke role yang sudah ada

### 4.1 Discovery Phase → ditambahkan ke role **Coder**

Sebelum menulis kode implementasi, Coder wajib:
1. Grep/text search nama fungsi/fitur mirip.
2. Baca 2–3 file paling mirip secara fungsi — kutip pola konkretnya, bukan cuma "sudah dicek".
3. Cek dependency yang sudah terinstall (`composer.json`) untuk kapabilitas yang mungkin sudah ada tapi belum dipakai.
4. Kalau kesimpulannya "tidak ada yang bisa dipakai ulang" — itu klaim yang harus dijustifikasi (apa yang dicari, kenapa tidak cocok), bukan kalimat kepercayaan diri kosong.

**Perubahan ke Batas Wewenang Coder (section 6b v0.2):** ditambah larangan eksplisit — Coder **tidak boleh** membuka PR (bahkan Draft) sebelum Discovery Phase tercatat di komentar Issue.

### 4.2 Convention Extraction → ditambahkan ke setup awal (dijalankan sekali per project, bukan per task) + terhubung ke Visual Verification Checkpoint (6c)

`CONVENTIONS.md` **tidak ditulis manual di awal** dari ingatan kamu — dihasilkan dari scan otomatis terhadap kode existing (struktur folder, ada Service Layer atau tidak, pola error handling, dst), lalu **dikonfirmasi kamu** sebelum jadi constraint yang mengikat. Dipisah dua kategori:
- **Hard constraint** (blocking, dicek mekanis lewat lint rule/custom check di `al run`): contoh "tidak ada Service Layer, Controller boleh langsung panggil Model/Repository".
- **Soft convention** (diikuti tapi boleh di-deviasi dengan alasan tertulis): contoh gaya penamaan.

**Ini yang menghubungkan ke section 6c (Visual Verification Checkpoint) yang kamu bilang tetap relevan:** cek ERD di 6c poin 1 ("apakah relasi antar tabel match dengan constraint di AGENTS.md") sekarang eksplisit dicocokkan ke `CONVENTIONS.md`, bukan ke AGENTS.md yang isinya cuma pointer. Checkpoint visual itu tetap jalan persis seperti desain v0.2 — cuma sumber constraint-nya sekarang lebih presisi.

### 4.3 Complexity Budget → ditambahkan sebagai bagian dari `al run standard`

Bukan instruksi "tolong sederhana" (lemah, karena model secara struktural dioptimasi ke kebenaran fungsional bukan kesederhanaan) — harus mekanis:
- Cyclomatic complexity threshold per fungsi (mulai jadi masalah di >10, hard problem di >15 — **catatan: angka ini rule of thumb umum, kemungkinan perlu disesuaikan untuk gaya fluent query builder Laravel yang bisa menaikkan angka tanpa benar-benar susah dibaca — validasi di Fase 1, lihat Open Question**).
- Batas ukuran fungsi/file, boleh dilanggar tapi wajib alasan tertulis.
- **Prinsip default ke Coder:** solusi paling sederhana yang lulus requirement + test — bukan solusi paling robust/scalable yang kepikiran duluan. YAGNI sebagai default, bukan exception yang perlu diminta.

`al run standard` yang tadinya cuma exit code test/build (v0.2), sekarang juga menjalankan static analysis complexity check sebagai bagian dari command yang sama — supaya distinction PASS/FAIL/UNKNOWN tetap konsisten, tidak dibuat gate terpisah yang malah membingungkan.

### 4.4 Decision Framework → ditambahkan ke role **Planner**

Untuk pilihan tool/library/pendekatan signifikan (bukan semua keputusan kecil), Planner wajib isi `DECISION.md`:

| Bagian | Isi wajib |
|---|---|
| Problem statement | Kebutuhan konkret, bukan generik — contoh: "butuh export ke template xlsx existing dengan formatting kompleks, volume X baris" bukan "butuh export excel" |
| Constraint konkret | Format/template existing, ukuran data, performa, kompatibilitas dengan `CONVENTIONS.md` |
| Minimal 2 kandidat | Wajib termasuk minimal satu opsi **bukan** yang paling populer, dievaluasi murni dari fit ke constraint |
| Bukti, bukan asumsi | Klaim performa/kompatibilitas harus dicek (baca dokumentasi asli/coba kecil), bukan ditebak dari nama besar |
| Alasan penolakan alternatif | Spesifik ke constraint, bukan "kurang populer" |

**Larangan eksplisit:** Planner tidak boleh menjustifikasi pilihan hanya dengan "paling banyak dipakai/GitHub stars tertinggi" sebagai alasan utama. Popularitas boleh jadi salah satu sinyal (maintenance aktif, dokumentasi lengkap — itu sinyal risiko yang legit) tapi bukan alasan tunggal.

**Perubahan ke Batas Wewenang Planner (section 6b v0.2):** klausul lama "tidak boleh memutuskan tech stack tanpa konfirmasi kamu kalau spec asli tidak menyebutkannya" sekarang diperjelas mekanismenya — konfirmasi itu **melalui** `DECISION.md`, bukan sekadar tanya di chat.

### 4.5 Verification-over-claim → ditambahkan ke role **Reviewer**

v0.2 sudah punya prinsip ini untuk klaim "test lulus" lewat `al run`. v2.1 memperluas ke klaim lain yang selama ini dipercaya mentah:

| Klaim | Verifikasi pengganti |
|---|---|
| "Sudah dicek, tidak ada kode serupa" | `DISCOVERY.md` (4.1) — bisa diaudit |
| "Ini sudah sesuai pola project" | Dicocokkan ke `CONVENTIONS.md` (4.2) |
| "Ini sudah simpel/tidak over-engineered" | Angka complexity metric (4.3) |
| "Library ini paling cocok" | `DECISION.md` (4.4) |
| "Sudah dites, semua jalan" | Exit code `al run` (v0.2, tetap) |

**Perubahan ke Output Reviewer (section 6b v0.2):** ditambah satu kategori temuan baru selain Critical/Major/Minor/Nitpick — **"Unverified Claim"**: kalimat kepastian ("pasti", "sudah optimal", "sesuai standar") yang tidak merujuk ke salah satu artifact di atas. Ini otomatis jadi item yang harus dijawab sebelum PR ditandai `status:ready-for-human-review`.

Catatan penting: jangan andalkan Coder mereview klaimnya sendiri untuk ini — sesuai riset, self-reflection tidak cukup memperbaiki miskalibrasi. Makanya ini ditaruh di role Reviewer (fresh context, tanpa riwayat chat Coder — ini sudah desain v0.2, tinggal dipakai untuk kategori temuan baru ini juga).

---

## 5. Metrics (gabungan v0.2 + baru)

| Metrik | Cara ukur | Menjawab |
|---|---|---|
| % task exit `UNKNOWN` di `al run` | Event log agentic-loop | v0.2, tetap |
| % PR di-revert dalam 48 jam | GitHub API | v0.2, tetap |
| Waktu Issue dibuka → PR merged | GitHub Projects timestamp | v0.2, tetap |
| Jumlah instruksi aktif AGENTS.md + WORKFLOW.md | Manual count, target <150 | v0.2, tetap |
| % task dengan `DISCOVERY.md` terisi memadai vs asal | Audit sampling PR | P1 (baru) |
| Duplikasi fungsi terdeteksi pasca-merge (mis. PHPCPD, periodik) | Tool scan | P1 (baru) |
| % PR menyimpang `CONVENTIONS.md` tanpa justifikasi | Review sampling | P2 (baru) |
| Distribusi cyclomatic complexity kode baru vs threshold | Static analysis per-PR | P3 (baru) |
| % `DECISION.md` mencantumkan ≥1 kandidat non-populer | Audit manual | P4 (baru) |
| Jumlah temuan "Unverified Claim" per PR (kategori baru Reviewer) | Dari komentar review | P5 (baru) |

Baseline: sama seperti v0.2 — belum ada, diisi setelah 2–4 minggu pemakaian nyata.

---

## 6. Scope Fase 1 (1–2 minggu, tidak berubah signifikan dari v0.2 — ditambah validasi mekanisme baru)

**In scope:**
- Semua in-scope v0.2 (6 file inti, `al init`+`al doctor`, Spec Kit, 1 GitHub Action required check, Hermes jalankan 5 role, branching/worktree sejak task pertama).
- `CONVENTIONS.md` pertama lewat proses scan+konfirmasi (4.2) untuk project yang dipilih.
- Minimal 1 `DECISION.md` nyata (4.4) — idealnya kasus mirip Laravel-Excel/PhpSpreadsheet, supaya langsung ketahuan formatnya kepakai atau kebanyakan birokrasi.
- Complexity check (4.3) terpasang di `al run standard` — pilih satu tool dulu (mis. PHPStan/phpmetrics), jangan multi-tool di awal.
- Validasi drawio-skill dan Open Design langsung di task pertama (ini Open Question v0.2 #5 — tetap belum tervalidasi, tetap prioritas Fase 1).

**Out of scope (ditunda):**
- Sama seperti v0.2: adapter Cursor/Windsurf, cost-routing model, governance/RFC, delegasi penuh `git worktree` ke Hermes.

---

## 7. Open Questions (gabungan v0.2 + baru)

**Dari v0.2 (belum berubah):**
1. QA boleh menulis kode test langsung atau cuma menyarankan?
2. Kompatibilitas Spec Kit dengan Hermes belum tervalidasi.
3. Siapa yang menjalankan `git worktree add`/`remove` — manual dulu atau delegasi ke Hermes?
4. Threshold "task kecil tidak perlu worktree terpisah" masih subjektif.
5. `drawio-skill` dan `Open Design` belum pernah dicoba langsung di setup kamu — validasi di task pertama Fase 1.

**Baru di v2.1:**
6. Threshold cyclomatic complexity 15 itu rule of thumb umum — perlu dicoba dulu ke kode Laravel real kamu, karena fluent query builder bisa menaikkan angka tanpa kode-nya benar-benar susah dibaca.
7. Siapa yang menjalankan Convention Extraction (4.2) pertama kali — agent scan lalu kamu approve, atau kamu draft dulu lalu agent isi detail?
8. Format `DISCOVERY.md` — komentar PR/Issue biasa, atau file fisik di repo?
9. Tool duplication scan untuk PHP (PHPCPD) belum divalidasi cocok untuk pola Laravel kamu.

---

## 8. Roadmap setelah Fase 1

Sama seperti v0.2 — Fase 2 evaluasi `METRICS.md` per role (termasuk metrik baru section 5) untuk lihat apakah 5 mekanisme baru ini kepakai atau cuma nambah birokrasi tanpa hasil. Kalau ada mekanisme yang datanya menunjukkan overhead > manfaat, disederhanakan — keputusan berbasis data, bukan ditebak, sama prinsipnya dengan v0.2.
# Agentic Engineering Platform — PRD v7.1

**Status:** Siap menjalankan Fase 0 dengan Hermes Agent sebagai constrained primary harness; Fase 1 bersifat conditional setelah baseline

**Pemilik:** Hasban / Hustle Studio  
**Tanggal:** 2 Agustus 2026  
**Target awal:** Satu repository privat non-pemerintah pada server Linux dengan RAM 2 GB

## 0. Koreksi arsitektur dan keputusan utama

Versi sebelumnya mencampurkan dua hal:

1. **Hermes Agent**, yaitu agent coding siap pakai dari Nous Research; dan
2. **workflow engineering platform**, yaitu policy, evidence, risk gate, GitHub/CI, audit, dan operating model milik Hustle Studio.

PRD v7.1 memisahkan keduanya. Hermes tidak dibangun ulang dan tidak diperlakukan sebagai service yang harus digantikan oleh orchestrator custom.

Hermes sudah menyediakan agent loop, provider/model resolution, terminal dan file tools, session storage, persistent memory, skills, gateway, scheduled automation, approval command, dan beberapa terminal backend. Fitur-fitur tersebut menjadi dependency yang dikonfigurasi dan diuji, bukan fitur yang diimplementasikan ulang oleh proyek ini.

### 0.1 Keputusan arsitektur Fase 0

| Area | Keputusan Fase 0 |
|---|---|
| Primary harness | Hermes Agent versi yang dipin dan diuji |
| Agent loop | Hermes bawaan; tidak membuat agent/orchestrator baru |
| Context | `AGENTS.md` atau `.hermes.md` sebagai aturan proyek; satu sumber aturan utama |
| Memory agent | Built-in memory Hermes boleh menjadi context hint dengan write approval; external memory provider off pada Fase 0; bukan source of truth audit |
| Skills | Hanya bundled/project skill yang di-allowlist; agent-created skill wajib approval; Skills Hub/MCP install tidak otomatis |
| Terminal | `local` pada user Linux khusus untuk pilot terkontrol; Docker atau CI untuk kode yang tidak dipercaya/high-risk |
| LLM | Provider eksternal; server 2 GB tidak menjalankan model lokal |
| Evidence | Bash adapter + GitHub Actions/CI sebagai verifier independen |
| Source control | GitHub, branch, PR, branch protection |
| Database custom | Tidak ada di Fase 0; audit utama memakai PR, GitHub checks, Evidence Artifact, dan event JSONL |
| SQLite/PostgreSQL/Redis | Tidak menjadi dependency awal; baru dipertimbangkan jika kebutuhan terbukti |
| Bahasa custom | Bash terlebih dahulu, tool Rust yang sudah ada berikutnya, Bun 1.4 hanya jika script mulai membutuhkan logic terstruktur |
| Eksekusi | Serial; satu task aktif dan satu verifier aktif |
| Merge/deploy | Manual pada Fase 0 dan Fase 1 untuk medium/high-risk |
| Durable orchestration | Tidak dibangun; Hermes session, Git, PR, dan artifact menjadi checkpoint awal |

Referensi operasional resmi Hermes yang menjadi dasar keputusan ini:

- [Hermes Agent documentation](https://hermes-agent.nousresearch.com/docs/)
- [Hermes architecture](https://hermes-agent.nousresearch.com/docs/developer-guide/architecture)
- [Hermes configuration and terminal backends](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)
- [Hermes security](https://hermes-agent.nousresearch.com/docs/user-guide/security)
- [Hermes context files](https://hermes-agent.nousresearch.com/docs/user-guide/features/context-files)

### 0.2 Prinsip titik tengah

PRD v7.1 mempertahankan kebutuhan yang benar dari versi sebelumnya:

- pekerjaan agent harus dapat diaudit;
- command dan evidence harus dapat diulang;
- manusia mengendalikan risiko tinggi, production, dan pengecualian;
- task kecil tidak boleh selalu menunggu human;
- failure infrastructure tidak boleh disalahartikan sebagai failure kode;
- data sensitif dan credential tidak boleh mengalir bebas ke model atau log;
- fitur baru harus earned by evidence.

PRD v7.1 menghapus atau menunda:

- agent loop custom;
- memory graph atau memory service custom;
- queue, scheduler, dan gateway custom;
- approval engine custom yang menggantikan Hermes;
- dashboard platform sebelum metrik dasar tersedia;
- Neo4j, Graphiti, DBOS, Redis, pgvector, vector database, dan distributed lock;
- parallel worker dan autonomous production deploy.

### 0.3 Disposisi review GLM 5.2, MiniMax M3, dan Qwen 3.8

Ketiga review memiliki satu rekomendasi yang benar: fitur Hermes yang dapat mengubah state, menambah skill, mengirim data ke provider, atau membuat subagent harus masuk ke constrained profile. Namun, beberapa rekomendasi mengulang kompleksitas v6 dengan meminta memory PostgreSQL eksternal sebagai kewajiban. Itu tidak diterapkan karena Hermes sudah memiliki memory internal dan kebutuhan audit v7 sengaja dipenuhi melalui PR, commit, CI check, Evidence Artifact, serta event JSONL.

| Rekomendasi review | Keputusan v7.1 | Alasan |
|---|---|---|
| Jangan gunakan ECC/skill Claude Code di Hermes | Diterapkan | Project skill harus mengikuti format dan lifecycle Hermes; ECC bukan dependency |
| Matikan atau kendalikan memory Hermes | Diperjelas | Memory boleh menjadi hint, tetapi write approval wajib; external provider off; high-risk dapat mematikan memory |
| Buat memory PostgreSQL sebagai source of truth | Ditolak untuk Fase 0 | Menambah service, sync, dan failure mode; audit tetap berada pada PR/CI/artifact |
| Agent-created skill berisiko supply chain | Diterapkan | Skill write approval, guard scan, allowlist, external directory read-only |
| MCP one-click install berisiko bypass registry | Diterapkan | MCP manual allowlist; tidak ada install otomatis pada production profile |
| GEPA/prompt evolution harus dikontrol | Diterapkan secara policy | Fitur prompt optimization eksperimental tidak menjadi production dependency; hanya evaluation profile setelah version dan output dapat direproduksi |
| Trajectory dapat memuat source code | Diterapkan | Trajectory export/RL training off pada worker; bila file tercipta, retention dan redaction berlaku |
| Subagent perlu audit | Diterapkan | Delegation off pada Fase 0; jika kelak diaktifkan, setiap child wajib memiliki task/event/artifact boundary sendiri |
| Multi-platform gateway memperluas attack surface | Diterapkan | CLI saja pada Fase 0; gateway connector tidak dikonfigurasi |
| Nous Portal multi-hop perlu data policy | Diterapkan | Boleh untuk internal pilot; direct provider lebih disukai untuk client-confidential/sensitive |
| Ollama/local model menghapus token cost | Ditunda | Tidak cocok sebagai asumsi server 2 GB; compute cost dan kualitas perlu benchmark terpisah |

## 1. Ringkasan eksekutif

Hustle Studio menggunakan Hermes Agent sebagai coding agent utama pada satu server kecil. Hermes menerima task, membaca context proyek, memodifikasi repository, dan menjalankan tool. Repository menyediakan adapter Bash yang mendefinisikan cara build, test, lint, security scan, dan healthcheck.

Setiap perubahan agentic harus menghasilkan branch dan PR. Verifier CI menjalankan Evidence Contract terhadap commit yang tepat. Evidence Gate menghasilkan `PASS`, `FAIL`, atau `UNKNOWN`. Risk Gate menentukan apakah PR boleh diproses secara autonomous, membutuhkan asynchronous review, atau wajib human approval sebelum merge.

Platform pada Fase 0 bukan aplikasi web besar. Ia adalah kombinasi dari:

- Hermes yang dikonfigurasi secara aman;
- file policy dan context di repository;
- Bash adapter yang idempotent;
- tool Rust/Unix yang dipin;
- GitHub PR dan branch protection;
- CI Evidence Gate;
- Evidence Artifact dan event log;
- runbook manusia.

Tujuan utama bukan membuat agent paling kompleks, melainkan membuat satu workflow yang dapat dijalankan berulang kali, murah, dapat dihentikan, dan dapat dibuktikan hasilnya.

## 2. Konteks, pengguna, dan batasan

### 2.1 Pengguna Fase 1

- **Hasban / owner:** menentukan policy, menyetujui high-risk change, dan mengambil keputusan pengecualian.
- **Delegate reviewer:** mengambil human gate saat owner tidak tersedia dengan scope dan expiry yang jelas.
- **Hermes Agent:** mengerjakan task berdasarkan context dan tool yang diizinkan.
- **Verifier CI:** menjalankan evidence secara independen terhadap commit PR.
- **Reviewer:** menilai desain, acceptance, UX, business risk, dan hasil evidence.
- **Operator:** menjaga server Hermes, provider, token, disk, backup, dan incident response.

### 2.2 Batasan mengikat

- Server awal hanya memiliki RAM 2 GB.
- Model dijalankan melalui provider eksternal; tidak ada local LLM pada server awal.
- Hanya satu repository pilot yang diproses bersamaan.
- Stack repository dapat berbeda: PHP/Laravel, JavaScript/TypeScript, Go, atau monorepo.
- Semua command yang dijalankan Hermes harus memiliki timeout dan working directory yang jelas.
- Server Hermes tidak boleh menyimpan production secret secara default.
- CI adalah source of truth untuk evidence jika local environment berbeda dari runner.
- Production deploy dan perubahan high-risk tetap memiliki human control.

### 2.3 Asumsi awal

- GitHub menjadi source control provider pertama.
- GitHub Actions atau CI setara tersedia untuk verifier.
- Server menggunakan Linux LTS, filesystem lokal, dan systemd.
- Provider LLM mampu menyediakan context window minimal 64K token sesuai kebutuhan Hermes.
- Backup artifact dan event penting dapat disalin ke lokasi berbeda dari server utama.

### 2.4 RACI minimum

| Aktivitas | Hasban | Delegate | Hermes | Verifier CI | Operator |
|---|---|---|---|---|---|
| Menulis code | A | C | R | I | I |
| Menentukan risk tier | A | C | C | I | I |
| Menjalankan evidence | I | I | R lokal | R independen | C |
| Menyetujui medium/high-risk | A | R dalam scope | - | I | I |
| Merge low-risk autonomous | A | C | - | R check | I |
| Merge medium/high-risk | A | R dalam scope | - | R check | I |
| Production deploy | A | R jika didelegasikan | - | C | R |
| Menangani incident | A | R | I | C | R |
| Menjaga provider/token/server | I | I | I | I | R |

## 3. Tujuan dan non-tujuan

### 3.1 Tujuan

1. Mengubah task terdefinisi menjadi perubahan repository yang dapat direview.
2. Menjalankan evidence yang konsisten lintas stack melalui adapter repository.
3. Membuat setiap keputusan merge tertaut ke task, commit, CI run, dan artifact.
4. Menyediakan otonomi untuk task low-risk tanpa menjadikan human bottleneck.
5. Memaksa human gate untuk migration destructive, auth, secret, external exposure, production, dan perubahan high-impact.
6. Menjalankan workflow pada server 2 GB dengan biaya dan maintenance rendah.
7. Menyediakan stop rule jika evidence, provider, quota, permission, atau environment tidak dapat dipercaya.
8. Menghasilkan baseline nyata sebelum membangun komponen tambahan.

### 3.2 Non-tujuan

PRD ini tidak bertujuan untuk:

- membangun agent LLM baru;
- menggantikan Hermes memory, session, skill, gateway, atau tool registry;
- membuat IDE atau chat application baru;
- menjalankan local LLM pada server 2 GB;
- mengaktifkan parallel coding sebagai default;
- menjalankan merge atau deploy production tanpa policy dan approval;
- menjamin kualitas bisnis hanya dari test teknis;
- membuat platform multi-tenant atau government-ready pada fase awal;
- menambahkan service database, queue, atau observability sebelum ada kebutuhan terbukti.

## 4. Prinsip desain

### 4.1 Hermes adalah execution harness, bukan audit source of truth

Hermes boleh menyimpan session, memory, skill, dan konfigurasi internal. Namun, audit workflow harus bergantung pada data yang dapat direkonstruksi dari:

- repository dan commit SHA;
- PR dan review event;
- CI run ID;
- Evidence Manifest dan Evidence Artifact;
- risk decision;
- approval record;
- deployment/incident record bila ada.

Jika memory internal Hermes hilang, project masih harus dapat menjelaskan mengapa PR di-merge berdasarkan artifact dan event workflow.

### 4.2 Bash sebagai adapter, bukan database

Bash cocok untuk command repository dan glue sederhana. Bash tidak boleh menjadi tempat state machine, policy kompleks, atau penyimpanan state yang hanya hidup di shell.

Setiap adapter wajib:

- menggunakan `set -Eeuo pipefail`;
- menerima input dari environment/argument yang terdokumentasi;
- memiliki exit code stabil;
- menghasilkan output machine-readable bila dipanggil oleh verifier;
- memiliki timeout dan cleanup trap;
- tidak mencetak secret;
- tidak melakukan `git push` ke protected branch;
- dapat dijalankan ulang tanpa merusak state.

### 4.3 Evidence bukan jaminan produk

Evidence membuktikan command tertentu berhasil pada commit dan environment tertentu. Evidence tidak membuktikan seluruh acceptance, UX, security, atau business rule. Reviewer tetap diperlukan berdasarkan risk tier.

### 4.4 Fail closed pada ketidakpastian material

`UNKNOWN` bukan `PASS`. Jika artifact hilang, commit mismatch, provider expired, scanner tidak tersedia, acceptance mapping tidak lengkap, atau healthcheck tidak dapat dibuktikan, merge ditahan sampai ada recovery atau keputusan manusia yang tercatat.

### 4.5 Serial sampai data membuktikan kebutuhan parallel

Satu task aktif dan satu evidence run aktif adalah default. Parallelisme hanya boleh dipilotkan setelah baseline menunjukkan throughput bersih meningkat tanpa menaikkan conflict, escape, biaya, atau maintenance secara material.

## 5. Arsitektur dan boundary tanggung jawab

### 5.1 Komponen

| Komponen | Tanggung jawab | Bukan tanggung jawab |
|---|---|---|
| Hermes Agent | Memahami task, membaca context, mengedit code, menjalankan tool yang diizinkan | Menentukan bahwa test PASS secara independen, mengubah branch protection, menyetujui PR sendiri |
| `AGENTS.md`/`.hermes.md` | Instruksi proyek, workflow, command, konvensi, batasan | Menjadi audit database |
| Project skill | Prosedur berulang untuk Hermes | Menggantikan policy enforcement CI |
| Bash adapter | Build/test/lint/healthcheck/security command | Menyimpan state workflow jangka panjang |
| Rust/Unix tools | Scanning, searching, hashing, parsing, dan utility yang sudah tersedia | Menjadi orchestrator baru tanpa kebutuhan |
| Bun helper | Logic terstruktur yang tidak layak ditulis dalam Bash | Menjadi service permanen secara default |
| GitHub | Branch, PR, review, checks, merge protection, commit identity | Menyimpan semua raw log untuk retention jangka panjang |
| CI Verifier | Menjalankan evidence secara independen, menghasilkan artifact dan check | Mengubah source code atau approve PR |
| Audit storage | Menyimpan artifact merge/deploy dan event penting | Menjadi working directory agent |
| Human reviewer | Menilai risiko, acceptance, design, exception, dan production | Menyetujui setiap task low-risk tanpa alasan |

### 5.2 Alur kanonik

```text
Issue/task
   ↓
Hermes membaca AGENTS.md + project skill + task context
   ↓
Hermes bekerja pada branch/worktree serial
   ↓
Bash adapter menjalankan local evidence bila dapat direplikasi
   ↓
PR dengan task ID, risk label, origin, acceptance map
   ↓
CI Verifier menjalankan Evidence Contract pada commit PR
   ↓
Risk Gate + reviewer policy
   ↓
Merge manual atau autonomous low-risk sesuai policy
   ↓
Deploy/monitoring/rollback dengan human control
```

### 5.3 Model state workflow

State ini adalah state task/PR workflow, bukan state internal Hermes:

```text
proposed
  → ready
  → in_progress
  → evidence_pending
  → review_required
  → verified
  → merge_ready
  → merged
  → deploy_pending
  → deployed
  → monitoring
```

State failure:

```text
in_progress/evidence_pending
  → failed
  → retrying_code
  → retrying_infra
  → unknown
  → escalated

monitoring
  → rollback_pending
  → rolled_back
  → incident_open
  → forward_fixed
```

Setiap transition yang penting harus dapat dibuktikan melalui PR event, CI run, artifact, approval, deployment event, atau incident event. Tidak perlu membuat custom scheduler hanya untuk menyimpan state ini.

### 5.4 Deployment state

`reverted` adalah outcome deployment/PR, bukan state coding task. Minimal deployment record:

```json
{
  "deploy_id": "DEP-123",
  "project_id": "pilot-repo",
  "pr_number": 42,
  "commit_sha": "sha256-or-git-sha",
  "environment": "staging|production",
  "state": "deploy_pending|deployed|monitoring|rollback_pending|rolled_back|incident_open|forward_fixed",
  "actor": "human-or-service",
  "approval_ref": "APR-123",
  "timestamp": "2026-08-02T00:00:00Z",
  "incident_ref": null,
  "idempotency_key": "..."
}
```

## 6. Hermes runtime contract

### 6.1 Installation and version pin

Fase 0 menggunakan installer resmi Hermes pada Linux. Setelah instalasi:

1. jalankan `hermes doctor`;
2. pilih provider dengan `hermes model` atau `hermes setup --portal`;
3. pin versi Hermes yang lulus smoke test;
4. catat versi, model, provider, dan konfigurasi pada repo fact sheet;
5. jangan menjalankan update otomatis pada production workflow.

Upgrade Hermes harus mengikuti self-test, fixture task, dan rollback path. `latest` tidak boleh menjadi dependency production yang tidak terdokumentasi.

### 6.2 Context files

Repository memiliki satu context file utama. Pilihan default adalah `AGENTS.md`; `.hermes.md` hanya digunakan jika memang diperlukan dan harus menggantikan, bukan menduplikasi, aturan utama.

Isi minimum:

- tujuan repository;
- struktur direktori;
- stack dan runtime version;
- command build/test/lint;
- Evidence Contract adapter;
- aturan branch/PR;
- high-risk paths;
- secret dan data classification;
- file yang tidak boleh disentuh;
- aturan bahwa Hermes tidak boleh merge/deploy sendiri;
- Definition of Done;
- cara mengeskalasi `UNKNOWN`.

PRD lengkap disimpan sebagai file terpisah dan dirujuk dari context file agar system prompt tidak membengkak.

### 6.3 Hermes skills

Skill project digunakan untuk prosedur berulang seperti:

- membuat task plan;
- menjalankan evidence lokal;
- menyiapkan PR;
- membaca Evidence Artifact;
- menangani reviewer feedback;
- membuat incident report.

Skill harus:

- memiliki scope jelas;
- tidak mengandung credential;
- tidak memberi Hermes hak merge/deploy;
- menyebutkan command yang valid;
- memiliki stop condition;
- memiliki self-test fixture;
- disimpan dan direview sebagai code/config.

Skill tidak boleh menjadi satu-satunya enforcement. Jika aturan benar-benar wajib, aturan tersebut juga harus diterapkan oleh branch protection, CI, atau script verifier.

### 6.4 Memory, session, gateway, dan cron Hermes

Fitur berikut dianggap sudah disediakan Hermes dan tidak dibangun ulang:

- persistent session;
- memory dan recall;
- skill management;
- messaging gateway;
- scheduled automation;
- tool registry dan dispatch;
- command approval.

Aturan proyek:

- memory Hermes adalah konteks/hint, bukan source of truth audit; Fase 0 memakai built-in memory tanpa external provider dan dengan write approval;
- session Hermes tidak menggantikan task ID dan PR;
- gateway connector tidak dikonfigurasi pada Fase 0;
- cron Hermes tidak dipakai untuk merge/deploy; jika dipakai untuk read-only health check, `cron_mode` tetap deny untuk command berbahaya;
- command berbahaya pada cron default-nya ditolak;
- skill write dan memory write memerlukan approval;
- delegation/subagent dimatikan pada constrained worker;
- setiap pekerjaan penting tetap menghasilkan branch/PR/artifact.

Jika memory Hermes unavailable, low-risk task boleh lanjut dengan warning. Medium hanya boleh lanjut jika history tidak dibutuhkan. High-risk, sensitive, dan government task harus block/escalate.

### 6.5 Terminal backend dan isolasi

Pilihan bertahap:

| Kondisi | Backend |
|---|---|
| Pilot private repo, low-risk, user hadir | `local` pada user Linux khusus |
| Kode belum dipercaya atau dependency berisiko | `docker` atau CI runner |
| Membutuhkan mesin berbeda | `ssh` dengan user dan directory terbatas |
| High-risk/production | CI atau environment terisolasi dengan approval |

`local` tidak dianggap sandbox. Server Hermes tidak boleh memiliki production credential pada environment yang dipakai Hermes. Docker image harus dipin, tidak dijalankan sebagai privileged container, dan tidak boleh memiliki akses Docker socket host tanpa alasan tertulis.

### 6.6 Provider dan model

Fase 0 hanya memilih satu provider utama. Fallback provider tidak diaktifkan sebelum provider utama stabil, karena routing otomatis dapat menyulitkan reproduksi biaya, perilaku, dan data residency.

Provider registry minimal mencatat:

```yaml
provider: example-provider
model: example-model
config_version: "..."
context_window: 64000
data_class: internal
region: "..."
contract_status: approved|pending|expired|revoked
owner: "..."
review_date: "..."
```

Provider expired, region mismatch, contract tidak jelas, atau model context di bawah minimum menghasilkan `BLOCKED`, bukan fallback diam-diam.

Nous Portal dapat digunakan untuk internal pilot bila account, data class, dan retention telah disetujui. Karena Portal dapat menjadi gateway ke provider/model lain, source code client-confidential, PII, financial, sensitive, dan government tidak boleh dikirim melalui Portal tanpa review kontrak, region, retention, training-use, dan subprocessor. Untuk class tersebut, direct provider endpoint yang approved atau local/isolated inference menjadi pilihan yang lebih mudah diaudit.

### 6.7 Resource policy server 2 GB

Server 2 GB hanya menjalankan satu Hermes session aktif dan tidak menjalankan local LLM. Evidence build berat diserahkan ke CI bila memungkinkan.

Baseline operasional:

- user Linux khusus, bukan root;
- satu workspace aktif;
- satu task agentic aktif;
- satu evidence run lokal aktif;
- tidak ada subagent paralel;
- tidak ada browser/voice/image tool kecuali dibutuhkan;
- timeout command default dan memory limit ditetapkan;
- disk usage, swap, CPU load, dan process count dimonitor;
- artifact lama dihapus sesuai retention setelah dipastikan tidak berada dalam legal hold.

Angka memory final harus diukur pada server pilot. Jangan menganggap swap sebagai kapasitas normal. Jika build/test repository membutuhkan memory lebih besar daripada kapasitas server, local evidence boleh dilewati dengan mode `ci_only` dan CI menjadi source of truth.

### 6.8 Hermes constrained profile

Fase 0 menggunakan profile Hermes yang sengaja minimal. Project menyimpan desired policy sebagai `.agent/hermes-policy.yaml`; file ini bukan pengganti `~/.hermes/config.yaml`, tetapi contract yang diverifikasi saat startup dan self-test.

```yaml
profile: constrained-worker-v1
harness: hermes-agent
execution:
  serial_only: true
  max_active_tasks: 1
  max_active_subagents: 0
memory:
  mode: context_only # off | context_only; never audit_source
  external_provider: disabled
  write_approval: required
skills:
  source: bundled_allowlist_and_project
  agent_created_write: approval_required
  external_directories: read_only
delegation:
  enabled: false
gateway:
  enabled: false
mcp:
  mode: manual_allowlist
trajectory:
  export: disabled
prompt_optimization:
  mode: disabled
tools:
  terminal: enabled
  file_operations: enabled
  browser: disabled
  voice: disabled
  image_generation: disabled
  broad_web_search: disabled
```

Implementasi config mengikuti versi Hermes yang dipin. Nama field pada policy project tidak boleh diasumsikan otomatis sama dengan nama field Hermes; operator wajib memetakan dan menguji setiap field saat instalasi.

Untuk versi Hermes yang mendukung field berikut, reference mapping awalnya adalah:

```yaml
approvals:
  mode: smart
  timeout: 300
  cron_mode: deny
memory:
  memory_enabled: true
  user_profile_enabled: false
  write_approval: true
skills:
  write_approval: true
  guard_agent_created: true
delegation:
  orchestrator_enabled: false
  max_concurrent_children: 1
terminal:
  timeout: 180
  env_passthrough: []
```

`memory_enabled: false` dipakai untuk profile high-risk/sensitive. Toolset delegation, gateway, trajectory, dan external memory provider harus tidak aktif meskipun field pada versi tertentu memiliki nama berbeda. Self-test memeriksa perilaku aktual, bukan hanya keberadaan YAML.

#### Memory mode

- `context_only`: built-in `MEMORY.md`/`USER.md` boleh membantu konteks, tetapi tidak boleh menjadi alasan tunggal untuk policy, risk tier, approval, merge, atau deployment. `memory.write_approval` wajib aktif.
- `off`: dipakai untuk high-risk, sensitive, government, dan task yang membutuhkan reproducibility maksimum. Context harus berasal dari repository, task, PR, ADR, dan artifact.
- External memory provider seperti Honcho, Mem0, OpenViking, atau provider lain tidak dipakai pada Fase 0. Ia baru dapat dipilih melalui provider review, data-flow review, dan owner retention.

Jika versi Hermes yang dipakai tidak dapat menerapkan mode atau write approval secara dapat diverifikasi, profile tersebut tidak boleh dipakai untuk automated low-risk merge; gunakan `off` atau eskalasi human.

#### Skill dan MCP policy

Bundled skill tidak otomatis berarti approved untuk setiap project. Bila versi Hermes mendukung blank-slate profile, gunakan itu lalu aktifkan hanya skill yang diperlukan. Jika tidak, skill yang aktif harus masuk allowlist dengan source, version, owner, required toolset, required environment variable, dan review date. Skill Hub install dan agent-created skill tanpa approval dilarang. Skill write approval dan guard scan harus aktif. External skill directory harus read-only bagi proses Hermes.

MCP server hanya boleh ditambahkan secara manual melalui konfigurasi yang direview. Catalog/one-click install, remote URL tanpa checksum, dan MCP yang memiliki credential broad-scope diblokir. Setiap MCP memiliki project scope, data class, egress policy, timeout, owner, dan removal path.

#### Delegation, gateway, trajectory, dan prompt optimization

- Delegation/subagent dimatikan pada Fase 0. `orchestrator_enabled: false` menjadi defense-in-depth, tetapi toolset delegation juga harus tidak tersedia dalam profile yang digunakan.
- Gateway Telegram, Discord, Slack, WhatsApp, Email, dan connector lain tidak dikonfigurasi pada pilot. Interface resmi Fase 0 adalah CLI/terminal dan GitHub.
- Trajectory export dan RL/training pipeline dimatikan. File trajectory tidak boleh masuk artifact atau dikirim ke provider lain. Jika versi Hermes tetap menghasilkan file trajectory, path, retention, redaction, dan deletion harus diuji sebelum production profile disetujui.
- Fitur prompt evolution/optimization eksperimental tidak digunakan pada production worker. Evaluation run harus memakai profile terpisah, diberi label, dan tidak boleh mengubah prompt/policy production secara otomatis.

### 6.9 Token-efficient Skills, MCP, dan CLI

Penghematan token diperlakukan sebagai masalah loading architecture, bukan sekadar memendekkan prompt. Fase 0 memakai keputusan berikut:

| Kebutuhan | Pilihan pertama | Alasan |
|---|---|---|
| Prosedur berulang | Hermes project skill | Metadata singkat; detail dimuat saat relevan |
| Command repository satu kali/berulang sederhana | Bash/CLI langsung | Tidak menambah tool schema dan server |
| Akses sistem eksternal dengan kontrak terstruktur | MCP manual allowlist | Cocok untuk action/query yang reusable |
| Data besar untuk dibaca | Resource/file reference/pagination | Model menerima excerpt atau ringkasan, bukan dump |
| Transformasi deterministik | Script Bash/Rust/Bun | Filtering dilakukan di luar model |
| Workflow API multi-step dengan katalog besar | Code Mode/evaluation terpisah | Belum layak untuk Fase 0 server 2 GB |

#### Skill budget dan progressive disclosure

Project skill mengikuti Agent Skills convention yang didukung Hermes, tetapi target berikut adalah budget engineering, bukan jaminan bahwa setiap versi Hermes memuat file dengan cara yang identik:

- `SKILL.md` memiliki frontmatter `name` dan `description` yang singkat;
- description menjelaskan apa, kapan dipakai, dan kapan tidak dipakai;
- target description 50–100 kata, dengan pembeda jelas antar skill;
- body idealnya di bawah 500 baris; detail panjang dipisah ke `references/`;
- referensi langsung satu level dari `SKILL.md`, bukan rantai referensi dalam;
- script deterministik berada di `scripts/`, bukan ditulis ulang sebagai prosa panjang;
- template dan contoh besar berada di `templates/` atau `examples/` dan dibaca hanya saat dibutuhkan;
- setiap skill memiliki version, owner, scope, required toolset, required environment variables, dan review date;
- skill memiliki positive trigger, negative trigger, output contract, dan stop condition;
- policy global tidak diduplikasi ke semua skill.

Skill tidak boleh memasukkan seluruh PRD, log, source code, atau dokumentasi stack ke body utama. Hermes hanya perlu ringkasan aturan dan path ke resource yang diperlukan.

#### MCP tool budget dan output contract

MCP bukan default pengganti Bash. Setiap MCP server yang diaktifkan harus memenuhi:

- satu tool memiliki satu outcome yang jelas;
- nama tool pendek dan verb-object;
- deskripsi ringkas: fungsi, kapan dipakai, dan output utama;
- input schema minimal dengan enum/constraint bila nilai terbatas;
- annotations read-only/destructive/idempotent/open-world bila didukung;
- output terstruktur dan hanya mengembalikan field yang diperlukan;
- summary sebelum detail, pagination/cursor untuk daftar panjang;
- server-side filtering/agregasi sebelum hasil masuk konteks model;
- error singkat, actionable, dan bebas secret/stack trace mentah;
- response byte/token maksimum dan timeout;
- owner, version, project scope, data class, egress policy, dan removal path.

Target awal adalah 5–15 tool per server; lebih dari 20 menjadi trigger review, bukan hard failure. Tool yang jarang dipakai lebih baik tetap menjadi CLI/skill daripada selalu masuk tool catalog.

`outputSchema` dan structured output dipakai bila didukung MCP client/server. Jika Hermes/provider tidak mengekspos `defer_loading`, Tool Search, atau output schema dengan cara yang dapat diverifikasi, fitur tersebut tidak boleh diasumsikan tersedia. Nama konfigurasi yang berasal dari Claude Code atau Anthropic tidak boleh langsung disalin ke Hermes.

#### Cache dan loading stability

Jika provider mendukung prompt caching, prefix stabil berisi identity, policy, context metadata, skill metadata, dan tool catalog yang dipin. Input task, timestamp, PR number, serta hasil tool terbaru diletakkan di bagian dinamis. Config, skill, atau MCP tidak diubah di tengah sesi produksi tanpa memulai session baru dan mencatat invalidation.

Cache hit rate hanya diukur bila provider menyediakannya. Jika tidak tersedia, gunakan proxy metrics: input tokens, output tokens, tool count, response bytes, error rate, retry, latency, dan cost per task.

#### Code Mode dan router

Code Mode/router tidak menjadi dependency Fase 0. Ia baru dievaluasi jika catalog mencapai lebih dari 20 tool, workflow eksternal membutuhkan minimal 4–6 langkah berurutan, atau output filtering di server tidak lagi cukup. Evaluation wajib mengukur token, latency, success rate, sandbox escape risk, dan maintenance cost. Klaim penghematan 80–99% dari framework lain tidak dianggap baseline untuk Hermes.

## 7. Evidence Gate Contract

### 7.1 Tujuan

Evidence Gate menjawab pertanyaan terbatas:

> Apakah command wajib pada commit ini berhasil di environment yang didefinisikan, dengan log dan metadata yang dapat diverifikasi?

Evidence Gate tidak menilai apakah produk sudah benar secara bisnis.

### 7.2 Kontrak adapter minimum

Setiap repository menyediakan command berikut, melalui Makefile, script, atau command adapter lain:

```text
evidence.setup
evidence.build
evidence.test
evidence.lint
evidence.security
evidence.healthcheck       # conditional jika service eksternal diperlukan
evidence.cleanup
```

Adapter minimal boleh berupa Bash:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

run_step() {
  local name="$1"
  shift
  timeout "${EVIDENCE_TIMEOUT_SECONDS:-900}" "$@"
}

run_step evidence.test ./vendor/bin/phpunit
```

Implementasi nyata harus mencatat nama command, exit code, durasi, stdout/stderr path, environment mode, dan versi tool.

### 7.3 Evidence manifest

`.agent/evidence.yaml` minimal:

```yaml
contract_version: evidence-v1
repository: pilot-repo
runtime: php-8.3
environment_mode: ci_only # exact | approximate | hybrid | ci_only
build_mode: required # required | no_build | no_op
services:
  required: false
commands:
  setup: ./scripts/evidence/setup.sh
  build: ./scripts/evidence/build.sh
  test: ./scripts/evidence/test.sh
  lint: ./scripts/evidence/lint.sh
  security: ./scripts/evidence/security.sh
  healthcheck: ./scripts/evidence/healthcheck.sh
timeouts_seconds:
  setup: 300
  build: 900
  test: 1800
  lint: 600
  security: 900
  healthcheck: 300
acceptance_evidence_map: .agent/acceptance-evidence.yaml
```

`environment_mode` wajib jujur:

- `exact`: local dan CI image/runtime setara;
- `approximate`: local membantu tetapi CI tetap source of truth;
- `hybrid`: sebagian service memakai adapter lokal, sebagian CI;
- `ci_only`: local evidence tidak dianggap representatif.

### 7.4 Acceptance-to-evidence mapping

Setiap task memiliki mapping:

```yaml
task_id: TASK-123
acceptance:
  - id: AC-1
    statement: "User dapat mengunduh report"
    evidence:
      - test: tests/report_download_test.php
        type: automated
  - id: AC-2
    statement: "Permission report mengikuti role"
    evidence:
      - test: tests/report_permission_test.php
        type: automated
  - id: AC-3
    statement: "Copy UX jelas pada mobile"
    evidence:
      - type: human_only
        reviewer: "..."
        approval_ref: "..."
```

`human_only` wajib memiliki reviewer dan approval. Mapping yang kosong, tidak konsisten dengan acceptance, atau menyatakan `human_only` tanpa approval menolak automated `PASS`.

### 7.5 Evidence profiles

| Profile | Penggunaan | Command minimum |
|---|---|---|
| `smoke` | Feedback cepat lokal | setup, targeted test |
| `standard` | PR low/medium-risk | setup, build, test, lint, security |
| `full` | high-risk, migration, release | semua command + healthcheck jika perlu |
| `ci_only` | Environment lokal tidak representatif | tidak menjalankan local PASS sebagai keputusan |

Skip hanya sah jika:

- command memang tidak relevan dan manifest menjelaskannya;
- `no_op_reason_code` tersedia;
- policy version cocok;
- reviewer/risk gate menerima skip tersebut.

Skip test karena flaky tanpa quarantine policy adalah `FAIL`, bukan PASS.

### 7.6 PASS, FAIL, UNKNOWN

- **PASS:** command wajib exit code 0, artifact lengkap, commit sesuai, mapping tersedia, scanner lulus, dan tidak ada policy violation.
- **FAIL:** command wajib gagal, test gagal, scanner menemukan issue, atau artifact melanggar contract.
- **UNKNOWN:** hasil tidak dapat dibuktikan karena runner crash, timeout infra, healthcheck tidak tersedia, artifact hilang, provider invalid, log terpotong, atau hash mismatch.

`UNKNOWN` memblokir merge. Ia tidak otomatis menghabiskan code retry. Scheduler/worker custom tidak diperlukan; status disimpan pada PR check, artifact, dan event record.

### 7.7 Evidence Artifact

```json
{
  "artifact_version": "evidence-v1",
  "task_id": "TASK-123",
  "pr_number": 42,
  "base_sha": "...",
  "head_sha": "...",
  "commit_sha": "...",
  "ci_run_id": "...",
  "profile": "standard",
  "risk_tier": "low",
  "policy_version": "policy-v7",
  "environment": {
    "mode": "ci_only",
    "runner_image_digest": "sha256:...",
    "runtime_versions": {"php": "8.3.x", "node": "..."}
  },
  "commands": [
    {"name": "setup", "exit_code": 0, "duration_ms": 1000, "log_hash": "..."},
    {"name": "build", "exit_code": 0, "duration_ms": 1000, "log_hash": "..."},
    {"name": "test", "exit_code": 0, "duration_ms": 1000, "log_hash": "..."},
    {"name": "lint", "exit_code": 0, "duration_ms": 1000, "log_hash": "..."},
    {"name": "security", "exit_code": 0, "duration_ms": 1000, "log_hash": "..."}
  ],
  "required_commands": ["setup", "build", "test", "lint", "security"],
  "skipped_commands": [],
  "skip_reasons": [],
  "acceptance_map_ref": ".agent/acceptance-evidence.yaml",
  "quality_flags": [],
  "secret_scan_status": "pass",
  "pii_scan_status": "pass",
  "redaction_status": "pass",
  "artifact_hash": "sha256:...",
  "verifier_decision": "PASS",
  "retention_expiry": "...",
  "artifact_uri": "..."
}
```

Artifact yang menjadi dasar merge/deploy disalin ke audit storage approved. Pointer provider CI saja tidak cukup. Retention minimum adalah 1 tahun atau mengikuti kontrak/regulasi yang lebih ketat. `legal_hold=true` menahan deletion.

Fase 1 tidak mewajibkan attestation cryptographic kompleks jika CI artifact, commit SHA, run ID, dan hash dapat diverifikasi. HMAC/in-toto menjadi enhancement setelah kebutuhan terbukti dan key management sudah memiliki owner.

### 7.8 Redaction, secret, dan PII

Redaction dilakukan sebelum log/artifact disimpan ke lokasi yang tidak berhak melihat data mentah.

Minimal ada tiga pemeriksaan:

1. secret scanner untuk token, credential, private key, dan environment secret;
2. PII scanner sesuai data classification repository;
3. structural scrubber untuk header, URL query, environment variable, dan payload fixture.

Aturan status:

- `fail`: temuan belum ditangani; Evidence ditolak;
- `unavailable`: hasil tidak dapat dibuktikan; status `UNKNOWN`;
- false positive: hanya melalui scoped allowlist dengan owner dan expiry;
- raw secret/PII tidak boleh masuk event log, memory Hermes, preview, atau ticket;
- fixture sintetis wajib menguji secret, email/phone, dan identifier sensitif.

### 7.9 Flaky test dan infrastructure

- Failure yang PASS pada rerun tetap dicatat sebagai `flaky_test` atau `flaky_infra`.
- Dua kejadian pada test yang sama dalam 10 run atau tiga dalam 20 run menjadi `quarantine_candidate`.
- Quarantine memiliki owner, alasan, impact, dan expiry maksimum 7 hari.
- Test critical path tidak boleh silently skipped.
- Dua `UNKNOWN` pada runner/service yang sama dalam lima run memicu infra incident.
- Flaky infra tidak menghabiskan code retry, tetapi tetap memengaruhi quality dan CI budget.

## 8. Risk classification dan human control

### 8.1 High-risk flags

PR minimal menjadi high-risk jika menyentuh:

- authentication, authorization, permission, session, atau identity;
- migration destructive atau perubahan data irreversible;
- production config, deployment, rollback, atau secret;
- public endpoint, external integration, webhook, atau egress;
- payment, payroll, financial calculation, atau audit trail;
- PII, data residency, government constraint, atau client contract;
- dependency runtime baru yang belum dipin;
- shared hotspot pada schema, routing, auth, deployment, atau public contract;
- perubahan besar di atas `max(8, ceil(1.4 × median changed files))` dari minimal 20 PR relevan;
- Evidence atau acceptance mapping yang tidak lengkap;
- provider, runner, toolchain, atau policy berubah.

### 8.2 Tier dan autonomy

| Tier | Contoh | Mode |
|---|---|---|
| Low | typo, test terisolasi, dokumentasi, refactor lokal kecil | autonomous setelah Evidence PASS |
| Medium | fitur satu bounded context, endpoint internal, perubahan beberapa file | asynchronous human review sebelum merge |
| High | auth, migration, secret, production, public exposure, sensitive data | human approval wajib sebelum merge/deploy |

Emergency adalah mode incident, bukan risk tier. Emergency tetap harus memiliki incident ID, scope, approver, rollback plan, dan follow-up evidence.

### 8.3 Risk label enforcement

Risk label final ditulis oleh mekanisme CI atau GitHub App/action yang disetujui, bukan oleh Hermes. Hermes boleh mengusulkan label tetapi tidak boleh menurunkannya.

Jika label hilang, actor tidak valid, atau hasil risk check `unknown`, PR diblokir.

### 8.4 Approval record

Approval harus terikat pada:

- project/repository;
- PR number;
- head SHA;
- risk decision;
- scope approval;
- approver identity;
- timestamp;
- expiry.

Approval berlaku untuk satu head SHA atau maksimum satu jam. Push baru, perubahan risk tier, atau Evidence rerun yang mengubah hasil menginvalidasi approval.

### 8.5 Permission boundary

| Identity | Boleh | Tidak boleh |
|---|---|---|
| Hermes token | read issue/PR, create branch, push feature branch, comment | approve sendiri, merge protected branch, deploy production |
| CI Verifier | checkout commit, run evidence, publish check/artifact | push source code, approve PR |
| Reviewer | review, approve sesuai scope | menghapus required check tanpa policy |
| Merge automation | merge low-risk sesuai branch policy | merge medium/high-risk |
| Deploy identity | deploy sesuai environment approval | bypass approval tanpa emergency procedure |

## 9. Retry, budget, dan checkpoint

### 9.1 Retry budget

Setiap task memiliki dua pool terpisah:

- maksimum 3 retry untuk masalah kode;
- maksimum 1 recovery untuk `UNKNOWN` infrastructure.

Jika recovery infra habis, task menjadi `escalated` tanpa memakan code retry. Retry tidak boleh mengulang command yang sama tanpa informasi baru.

### 9.2 Cost budget

Budget awal per task:

| Tier | Target model cost | Hard cap |
|---|---:|---:|
| Low | 1.0 unit | 1.5 unit |
| Medium | 2.0 unit | 3.0 unit |
| High | 3.5 unit | 5.0 unit |

Angka ini alert baseline. Actual cost dikalibrasi setelah minimal 30 task. Hard cap tetap berlaku selama kalibrasi.

### 9.3 Checkpoint

Checkpoint Fase 0 menggunakan mekanisme yang sudah tersedia:

- Hermes session resume;
- Git commit;
- feature branch;
- PR comment/check;
- Evidence Artifact;
- task log/event JSONL.

Custom durable orchestrator baru dipertimbangkan bila restart/replay manual terbukti menjadi bottleneck material dalam minimal 30 task.

### 9.4 CI quota

Threshold:

- 70%: warning;
- 80%: owner notification dan optimasi;
- 90%: freeze task normal non-urgent;
- 100%: task normal blocked.

Low-risk boleh melakukan precheck murah tetapi tidak boleh mendapat full evidence/merge jika quota tidak dapat dibuktikan. Medium/high blocked kecuali incident emergency yang memiliki reserve atau fallback runner.

Queue akibat evidence slot penuh bukan `UNKNOWN` dan tidak boleh menghabiskan retry.

## 10. Source control, CI, merge, dan deploy

### 10.1 Source control

- Semua perubahan melalui branch dan PR.
- `main` protected dan tidak dapat diedit langsung.
- Hermes hanya boleh push feature branch.
- Force-push setelah Evidence run menginvalidasi run dan approval.
- PR wajib mencantumkan task ID, origin, risk label, acceptance mapping, dan Evidence profile.

### 10.2 Origin

Nilai wajib:

- `agent`: perubahan dibuat Hermes dan tidak ada perubahan manual setelahnya;
- `human`: perubahan dibuat manusia;
- `mixed`: Hermes dan manusia sama-sama mengubah branch.

`origin=mixed` tetap masuk audit, tetapi harus memiliki human intervention flag dan tidak boleh disamakan dengan autonomous completion.

### 10.3 Merge

- Low-risk dapat di-merge automation setelah required checks dan policy PASS.
- Medium membutuhkan asynchronous human approval.
- High membutuhkan human approval eksplisit.
- Batch low-risk maksimum 3 PR dengan rollback pointer per PR.
- Satu artifact atau risk check berubah membatalkan batch.

### 10.4 Preview dan monitoring

Preview memiliki TTL, noindex, access control, dan cleanup. Monitoring minimal mencakup:

- process health;
- dependency health;
- endpoint health;
- synthetic critical flow/job;
- error rate;
- p95 latency;
- disk, memory, dan queue health bila ada.

Rollback manual Fase 1 memiliki target RTO maksimum 30 menit pada support window. Drill rollback dilakukan sebelum production pertama dan minimal quarterly setelahnya.

### 10.5 Migration/data safety

- Expand/contract untuk perubahan yang dapat dilakukan bertahap.
- Compatibility window standar 7 hari.
- Sensitive/government compatibility window 14 hari atau sesuai kontrak.
- Destructive migration wajib human approval, backup/PITR tervalidasi, dan staging drill.
- Backfill harus resumable dan idempotent.
- Migration irreversible wajib memiliki restore plan atau forward-fix plan.

### 10.6 Incident dan after-hours

Incident record minimal memiliki incident ID, severity, commander, timeline, impact, containment, rollback/forward-fix decision, dan follow-up evidence.

- P0 acknowledge maksimum 15 menit pada support window.
- Containment target maksimum 30 menit.
- Postmortem maksimum 2 hari kerja.
- Reviewer postmortem berbeda dari incident commander jika memungkinkan.
- P0 after-hours dapat memakai break-glass dengan expiry dan follow-up review.

Repo fact sheet wajib mencatat timezone, support window, on-call, delegate, dan deploy window. Low-risk deploy outside window hanya boleh jika monitoring dan on-call terbukti.

## 11. Security, data, dan legal

### 11.1 Klasifikasi proyek

| Kelas | Contoh | Aturan |
|---|---|---|
| Internal | tool internal, synthetic data | provider approved, secret scan, access control |
| Client confidential | source client, business logic, PII terbatas | contract/residency/provider review, no broad sharing |
| Sensitive | financial, identity, health, security | human gate, restricted provider, audit retention |
| Government | data/regulatory contract pemerintah | tidak masuk pilot tanpa residency, contract, RTO/RPO, dan threat model khusus |

### 11.2 Hermes secrets

Hermes memisahkan config normal dan secret. Operator wajib:

- membatasi permission file secret;
- tidak mencetak `~/.hermes/.env` atau OAuth credential;
- tidak meneruskan seluruh environment ke terminal backend;
- memakai env passthrough allowlist;
- melakukan rotation dan revocation;
- menyimpan backup credential secara terpisah dan terenkripsi.

### 11.3 Threat model minimum

| Threat | Control |
|---|---|
| Prompt injection pada Issue/PR/code | Treat source sebagai untrusted data; Hermes tidak mengikuti instruksi yang bertentangan dengan AGENTS/policy |
| Hermes membaca production secret | Dedicated user, no production secret, env allowlist |
| Hermes self-approve/self-merge | Token separation, branch protection, approval actor check |
| Local backend tidak terisolasi | Gunakan Docker/CI untuk kode tidak dipercaya/high-risk |
| Evidence dimanipulasi | Commit SHA, CI run ID, hash, immutable audit copy |
| Memory Hermes menjadi policy salah | Memory hanya hint; policy berasal dari repo/ADR/PR approval |
| Cross-project leakage | Satu workspace, project allowlist, tidak mencampur context atau credential |
| Supply-chain tool | Version pin, approved tool list, checksum/review, update test |
| Artifact/log bocor | Secret/PII scanner, redaction, restricted storage, legal hold |
| Server compromise | Non-root, firewall, patching, SSH restriction, backup off-host |

### 11.4 Dependency dan scanner

Tool dapat memakai tool existing yang sudah tersedia. Minimal scope:

- dependency vulnerability scanner;
- secret scanner;
- static analysis sesuai stack;
- license/dependency attribution bila code eksternal digunakan;
- human security review untuk auth, permission, migration, external exposure, dan high-risk.

Nama tool tidak dipaksakan oleh PRD. Tool dipilih berdasarkan repo fact sheet, availability, false-positive profile, dan ownership.

### 11.5 Legal/IP

Repo fact sheet mencatat license policy, ownership/IP clause, third-party code policy, dan apakah generated code dari provider diizinkan kontrak. Jika contract/IP status tidak jelas, branch private boleh dikerjakan tetapi tidak boleh merge/deploy sebelum keputusan tertulis.

## 12. Workflow operasional

### 12.1 Definition of Ready untuk task

Task harus memiliki:

- tujuan dan non-goal;
- acceptance criteria;
- task ID;
- repository dan branch target;
- data classification;
- expected risk tier atau permission untuk recalculation;
- dependencies;
- acceptance-to-evidence mapping;
- apakah membutuhkan human-only evidence;
- rollback/forward-fix expectation bila relevan.

Hermes harus berhenti dan meminta klarifikasi jika acceptance bertentangan, dependency tidak jelas, atau scope menyentuh high-risk path tanpa owner.

### 12.2 Instruksi kerja Hermes

Urutan standar:

1. baca `AGENTS.md`, PRD, dan task;
2. buat plan singkat dan daftar file yang diperkirakan berubah;
3. cek risk flags dan dependencies;
4. implementasi serial pada branch;
5. jalankan targeted smoke evidence;
6. jalankan profile sesuai tier;
7. update acceptance mapping;
8. buat commit yang dapat dijelaskan;
9. buka/update PR;
10. tunggu CI verifier dan review;
11. jangan merge/deploy tanpa policy yang sesuai.

### 12.3 PR template minimum

```markdown
## Task
- Task ID:
- Summary:
- Origin: agent | human | mixed

## Risk
- Proposed tier:
- Risk flags:
- Changed hotspots:

## Acceptance
- [ ] AC-1: ...
- [ ] AC-2: ...
- Mapping: `.agent/acceptance-evidence.yaml`

## Evidence
- Local mode: exact | approximate | hybrid | ci_only
- Profile:
- Commands:
- CI run:
- Result: PASS | FAIL | UNKNOWN

## Human-only checks
- Reviewer:
- Approval reference:

## Rollback
- Revert/forward-fix plan:
```

### 12.4 Reviewer negatif

Jika reviewer memberi rekomendasi negatif:

- PR tetap terbuka;
- Hermes membuat follow-up plan;
- perubahan baru menginvalidasi approval lama bila head SHA berubah;
- Evidence rerun wajib bila code atau configuration berubah;
- rekomendasi negatif tidak boleh dihapus dari history;
- jika conflict tidak dapat diselesaikan, task menjadi `escalated`.

### 12.5 Manual override

Override emergency membutuhkan:

- incident ID;
- scope PR/commit;
- alasan dan impact;
- approver;
- waktu mulai dan expiry;
- rollback/forward-fix plan;
- follow-up Evidence maksimal 24 jam;
- post-incident review.

## 13. Audit event dan retention tanpa custom platform

### 13.1 Canonical event

Fase 0 memakai event JSONL atau artifact metadata yang ditulis oleh script/CI. Minimal field:

```json
{
  "event_id": "uuid",
  "project_id": "pilot-repo",
  "task_id": "TASK-123",
  "pr_number": 42,
  "event_type": "task_started|evidence_run|approval|merge|deploy|incident",
  "actor": "hermes|human|github-actions|operator",
  "commit_sha": "...",
  "policy_version": "policy-v7",
  "source_pointer": "url-or-artifact",
  "rationale": "short operational explanation",
  "created_at": "...",
  "idempotency_key": "..."
}
```

Tidak perlu membuat event database custom pada Fase 0. Jika query mulai menyulitkan, Bun dapat membuat utility SQLite/JSONL terpisah tanpa mengubah Hermes internal state.

### 13.2 Retention

| Data | Minimum |
|---|---:|
| PR/check/event pointer | 1 tahun |
| Artifact merge/deploy | 1 tahun |
| Raw CI log | sesuai provider policy, tetapi pointer/hash dipertahankan |
| Task working directory | sampai task selesai + cleanup window |
| Provisional operational note | 90 hari atau sampai superseded |
| Legal hold | sampai owner dan reviewer melepas |

Retention service/script harus menghasilkan deletion event. Tidak boleh menghapus artifact yang terkait incident, client dispute, government review, atau security investigation.

### 13.3 Recovery

- Git repository adalah source recovery code.
- GitHub PR/check/artifact adalah source recovery workflow.
- Audit artifact dicopy ke storage berbeda dari server utama.
- Backup server Hermes tidak cukup untuk menggantikan backup project artifact.
- Restore test dilakukan bulanan selama pilot.

## 14. Build-vs-buy dan aturan teknologi

### 14.1 Gunakan apa yang sudah ada

Urutan implementasi:

1. Hermes built-in features;
2. Bash dan Unix tools;
3. existing Rust binaries;
4. GitHub CLI/API dan GitHub Actions;
5. Bun 1.4 untuk helper yang memiliki kebutuhan logic nyata.

Contoh kebutuhan yang layak memakai Bun:

- validasi schema JSON/YAML kompleks;
- normalisasi Evidence Artifact;
- rekonsiliasi event JSONL;
- perhitungan risk label yang terlalu rumit untuk Bash;
- utility CLI kecil yang membutuhkan test unit.

Bun helper harus berupa CLI yang dapat dipanggil oleh Bash/CI, bukan service daemon, kecuali ada trigger yang disetujui.

### 14.2 Belum perlu dibangun

- Hermes replacement;
- custom agent loop;
- custom memory graph;
- custom chat/gateway;
- custom cron scheduler;
- custom approval UI;
- custom queue;
- custom HTTP server;
- PostgreSQL/Redis/Neo4j;
- distributed lock;
- dashboard penuh;
- auto-revert;
- multi-agent parallel runtime.
- MCP Code Mode/router;

### 14.3 Trigger untuk menambah Bun service/database

Komponen custom baru hanya boleh dipertimbangkan jika salah satu bukti berikut ada:

- minimal 30 task dan 20 PR pilot;
- query/event JSONL menjadi bottleneck terukur;
- manual reconciliation memakan lebih dari 2 jam per minggu;
- lebih dari satu worker perlu berbagi state;
- audit query membutuhkan filter/report yang tidak praktis dari artifact;
- GitHub checks tidak cukup untuk queue/observability;
- CI/provider integration memerlukan API stabil;
- data loss atau retry ambiguity tidak dapat diselesaikan dengan artifact/branch.
- MCP catalog melebihi 20 tool atau workflow eksternal membutuhkan 4–6 langkah berurutan;
- token/response bloat terukur menjadi bottleneck setelah skill/tool filtering dasar diterapkan.

Jika trigger terpenuhi, opsi urutannya adalah Bun CLI → Bun scheduled utility → Bun service + SQLite → PostgreSQL hanya bila multi-process/multi-node benar-benar diperlukan.

### 14.4 Platform self-test

Self-test Fase 0 harus menguji:

1. Hermes dapat memulai conversation dengan provider utama;
2. `hermes doctor` bersih;
3. context file termuat dan aturan no-merge dipatuhi;
4. skill project dapat dipanggil;
5. local terminal berada pada directory yang benar;
6. command timeout menghentikan proses;
7. dangerous command memerlukan approval atau ditolak;
8. Hermes tidak dapat membaca production secret;
9. Bash adapter menghasilkan exit code dan artifact metadata;
10. CI dapat checkout exact commit SHA;
11. PASS menghasilkan Evidence Artifact lengkap;
12. code FAIL masuk FAIL dan tidak retry tanpa batas;
13. infra failure masuk UNKNOWN;
14. scanner fail/unavailable tidak menghasilkan PASS;
15. risk label invalid/unknown memblokir merge;
16. approval invalid setelah push baru;
17. high-risk PR tidak dapat di-merge tanpa approval;
18. low-risk PR dapat melewati human blocking setelah sampling policy;
19. artifact hash/head SHA mismatch ditolak;
20. cross-project workspace access ditolak;
21. quota 90% menahan task normal;
22. emergency override memiliki incident ID dan expiry;
23. destructive migration diblokir tanpa approval;
24. legal hold mencegah retention deletion;
25. backup artifact dapat dipulihkan;
26. rollback runbook berhasil pada fixture;
27. disk/memory emergency condition menghasilkan stop signal;
28. constrained profile menolak gateway connector dan delegation toolset;
29. `memory.write_approval` menahan memory write sampai approval;
30. `skills.write_approval` dan `skills.guard_agent_created` menahan/menandai skill write;
31. external memory provider tidak aktif pada Fase 0;
32. MCP yang tidak ada di allowlist tidak dapat dipanggil;
33. trajectory output terdeteksi dan tidak masuk Evidence Artifact;
34. provider direct/Portal dipetakan ke data class dan policy region;
35. prompt-optimization/evaluation profile tidak dapat mengubah production policy;
36. external skill directory yang writable menghasilkan failure atau blocked state;
37. skill metadata cukup untuk memilih skill pada kasus positif dan menolak kasus negatif;
38. skill body tidak memuat seluruh PRD atau source code dan reference/script dapat dibaca on-demand;
39. MCP tool di luar allowlist ditolak dan tool output memiliki ukuran/field limit;
40. MCP error tidak membocorkan secret, stack trace mentah, atau payload sensitif;
41. golden task mencatat token/tool/error/latency/cost bila metric tersedia;
42. perubahan skill/tool/schema menghasilkan regression comparison terhadap baseline.

Hermes internal implementation test tidak perlu diduplikasi oleh platform. Self-test hanya menguji integration boundary dan policy proyek.

### 14.5 Schema versioning

Schema yang wajib dimiliki project:

```text
.agent/schemas/task.schema.json
.agent/schemas/evidence-manifest.schema.json
.agent/schemas/evidence-artifact.schema.json
.agent/schemas/event.schema.json
.agent/schemas/risk-decision.schema.json
.agent/schemas/approval.schema.json
.agent/schemas/incident.schema.json
.agent/schemas/deployment.schema.json
```

Perubahan default bersifat additive dan backward-readable. Breaking change memakai version, fixture replay, migration note, dan rollback plan. Hermes config schema tidak disalin ke schema project; upgrade Hermes mengikuti dokumentasi dan test Hermes sendiri.

### 14.6 Reference repository: agentic-ai-engineering

`agenticloops-ai/agentic-ai-engineering` diperlakukan sebagai reference/learning repository, bukan runtime dependency dan bukan pengganti Hermes. Repository tersebut mengajarkan pembangunan agent loop, tool calling, memory, eval harness, serta production concerns dari first principles; README-nya juga mengelompokkan materi ke foundations, effective-agent patterns, advanced techniques, testing/evaluation, frameworks, dan production. [Repository](https://github.com/agenticloops-ai/agentic-ai-engineering)

Yang dapat dipakai untuk PRD ini:

- unit testing agent dengan mock-and-replay dan behavioral invariant;
- golden task/eval dataset;
- tracing dan failure analysis;
- red teaming untuk prompt injection dan tool misuse;
- benchmark model/prompt berdasarkan accuracy, latency, cost, dan token usage;
- human-in-the-loop, evaluator/optimizer, dan error handling sebagai pola yang diuji, bukan fitur yang wajib aktif;
- checklist production untuk monitoring, cost, security, dan resilience.

Adopsi dilakukan dengan mengambil pola, test idea, dan rubric secara selektif ke `.agent/fixtures/`, `.agent/evals/`, atau `references/`. Jangan menambahkan Python/`uv`, framework agent, custom agent loop, LangGraph, CrewAI, atau orchestrator dari repository tersebut hanya karena tutorialnya tersedia. Hermes sudah menjadi agent runtime; Bash, existing Rust tools, GitHub Actions, dan Bun helper tetap menjadi implementation path.

### 14.7 Evaluation set dan token audit

Fase 0 membuat minimal 10 golden task yang mewakili low, medium, high-risk, reviewer feedback, `FAIL`, `UNKNOWN`, dan human-only acceptance. Fase 1 memperluasnya menuju 20–50 representative task setelah data pilot tersedia.

Setiap eval mencatat:

- task ID dan fixture version;
- provider/model/profile Hermes;
- input/output token bila tersedia;
- jumlah tool call dan error;
- response bytes dan latency;
- Evidence result;
- human rubric bila diperlukan;
- cost estimate;
- regression versus baseline.

Optimasi token hanya diterima jika success rate dan safety tidak turun secara material. Output tool dipandang sebagai bagian dari biaya; log mentah, HTML penuh, database dump, dan seluruh source file tidak boleh dikirim ke konteks bila ringkasan/excerpt cukup.

## 15. Roadmap dan exit criteria

### Fase 0 — Hermes operational hardening

Output wajib:

- satu server Linux pilot dan user khusus Hermes;
- Hermes terpasang, provider dipilih, versi dipin, `hermes doctor` lulus;
- `.agent/hermes-policy.yaml` tersedia dan actual Hermes constrained profile lulus self-test;
- terminal backend dipilih dan boundary isolation didokumentasikan;
- satu context file utama (`AGENTS.md` atau `.hermes.md`);
- project skill minimum untuk plan/evidence/PR;
- skill audit checklist dan MCP/tool allowlist tersedia;
- minimal 10 golden task/eval fixture tersedia;
- provider registry dan secret policy;
- repo fact sheet;
- Bash Evidence Adapter;
- `.agent/evidence.yaml`;
- acceptance mapping template;
- GitHub PR template dan branch protection;
- CI verifier dengan PASS/FAIL/UNKNOWN;
- Evidence Artifact dan audit copy;
- risk label check;
- approval/merge policy;
- incident, rollback, migration, dan support runbook;
- fixture repository atau fixture task;
- self-test integration lulus;
- baseline report tersedia.

Fase 0 tidak selesai jika Hermes dapat coding tetapi evidence, permission, atau recovery tidak dapat dibuktikan.

### Fase 1 — Evidence-backed workflow

Target:

- minimal 30 task dan 20 PR agentic;
- 10 task pertama menjadi calibration window;
- minimal 80% task memiliki Evidence Artifact lengkap;
- 100% automated verified PR memiliki artifact lengkap;
- tidak ada critical security/data-loss incident akibat workflow;
- material escape maksimum 1 per rolling 50 PR, atau low-confidence jika sample belum 50;
- CI budget tidak exhaustion tidak terencana;
- satu operator dapat menjalankan workflow tanpa maintenance harian yang tidak realistis;
- low-risk human blocking wait p50 mendekati nol setelah policy stabil;
- cost actual tidak melebihi 2x seed pada lebih dari 20% task;
- golden task regression tidak menunjukkan penurunan material pada success/safety setelah skill/tool/token optimization.

Keputusan akhir Fase 1:

- **lanjut:** criteria terpenuhi dan owner tersedia;
- **perpanjang:** evidence belum cukup tetapi tidak ada critical failure;
- **ubah desain:** bottleneck nyata muncul pada tool/provider/workflow;
- **hentikan:** critical incident, repeated self-test failure, uncontrolled cost, atau tidak ada owner.

### Fase 2 — Custom integration earned by evidence

Hanya dievaluasi jika trigger Section 14.3 terpenuhi:

- Bun CLI untuk event/report;
- SQLite adapter untuk query/audit;
- webhook integration;
- dashboard ringan;
- provider fallback dengan calibration;
- parallel low-risk pilot;
- durable orchestration bila replay manual terbukti mahal.

### Fase 3 — Sensitive/government readiness

Membutuhkan assessment baru untuk:

- data residency;
- DPA/contract provider;
- identity/access review;
- threat model mendalam;
- RPO/RTO;
- immutable audit storage;
- incident response dan support SLA;
- approval/legal/compliance owner.

## 16. KPI dan definisi pengukuran

| KPI | Definisi | Denominator |
|---|---|---|
| Agentic lead time | task ready ke PR merge | PR agentic non-calibration |
| Evidence coverage | PR dengan artifact lengkap | seluruh PR agentic yang mencapai CI |
| Automated verified rate | PR low-risk yang PASS tanpa blocking human gate | PR low-risk eligible |
| Human wait | review_required ke approval | PR yang memang membutuhkan approval |
| Code retry rate | task yang memakai code retry | task yang evidence/code gagal |
| Infra unknown rate | run UNKNOWN akibat infra | seluruh evidence run |
| CI cost | compute minutes dan provider cost | PR/run aktual |
| Material escape | incident P1 linked ke merged PR | rolling 50 PR |
| Rollback time | detection ke rollback/forward-fix | deployment incident |
| Maintenance time | jam operator per minggu | minggu pilot |
| Memory/context dependency | task yang gagal karena memory Hermes tidak tersedia | task yang memanggil memory |
| Input tokens | token input per task/session bila provider menyediakan | task/session aktual |
| Output tokens | token output per task/session bila provider menyediakan | task/session aktual |
| Tool calls | jumlah call, error, retry, dan response bytes | task yang memakai tools |
| Skill activation | skill yang terpicu, success/failure, dan false trigger | task yang memuat skill |
| Cache hit ratio | cache read dibanding cacheable prefix bila provider menyediakan | request yang memiliki metric cache |
| Token/cost efficiency | cost dan token per successful task, bukan hanya per request | golden task/eval dan pilot task |

10 task calibration masuk audit dan security KPI, tetapi dikeluarkan dari efficiency KPI. Threshold dan definisi KPI harus versioned.

### 16.1 Severity

- **P0/Critical:** secret/PII exposure, auth bypass, irreversible data loss, core production unavailable lebih dari 15 menit.
- **P1/Material:** production defect yang memengaruhi user/financial flow dan membutuhkan rollback/forward-fix.
- **P2/Minor:** defect terbatas tanpa impact besar.

P0 selalu fail-safe dan memicu incident review, terlepas dari KPI efisiensi.

## 17. Definition of Ready — Fase 1

- [ ] Hermes terpasang pada Linux user khusus.
- [ ] Hermes version/provider/model/context window dipin.
- [ ] `hermes doctor` dan smoke chat lulus.
- [ ] `.agent/hermes-policy.yaml` tersedia dan dipetakan ke config Hermes versi yang dipin.
- [ ] Memory mode dipilih; external memory provider off; memory write approval diuji.
- [ ] Skill allowlist, skill write approval, agent-created skill guard, dan external directory read-only diuji.
- [ ] Delegation/subagent toolset dan gateway connector tidak aktif pada worker profile.
- [ ] MCP manual allowlist diuji; catalog/one-click install tidak menjadi jalur production.
- [ ] Trajectory export/RL training output tidak aktif atau diblokir dari artifact.
- [ ] Prompt optimization/evaluation profile dipisahkan dari production worker.
- [ ] Terminal backend, isolation, timeout, cwd, dan env passthrough didokumentasikan.
- [ ] Satu context file utama tersedia dan tidak konflik dengan context file lain.
- [ ] Project skills minimum tersedia dan direview.
- [ ] Skill metadata/body/reference/scripts mengikuti progressive-disclosure budget dan tidak menduplikasi policy global.
- [ ] MCP/tool allowlist, schema, output limit, timeout, owner, data class, dan removal path tersedia bila MCP dipakai.
- [ ] Minimal 10 golden task/eval fixture tersedia untuk regression dan token audit.
- [ ] Repo fact sheet dan baseline report tersedia.
- [ ] GitHub provider dan branch protection aktif.
- [ ] Hermes token tidak memiliki hak approve/merge/deploy.
- [ ] Evidence Contract empat command utama dapat dijalankan.
- [ ] Manifest mendeklarasikan exact/approximate/hybrid/ci_only.
- [ ] Acceptance-to-evidence mapping aktif.
- [ ] CI Verifier menghasilkan PASS/FAIL/UNKNOWN.
- [ ] Artifact menyimpan commit SHA, CI run ID, command, duration, log pointer, dan hash.
- [ ] Artifact merge/deploy dicopy ke audit storage.
- [ ] Secret/PII/redaction scanner diuji dengan fixture sintetis.
- [ ] Risk label actor dan high-risk flag diuji.
- [ ] Approval bound ke head SHA dan expiry.
- [ ] Retry code/infra terpisah dan tidak infinite loop.
- [ ] CI quota alert 70/80/90 memiliki owner.
- [ ] Emergency override memiliki incident ID, expiry, dan follow-up evidence.
- [ ] Migration, incident, rollback, dan support runbook tersedia.
- [ ] Backup/restore artifact dan event pointer diuji.
- [ ] Self-test integration lulus.
- [ ] Operator dapat menghentikan Hermes dan membersihkan workspace.
- [ ] Disk/memory limit dan cleanup policy aktif.

## 18. Risk register

| Risiko | Level | Mitigasi |
|---|---|---|
| Hermes mengikuti prompt injection | Tinggi | Context hierarchy, source untrusted, approval, no merge token |
| Local terminal tidak terisolasi | Tinggi | Dedicated user, no production secret, Docker/CI untuk high-risk |
| Model/provider berubah | Sedang | Pin provider/model, registry, smoke test, rollback |
| Hermes memory menjadi policy salah | Tinggi | Memory hanya hint, policy dari repo/PR/approval |
| Evidence PASS tidak mewakili business acceptance | Tinggi | Acceptance mapping, reviewer, human-only evidence |
| Environment drift | Sedang | CI source of truth, environment mode, pinned runtime |
| CI quota habis | Sedang | threshold, reserve, fallback, freeze policy |
| Secret/PII masuk log | Kritis | scanner, redaction, no production secret, restricted artifact |
| Artifact hilang/diubah | Tinggi | hash, commit SHA, audit copy, retention/legal hold |
| Retry loop | Tinggi | separate budgets, circuit breaker, escalation |
| Human bottleneck | Tinggi | risk-tiered autonomy, sampling, low-risk auto path |
| Server 2 GB OOM | Tinggi | serial, no local LLM, CI heavy build, resource limit, disk/memory monitoring |
| Tool supply chain | Tinggi | version pin, existing tools first, checksum/review |
| Migration tidak dapat di-rollback | Kritis | expand/contract, backup/PITR, approval, staging drill |
| Tidak ada operator/delegate | Sedang | RACI, delegate expiry, support window |
| Hermes upgrade merusak workflow | Sedang | version pin, fixture, self-test, rollback |
| Overbuilding custom platform | Sedang | trigger Section 14.3, no premature service |
| Agent-created skill menyisipkan instruksi berbahaya | Tinggi | skill write approval, guard scan, allowlist, read-only external dirs |
| External memory provider mengirim context ke pihak ketiga | Tinggi | external provider off Fase 0, provider/data-flow review sebelum enable |
| Gateway atau channel chat memicu task tanpa audit PR | Tinggi | gateway connector off; CLI/GitHub only |
| Subagent menghasilkan perubahan tanpa boundary audit | Tinggi | delegation off Fase 0; child wajib task/artifact boundary jika kelak aktif |
| Trajectory/source code masuk training pipeline | Kritis | trajectory export off, artifact scan, no RL pipeline pada worker |
| Prompt optimization membuat perilaku tidak reproducible | Sedang | production profile immutable; evaluation profile terpisah |
| Skill/tool context terlalu besar | Sedang | progressive disclosure, allowlist, skill/tool budget, token audit |
| MCP output membanjiri context atau membocorkan data | Tinggi | server-side filtering, output schema, pagination, byte/token limit, redaction |
| Claude-specific loading feature diasumsikan tersedia di Hermes | Sedang | feature detection, provider-specific self-test, no blind config copy |
| Code Mode/router menambah sandbox dan maintenance tanpa manfaat | Sedang | ditunda sampai tool/workflow trigger terbukti |
| Token optimization menurunkan accuracy/safety | Tinggi | golden tasks, regression eval, human rubric, rollback |

## 19. Decision log v7

| Keputusan | Alasan |
|---|---|
| Hermes menjadi primary harness | Sudah menyediakan agent loop, tools, session, memory, skills, dan gateway |
| Tidak membangun agent/orchestrator baru | Menghindari duplikasi dan beban maintenance |
| Bash menjadi adapter pertama | Cepat, portable, mudah diaudit pada repo heterogen |
| Existing Rust tools diprioritaskan | Menghindari implementasi utility yang sudah matang |
| Bun 1.4 hanya helper on-demand | Memberi typed logic tanpa memelihara service baru |
| GitHub Actions menjadi verifier independen | Memisahkan agent dari evidence decision |
| SQLite/custom DB ditunda | Fase 0 dapat berjalan dengan PR, artifact, dan JSONL |
| Serial execution sebagai default | Server 2 GB dan konflik lebih mudah dikendalikan |
| Local Hermes hanya untuk pilot terkontrol | Local backend tidak menyediakan sandbox penuh |
| Docker/CI untuk high-risk | Memperkuat boundary eksekusi kode |
| Hermes memory bukan audit source | Internal memory dapat berubah dan tidak cukup untuk compliance |
| Human gate berbasis risk | Task kecil tidak perlu menjadi bottleneck |
| Cryptographic attestation ditunda | Artifact hash/commit/CI identity cukup untuk baseline jika dapat diverifikasi |
| Hermes constrained profile | Memory write, skill write, delegation, gateway, MCP, trajectory, dan tool access memiliki guardrail eksplisit |
| External Hermes memory provider ditunda | Fase 0 tidak menambah data flow/provider/retention baru |
| Nous Portal bukan default untuk sensitive | Multi-hop provider/region/subprocessor harus dapat diaudit terlebih dahulu |
| ECC tidak digunakan | Hermes memiliki native skills dan ECC bukan dependency yang relevan |
| Skill memakai progressive disclosure | Metadata singkat, body on-demand, reference/script terpisah mengurangi context baseline |
| MCP bukan default untuk command sederhana | Bash/CLI tidak membayar tool schema dan lebih mudah diaudit pada Fase 0 |
| MCP output wajib diringkas di server | Response bloat dan raw data meningkatkan biaya serta leakage risk |
| Code Mode ditunda | Tool catalog dan workflow Fase 0 belum cukup besar untuk membayar sandbox complexity |
| `agentic-ai-engineering` hanya reference | Repo tutorial berguna untuk eval/testing/production patterns, bukan dependency runtime |

## 20. Open questions sebelum implementasi

| Pertanyaan | Owner | Blocking |
|---|---|---|
| Repo pilot pertama apa? | Hasban | Ya |
| GitHub Actions tersedia dan budget-nya berapa? | Operator | Ya |
| Provider/model Hermes utama apa? | Hasban | Ya |
| Apakah server boleh memakai Docker? | Operator | Ya untuk high-risk isolation |
| Apakah local backend boleh untuk source client? | Hasban/legal | Ya |
| Di mana audit artifact dicopy? | Operator | Ya |
| Siapa delegate approver? | Hasban | Ya |
| Berapa support window dan on-call? | Hasban | Ya |
| Tool scanner apa yang sudah tersedia? | Operator | Tidak jika adapter dapat dimulai |
| Kapan Bun helper pertama diperlukan? | Hermes/operator | Tidak pada hari pertama |
| Apakah memory Hermes default dipakai `context_only` atau `off` untuk pilot? | Hasban | Ya untuk automated policy |
| Apakah Nous Portal disetujui untuk data class internal pilot? | Hasban/legal | Ya jika dipakai |
| Apakah Docker tersedia untuk high-risk execution? | Operator | Ya sebelum high-risk run |
| Apakah gateway, delegation, dan trajectory benar-benar off pada profile? | Operator | Ya |

## 21. Catatan epistemik dan perubahan PRD

PRD ini sengaja membatasi klaim:

- Hermes dapat menjalankan workflow, tetapi tidak menjamin correctness produk.
- Evidence Gate membuktikan command, bukan business acceptance.
- Human review adalah mekanisme risk control, bukan validator semua task.
- Internal Hermes memory bukan durable audit database.
- Server 2 GB cukup untuk satu agent remote-model secara serial, tetapi harus divalidasi dengan benchmark nyata.
- Bun 1.4 diperlakukan sebagai pilihan implementasi helper yang harus dipin dan diuji, bukan asumsi bahwa seluruh service harus ditulis Bun.

Perubahan PRD wajib mencatat:

- versi;
- alasan;
- evidence yang memicu perubahan;
- owner;
- dampak terhadap workflow dan permission;
- apakah memerlukan migration atau retraining skill.

## 22. Upgrade dan deprecation path

### 22.1 Upgrade Hermes

1. Simpan versi lama yang known-good.
2. Jalankan `hermes doctor` pada kandidat baru.
3. Jalankan fixture chat, context loading, skill, terminal, approval, dan session resume.
4. Jalankan satu fixture Evidence workflow.
5. Review perubahan config/provider/tool behavior.
6. Deploy kandidat pada profile non-production.
7. Simpan rollback ke versi lama selama satu review cycle.

### 22.2 Upgrade project adapter

1. Naikkan `contract_version` atau `policy_version`.
2. Jalankan fixture PASS/FAIL/UNKNOWN.
3. Jalankan acceptance mapping validation.
4. Review changed command dan timeout.
5. Jalankan CI pada branch.
6. Merge hanya setelah artifact baru dapat dibandingkan dengan baseline.

### 22.3 Trigger deprecation

Tool atau custom component dideprecate jika:

- sudah digantikan fitur Hermes/CI yang lebih sederhana;
- maintenance time lebih besar daripada manfaat;
- tidak memiliki owner;
- tidak lulus self-test dua review cycle;
- menambah privilege, cost, atau failure mode tanpa evidence manfaat.

## 23. Definition of Done v7.1

PRD v7.1 dianggap terimplementasi minimum ketika:

1. Hermes dapat menjalankan task pilot pada server 2 GB dengan model eksternal.
2. Hermes mengikuti context file dan project skill.
3. Hermes tidak memiliki hak merge/deploy production.
4. Satu task dapat berjalan dari Issue sampai PR secara serial.
5. Bash adapter menghasilkan evidence yang dapat dijalankan ulang.
6. CI verifier menghasilkan PASS/FAIL/UNKNOWN.
7. Evidence Artifact tertaut ke task, PR, commit, dan CI run.
8. Risk tier menentukan human gate secara konsisten.
9. Low-risk dapat berjalan tanpa blocking human approval setelah calibration policy.
10. High-risk tidak dapat merge tanpa approval.
11. Secret/PII scanner dan redaction diuji.
12. Retry, quota, timeout, dan stop rule bekerja.
13. Artifact dapat dipulihkan dari audit storage.
14. Rollback dan incident runbook diuji pada fixture.
15. Operator dapat menghentikan, memperbarui, dan memulihkan Hermes.
16. Constrained profile memblokir skill write, external memory, delegation, gateway, MCP tidak approved, trajectory export, dan prompt optimization production.
17. Skill/MCP token audit dan golden-task regression tersedia bila skill atau MCP dipakai.
18. Tidak ada service custom yang dibangun tanpa trigger Section 14.3.

**Keputusan akhir:** mulai dari Fase 0 dengan Hermes + Bash + existing tools + GitHub Actions. Bun 1.4 dipakai hanya ketika kebutuhan helper terukur muncul. Semua komponen platform yang lebih berat harus menunggu evidence nyata dari workflow pilot.

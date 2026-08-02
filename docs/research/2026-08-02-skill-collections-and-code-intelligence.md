# Riset: skill collection + code intelligence (2026-08-02)

Tujuh repo diperiksa untuk memutuskan apa yang **tidak** perlu dibangun ulang.
Semua fakta di bawah dibaca langsung dari GitHub API dan raw file, bukan dari
ingatan model. Yang tidak terverifikasi ditandai eksplisit.

Metode: `curl` ke `api.github.com/repos/OWNER/REPO/git/trees/main?recursive=1`,
lalu `raw.githubusercontent.com` untuk isi file. Sebagian repo di-clone untuk
membaca frontmatter setiap `SKILL.md`.

## Ringkasan keputusan

| Repo | License | Bentuk | Menyelesaikan | Keputusan |
|---|---|---|---|---|
| obra/superpowers | MIT | 14 skill + 5 manifest plugin | planning, TDD, review, worktree, verification | integrasi upstream |
| DietrichGebert/ponytail | MIT | 6 skill (prompt pack) | YAGNI, over-engineering review, debt ledger | integrasi upstream |
| addyosmani/agent-skills | — (perlu cek) | 24 skill | ADR, doubt-driven, source-driven, simplification | integrasi upstream selektif |
| mattpocock/skills | — (perlu cek) | 41 skill | interface design, research, triage | kandidat, pilih selektif |
| oraios/serena | MIT | MCP server (Python) | navigasi simbol via LSP | **dilewati** |
| colbymchenry/codegraph | MIT | CLI + MCP + daemon | symbol graph, FTS5, impact analysis | adapter opsional |
| Egonex-AI/understand-anything | MIT | slash command (TS) | onboarding, comprehension | bukan gate dependency |

## Skill collection

### obra/superpowers

14 skill, semuanya prosa workflow. Yang relevan:

```text
brainstorming                     wajib sebelum kerja kreatif
writing-plans                     spec → rencana bertahap
executing-plans                   eksekusi rencana dengan checkpoint
subagent-driven-development       task independen di sesi yang sama
dispatching-parallel-agents       2+ task tanpa shared state
test-driven-development           sebelum menulis implementasi
systematic-debugging              sebelum mengusulkan fix
using-git-worktrees               isolasi workspace
requesting-code-review            sebelum merge
receiving-code-review             menanggapi feedback dengan rigor
verification-before-completion    menuntut command dijalankan sebelum klaim
finishing-a-development-branch    memutuskan cara integrasi
writing-skills                    membuat/mengedit skill
using-superpowers                 meta-skill
```

Distribusi: 5 manifest paralel (`.claude-plugin/`, `.codex-plugin/`,
`.cursor-plugin/`, `.kimi-plugin/`, `.agents/plugins/`) plus
`.opencode/plugins/superpowers.js`, `gemini-extension.json`, dan script sync.
Itu memberi install satu baris di banyak marketplace, dengan biaya lima manifest
yang harus dijaga tetap sinkron.

**Tidak diduplikasi.** `verification-before-completion` khususnya sudah
menyelesaikan sisi perilaku dari P5.

### DietrichGebert/ponytail

```text
license   MIT          language JavaScript      size 2253 KB
created   2026-06-12   pushed 2026-07-15
topics    agent-skills, ai-agents, claude-code, cursor-rules, yagni
```

156 file. 6 skill: `ponytail` (aturan utama), `ponytail-review` (review
over-engineering pada diff), `ponytail-audit` (seluruh repo), `ponytail-debt`
(memanen komentar `ponytail:` menjadi ledger utang), `ponytail-gain`,
`ponytail-help`.

Temuan yang menentukan: **nol enforcement mekanis.** `grep -E
'complexity|cyclomatic|lizard|budget'` pada `*.md` → 29 kecocokan, semuanya
prosa/heuristik. Tidak ada threshold CCN, tidak ada exit code, tidak ada gate.
Ini prompt pack, bukan tool.

Konsekuensi: ponytail menyelesaikan **penilaian** P3, bukan **pengukuran** P3.
Keduanya dibutuhkan, dan keduanya berbeda pekerjaan.

Marker `ponytail:` yang dipakai di komentar kode repo ini adalah konsep yang sama
— tandai simplifikasi yang disengaja beserta ceiling dan jalur upgrade-nya. Repo
itu memformalkannya sebagai instruksi agent untuk 6+ runtime.

*Belum diverifikasi:* isi lengkap beberapa `SKILL.md` hanya di-grep, tidak dibaca
utuh (output terpotong).

### addyosmani/agent-skills

24 skill. Yang memetakan ke masalah kita:

```text
documentation-and-adrs         P4 — ADR, keputusan arsitektur
source-driven-development      P4 — setiap keputusan berbasis dokumentasi resmi
doubt-driven-development       P5 — review adversarial fresh-context
code-simplification            P3 — refactor untuk kejelasan
code-review-and-quality        review multi-axis sebelum merge
incremental-implementation     delivery bertahap
planning-and-task-breakdown    spec → task
spec-driven-development        spec sebelum koding
test-driven-development        TDD
```

`doubt-driven-development` adalah kecocokan terkuat untuk P5: "subjects every
non-trivial decision to a fresh-context adversarial review before it stands".

### mattpocock/skills

41 skill, termasuk 4 deprecated dan 7 in-progress. Banyak yang spesifik ke
TypeScript atau workflow pribadi (`obsidian-vault`, `edit-article`,
`migrate-to-shoehorn`). Yang berpotensi: `research`, `code-review`,
`codebase-design`, `domain-modeling`, `to-tickets`, `triage`, `wayfinder`,
`writing-great-skills`.

Belum diputuskan — perlu validasi license dan mekanisme install lebih dulu.

## Code intelligence

### oraios/serena — dilewati

```text
MIT · Python · 27.4k stars · pushed 2026-08-01 · ~11 MB
install: uv tool install -p 3.13 serena-agent, lalu serena init
backend: LSP (default) atau JetBrains plugin (berbayar)
bahasa: "over 40 programming languages"
```

Tool yang diekspos (dibaca dari `src/serena/tools/*.py`):

```text
symbol_tools.py  FindSymbolTool, GetSymbolsOverviewTool, FindReferencingSymbolsTool,
                 FindImplementationsTool, FindDeclarationTool, GetDiagnosticsFor*,
                 ReplaceSymbolBodyTool, Insert{After,Before}SymbolTool,
                 RenameSymbolTool, SafeDeleteSymbol, RestartLanguageServerTool
file_tools.py    SearchForPatternTool, ReplaceContentTool, FindFileTool, ListDirTool, …
memory_tools.py  5 operasi memory
```

Alasan dilewati, tiga hal sekaligus:

1. Interface MCP-only. CLI-nya launcher/config, bukan query. Tidak ada jalur
   yang bisa dipanggil dari Bash.
2. Butuh language server hidup per bahasa (karena itu ada
   `RestartLanguageServerTool`), dan beberapa bahasa butuh dependency tambahan.
3. Pencarian non-simbolnya regex biasa — daya yang sama dengan `git grep` yang
   sudah dipakai.

**Verdict P1: tidak.** Ia menjawab "di mana simbol X / siapa memanggil X". Tidak
ada primitive kesamaan/duplikasi. Untuk tahu "apakah ada kode serupa", agent
masih harus menebak namanya.

*Belum diverifikasi:* perilaku offline setelah install.

### colbymchenry/codegraph — adapter opsional

```text
MIT · Rust kernel + TS · 64k stars · pushed 2026-08-01
install: curl -fsSL .../install.sh | sh  atau  npm i -g @colbymchenry/codegraph
index:   tree-sitter symbol + edge (calls/imports/extends/implements)
         → SQLite .codegraph/codegraph.db dengan FTS5
daemon:  ya, file watcher (FSEvents/inotify), CODEGRAPH_NO_DAEMON=1 mematikan
```

CLI-nya sungguhan, dan itu yang membedakannya:

```bash
codegraph query <search> --json
codegraph explore <query>
codegraph callers|callees|impact <symbol> --depth --json
codegraph affected --stdin --quiet     # README sendiri memberi contoh CI bash
git diff --name-only HEAD | codegraph affected --stdin --quiet
```

**Verdict P1: sebagian, terbaik dari tiga.** `query --json` + FTS5 memberi recall
nama/teks jauh di atas grep. Tetap bukan deteksi kesamaan — tidak ada primitive
"dua fungsi ini melakukan hal yang sama".

*Belum diverifikasi:* jejak disk/RAM nyata; semua angka performa adalah klaim
README (Swift repo 27k file → ~100s index; kernel Linux 70k file di VPS 2-core
<12 menit).

### Egonex-AI/understand-anything — bukan gate dependency

```text
MIT · TypeScript · 77k stars · pushed 2026-07-30
install: marketplace Claude Code, atau curl install.sh -s <platform>
         (platform termasuk hermes, codex, opencode, kiro, cursor)
index:   tree-sitter + summary hasil LLM → .ua/knowledge-graph.json
pipeline: 5-6 agent (project-scanner, file-analyzer, architecture-analyzer,
          tour-builder, graph-reviewer, domain-analyzer)
```

Interface slash command saja: `/understand`, `/understand-diff`,
`/understand-explain`, `/understand-onboard`, dst. Bukan MCP, bukan query CLI.

README-nya sendiri memperingatkan `/understand` "can consume a significant number
of tokens on large projects". Butuh panggilan LLM untuk membangun graph, jadi
tidak offline.

**Verdict P1: tidak, untuk gating.** Lapisan LLM non-deterministik + biaya token
+ tanpa query headless = bentuk yang salah untuk gate yang memblokir. "Fuzzy &
Semantic Search"-nya hidup di dashboard browser.

Graph-nya JSON yang di-commit, jadi bisa dibaca `jq` gratis kalau kebetulan ada.

### Tidak satu pun menyelesaikan P1

Ketiganya menjawab "di mana X". Tidak ada yang menjawab "apakah ada kode yang
fungsinya sama". Dan kegagalan yang dikutip di PRD — agent tidak mencari sebelum
generate — adalah masalah **perilaku**, bukan masalah daya retrieval. Retrieval
yang lebih baik tidak menyala kalau tidak ada yang memaksa melihat.

Karena itu forcing function berbasis artifact adalah bagian yang tidak tersedia
di luar, dan grep berlapis sudah cukup kuat untuk mengisinya:

- istilah utuh, case-insensitive
- token dipecah, supaya `report download` menemukan `downloadReport`
- riwayat git (`log -S`), supaya implementasi yang pernah dihapus terlihat

## Complexity: survei tool

| Tool | Install | Bahasa | Output mesin | Threshold per-fungsi + exit≠0 |
|---|---|---|---|---|
| **lizard** | `pipx install lizard`, Python murni | ~20: C/C++, Java, C#, JS, TS, Python, Ruby, PHP, Swift, Go, Rust, Kotlin, Lua, Scala, Solidity, Zig, ObjC, Fortran, Erlang, GDScript | `--csv`, `-X` xml. **tanpa JSON** | ya: `-C` CCN, `-L` panjang, `-a` argumen, `--warnings_only` |
| scc | 1 binary Go | ~200 | `--format json` | tidak — "complexity" = hitung keyword, per-file, tanpa fungsi |
| radon | pip | Python saja | JSON | ya, satu bahasa |
| gocyclo | go install | Go saja | teks | ya, satu bahasa |
| eslint `complexity` | node_modules + config + parser TS | JS/TS saja | JSON | ya, beban config terberat |
| PHPStan/phpmetrics | composer, berat | PHP saja | JSON | butuh extension |

Stack per-bahasa berarti 5 install, 5 format output, 5 konvensi exit. Ditolak.

**Dipilih: lizard.** Satu dependency yang menutup PHP+JS+TS+Go+Python+Rust dengan
CCN per-fungsi dan exit code threshold.

Diverifikasi langsung di mesin ini:

```bash
$ lizard --version
1.23.0

$ lizard -C 3 --warnings_only /tmp/t.py     # fungsi dengan CCN 13
t.py:1: warning: f has 13 NLOC, 13 CCN, 77 token, 1 PARAM, 13 length, 0 ND
EXIT=1

$ lizard -C 3 --warnings_only /tmp/t2.py    # fungsi trivial
EXIT=0
```

Kontrak exit code terbukti, bukan diasumsikan.

*Belum diverifikasi:* cakupan Rust di 1.23.0 dengan file Rust sungguhan.

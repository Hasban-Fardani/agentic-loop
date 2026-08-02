# AEP v2.1 — status implementasi

Dokumen ini menyatakan apa yang benar-benar berjalan, apa yang opsional, dan apa
yang masih pekerjaan manusia. Setiap baris "implemented" punya command dan test
yang bisa dijalankan; tidak ada klaim tanpa jalur verifikasi.

Terakhir diperbarui: 2026-08-02. Suite: `./bin/al selftest` → 263 assert.

## Prinsip yang memandu keputusan reuse

Riset ke tujuh repo (lihat `docs/research/`) mengubah dua rencana awal:

1. **P3 (kode terlalu rumit) tidak dibangun dari nol.** `DietrichGebert/ponytail`
   sudah menyelesaikan sisi penilaian — YAGNI, stdlib-first, review
   over-engineering — sebagai skill untuk 6+ runtime agent. Yang belum ada di
   sana: enforcement mekanis. Repo itu punya nol pengukuran; 29 kecocokan untuk
   `complexity|cyclomatic|budget` semuanya prosa. Jadi `al complexity` hanya
   mengukur, dan penilaiannya diserahkan ke ponytail.

   Marker `ponytail:` di komentar kode repo ini memang berasal dari konsep yang
   sama. Itu bukan kebetulan dan bukan penemuan sendiri.

2. **P1 (reinvent) tidak diselesaikan oleh tool code-intelligence mana pun.**
   Serena, codegraph, dan understand-anything semuanya menjawab "di mana simbol
   X" atau "siapa yang memanggil X". Tidak satu pun punya primitive "apakah ada
   kode yang fungsinya sama". Kegagalan yang sebenarnya bersifat perilaku: agent
   tidak mencari sebelum menulis. Retrieval yang lebih kuat tidak menolong kalau
   tidak ada yang memaksa melihat. Karena itu `al discovery` adalah forcing
   function berbasis artifact, bukan mesin pencari.

## Status per gate

| Gate | Status | Command | Test | Catatan |
|---|---|---|---|---|
| Evidence tri-state | implemented | `al run <profile>` | `evidence_test.sh` | 0=PASS 1=FAIL 2=UNKNOWN; UNKNOWN mengalahkan FAIL |
| Secret/PII | implemented | `al scan` | `scan_test.sh` | 2 = tool absen, bukan lulus |
| Scope path | implemented | `al scope check` | `scope_test.sh` | forbidden mengalahkan allowed |
| Worktree | implemented | `al worktree` | `worktree_test.sh` | satu issue = satu branch = satu worktree |
| Metrics | implemented | `al metrics` | `metrics_test.sh` | tanpa target yang ditebak |
| P1 Discovery | implemented | `al discovery start\|verify` | `discovery_test.sh` | artifact wajib; label confidence |
| P3 Complexity | implemented, opt-in | `al complexity check` | `complexity_test.sh` | butuh `lizard`; candidate → approved |
| P2 Conventions | **belum** | — | — | butuh scan + approval owner |
| P4 Decision record | **belum** | — | — | validator ADR, bukan penulis ADR |
| P5 Unverified claim | **belum** | — | — | butuh artifact review terstruktur |
| Upstream integration | **belum** | — | — | manifest pinned, non-vendored |

## Yang opsional dan bagaimana ia gagal

Inti toolkit tetap Bash + git + jq. Tool opsional tidak pernah mengubah
"tak terukur" menjadi "lulus":

| Tool | Dipakai untuk | Absen + optional | Absen + required |
|---|---|---|---|
| `lizard` | CCN lintas bahasa | `no_op COMPLEXITY_TOOL_UNAVAILABLE`, exit 0 | exit 2 (UNKNOWN) |
| `codegraph` | memperkaya kandidat discovery | fallback command, confidence diturunkan | — |
| `.ua/knowledge-graph.json` | sumber kandidat gratis bila kebetulan ada | dilewati | — |

Verifikasi degradasi:

```bash
AL_COMPLEXITY_MODE=required AL_LIZARD_COMMAND=- al complexity check   # 2
AL_COMPLEXITY_MODE=optional AL_LIZARD_COMMAND=- al complexity check   # 0 + no_op
```

`AL_LIZARD_COMMAND=-` berarti "anggap tidak ada", sehingga degradasi bisa diuji
tanpa mencabut tool dari sistem.

## Keputusan integrasi

| Sumber | Keputusan | Alasan |
|---|---|---|
| `obra/superpowers` | integrasi upstream, jangan tulis ulang | planning, TDD, worktree guidance, verification-before-completion sudah matang |
| `DietrichGebert/ponytail` | integrasi upstream untuk penilaian; `al complexity` untuk pengukuran | repo itu prompt pack, nol enforcement mekanis |
| `addyosmani/agent-skills` | integrasi upstream (`documentation-and-adrs`, `doubt-driven-development`, `source-driven-development`) | ADR + adversarial review sudah ada; lokal hanya validator artifact |
| `mattpocock/skills` | kandidat, belum diputuskan | 41 skill, banyak yang khusus TS/workflow pribadi; pilih selektif setelah validasi license/install |
| `oraios/serena` | **dilewati** | MCP-only, tanpa jalur query yang bisa di-script, butuh LSP per bahasa, dan pencarian non-simbolnya regex biasa — tidak menambah kapabilitas yang belum ada |
| `colbymchenry/codegraph` | adapter opsional | satu-satunya yang punya CLI sungguhan (`query --json`, `affected --stdin`); recall nama lebih baik daripada grep |
| `Egonex-AI/understand-anything` | **bukan dependency gate** | lapisan LLM non-deterministik, berbiaya token, tanpa API query headless. Graph JSON-nya dibaca gratis bila ada |

## Terbuka, butuh keputusan atau data

Belum diselesaikan, dan sengaja tidak ditebak:

1. Threshold CCN final. `10/60/5` adalah hipotesis. Status `candidate` berarti
   dilaporkan tanpa memblokir sampai divalidasi ke kode nyata — gaya fluent
   (query builder, chained promise) menaikkan CCN tanpa kode benar-benar sulit
   dibaca.
2. QA boleh menulis test atau hanya menyarankan.
3. Kompatibilitas Spec Kit dengan Hermes.
4. Siapa yang menjalankan `git worktree add/remove` — manual dulu, delegasi
   setelah terbukti stabil.
5. Validasi drawio-skill dan Open Design untuk visual checkpoint.
6. Tool duplication scan untuk PHP.
7. Ambang "task kecil tidak perlu worktree".

## Belum diverifikasi

- Klaim performa Serena/codegraph/understand-anything semuanya klaim vendor;
  tidak ada indexer yang dijalankan di sini.
- Cakupan Rust di lizard 1.23.0 belum diuji dengan file Rust sungguhan.
- Perilaku offline Serena.
- Tidak ada harness (Claude Code, Codex, Cursor, opencode) yang dijalankan
  end-to-end untuk mengonfirmasi skill benar-benar dimuat; yang diverifikasi
  baru file mendarat di path yang benar dengan bentuk yang benar.

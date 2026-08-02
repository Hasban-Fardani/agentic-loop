# AGENTS.md

Aturan proyek untuk agent coding apa pun (Codex, Cursor, opencode, Claude Code,
Hermes, Copilot, Gemini CLI, Zed, Aider). File terdekat menang; AGENTS.md di
subdirektori menimpa yang di root.

## Perintah

```bash
al run standard      # evidence gate: 0=PASS 1=FAIL 2=UNKNOWN
al decision          # decision + flags artifact terakhir
al scan              # scanner secret/PII
al doctor            # config efektif, tool, harness terdeteksi
```

Automation dan CI memanggil `al run` langsung. Jangan lewat `make`: `make`
meratakan semua kegagalan ke exit 2 dan menghapus perbedaan FAIL vs UNKNOWN.

## Evidence

`PASS` berarti command wajib exit 0 pada commit ini — bukan berarti produk benar.
`UNKNOWN` bukan `FAIL` dan bukan `PASS`: hasil tidak dapat dibuktikan, merge
diblokir, dan itu memakai budget infra recovery (1x), bukan code retry (3x).

Selalu baca `quality_flags`, jangan hanya exit code.

## Konfigurasi

Semua tunable dari environment atau `.env`. Presedensi:

```text
default  <  ~/.config/agentic-loop/config.env  <  ./.env  <  environment
```

Jangan pernah hardcode token, path, atau ambang di script. Jangan pernah commit
`.env` — hanya `.env.example`. Lihat `.env.example` untuk daftar variabel.

## Yang tidak boleh dilakukan agent

- merge PR sendiri
- push ke branch protected
- mengubah branch protection
- approve perubahan sendiri
- deploy production
- membaca production secret

Kalau sebuah task tampak menuntut salah satu di atas: task-nya salah, atau
manusia yang harus melakukannya.

## Risk tier

Low (typo, docs, test terisolasi) boleh autonomous setelah `PASS`. Medium butuh
review manusia asinkron. High wajib approval eksplisit. Path high-risk repo ini
ada di `.agent/agent-policy.yaml`.

Agent boleh **menaikkan** tier, tidak pernah menurunkan.

## Definition of Done

1. Branch + PR, bukan commit langsung ke branch protected.
2. `al run standard` menghasilkan artifact lengkap.
3. Acceptance mapping cocok dengan acceptance criteria.
4. Risk tier ditentukan dan human gate dipatuhi bila medium/high.
5. Worktree bersih sebelum run final — worktree kotor melepaskan hasil dari commit.

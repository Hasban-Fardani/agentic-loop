# AGENTS.md — AEP project pointer

Baca file ini sebelum kerja:

- `GOALS.md` — outcome, non-goal, boundary, scope, risk.
- `WORKFLOW.md` — Goal → Plan → Tasklist → evidence.
- `CONVENTIONS.md` — convention yang sudah disetujui owner.
- `CHECKLIST.md` — checklist sebelum laporan selesai.

Jalankan `al goals validate` sebelum Plan. Satu Plan aktif per Goal. Tasklist
serial sebagai default; paralel hanya jika DAG, path, output, dan shared state
terbukti disjoint.

Jalankan `al goals start` sebelum coding dan `al goals verify` sebelum klaim selesai.
Low risk boleh autonomous setelah PASS. Medium butuh human review. High butuh
human approval terikat commit SHA. UNKNOWN selalu blocking.

Jangan merge, approve, force-push, deploy production, membaca secret production,
atau menyentuh forbidden path.

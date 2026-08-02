# GitHub Setup — Human-Owned Controls

`agentic-loop` tidak mengubah branch protection atau memberi approval sendiri.
Pemilik repository harus mengatur ini di GitHub UI/API:

- protect `main`;
- require evidence workflow check;
- require branch to be up to date before merge;
- disallow force-push;
- require human review untuk perubahan medium;
- require explicit approval untuk perubahan high-risk;
- pastikan token agent tidak punya permission merge, approve, deploy, atau
  mengubah branch protection;
- gunakan PR head SHA sebagai objek review.

Approval high-risk harus mengikat:

```text
approval_ref
approved_head_sha
reviewer identity
approval timestamp
```

Push baru membatalkan approval lama. Pending approval bukan PASS; verifier
menghasilkan `UNKNOWN` dan merge tetap blocked.

CI memanggil `bin/al` langsung agar `PASS=0`, `FAIL=1`, dan `UNKNOWN=2` tidak
terpipihkan oleh `make`. `.github/workflows/evidence.yml` menjadi verifier
independen; chat, memory agent, dan klaim teks bukan evidence.

## Checklist perubahan policy

Setiap perubahan ke workflow, policy, evidence adapter, risk rules, atau branch
protection diperlakukan high-risk dan perlu approval eksplisit.

Jangan menyimpan token di file ini. Credential hanya lewat environment/secret
store GitHub.

## Existing upstream references

Skill reasoning tidak disalin ke repo ini. Gunakan upstream yang terdokumentasi di
README dan manifest `al integrate`; local code hanya memegang enforcement,
artifact, scope, dan tri-state evidence.

- Superpowers — planning/TDD/review/worktrees.
- Ponytail — YAGNI/over-engineering review.
- Addy Osmani agent-skills — ADR/source-driven/adversarial review.
- Agent-Reach — optional freshness/web research.
- Context7 — optional current library documentation.

Referensi bukan bukti bahwa dependency tersedia. Tool required yang unavailable
menghasilkan `UNKNOWN`.

## Verification

```bash
./bin/al selftest ci_contract
./bin/al selftest
```

Jalankan dari checkout target. Jangan gunakan `make gate` sebagai required GitHub
check.

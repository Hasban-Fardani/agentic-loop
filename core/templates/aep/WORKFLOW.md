# AEP Workflow

```text
Goal brainstorming → readiness PASS → satu Plan aktif → Tasklist DAG validation
→ goals start → discovery → task execution → task DoD → scope/evidence → review
→ GitHub merge
```

Planner membuat Goal dan Plan. Coder membaca kontrak immutable dan mengerjakan
Tasklist. Reviewer mengecek DoD, scope, risk, dan evidence. CI mengulang validasi
secara independen. Chat bukan approval channel.

Medium wajib human review. High wajib approval eksplisit terikat `approved_head_sha`.
Plan tidak executable jika approval high-risk pending. Task dependency FAIL atau
UNKNOWN memblokir task berikutnya. Parallel ambiguity menghasilkan UNKNOWN.

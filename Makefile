# Titik masuk kanonik untuk manusia dan tooling.
#
# PENTING: `make` mengembalikan 2 untuk setiap recipe yang gagal, jadi ia TIDAK
# dapat membawa kontrak tri-state evidence gate (PASS=0 FAIL=1 UNKNOWN=2).
# CI dan automation wajib memanggil `bin/al run` langsung. Target `gate` di sini
# hanya untuk manusia; ia sengaja mencetak decision, bukan mengandalkan exit code.
.POSIX:
.PHONY: help test lint check gate decision doctor install uninstall clean

help: ## daftar target
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / -- /'

test: ## test suite toolkit ini sendiri (pass/fail biner)
	@./bin/al selftest

lint: ## syntax check semua shell + shellcheck bila ada
	@for s in bin/al install.sh core/lib/*.sh core/cmd/*.sh \
	          core/templates/adapters/*.sh tests/*.sh; do \
	  bash -n "$$s" || exit 1; \
	done
	@command -v shellcheck >/dev/null 2>&1 \
	  && shellcheck -S warning -e SC1091,SC2317 bin/al install.sh core/lib/*.sh core/cmd/*.sh \
	  || echo "lint: shellcheck absen, bash -n saja (degraded)"

check: lint test ## lint + test — jalankan ini sebelum commit

gate: ## evidence gate di repo ini; cetak decision, jangan andalkan exit make
	@./bin/al run standard || true
	@./bin/al decision

decision: ## decision + flags dari artifact terakhir
	@./bin/al decision

doctor: ## config efektif, tool, harness, cek .env safety
	@./bin/al doctor

install: ## pasang skill ke harness yang terdeteksi
	@./install.sh

uninstall: ## lepas skill dari harness
	@./install.sh --uninstall

clean: ## hapus log kedaluwarsa; artifact dipertahankan
	@./bin/al clean

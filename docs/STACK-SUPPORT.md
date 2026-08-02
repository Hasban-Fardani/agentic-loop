# Dukungan stack dan framework

Satu set adapter untuk semua repo. Yang berubah antar-proyek adalah *command yang
diturunkan*, bukan file yang harus diedit.

Sumber: `core/lib/detect.sh`. Test: `tests/detect_test.sh` (60 assert).

## Dua properti yang lebih penting daripada panjang daftar

**1. Marker framework mengalahkan manifest generik.**

Repo polyglot adalah norma. Laravel 11 mengirim `package.json` untuk Vite, Rails
untuk jsbundling, Django untuk Tailwind. Kalau urutan pemeriksaan file yang
menentukan stack, repo Laravel akan terdeteksi sebagai Node dan gate utamanya
menjadi `npm test` — bukan Pest.

Karena itu marker yang hanya ada kalau framework-nya benar-benar dipakai
(`artisan`, `bin/rails`, `manage.py`, `mix.exs`, `deno.json`) diperiksa lebih
dulu dan menentukan stack primer.

**2. Command hanya dipancarkan kalau tool-nya benar-benar ada.**

Tebakan yang salah lebih buruk daripada tidak menebak:

- `npm run lint` di repo tanpa script `lint` → exit 1, tampak seperti kode gagal
  lint padahal linter-nya tidak ada.
- `./vendor/bin/phpunit` di repo Laravel 11 → exit 127, dan `al run` memetakan
  itu ke `UNKNOWN`. Budget infra recovery habis untuk kesalahan tebakan kita.

Jadi setiap command diprobe lebih dulu: script di `package.json`, binary di
`vendor/bin/`, target di `Makefile`, wrapper `mvnw`/`gradlew`. Kalau tidak ada,
step mengumumkan `no_op` beserta nama variabel yang bisa di-set.

## Stack

| Stack | Dideteksi dari | setup | test | lint |
|---|---|---|---|---|
| node | `package.json` | `<pm> install` | script `test` | script `lint` → `typecheck` |
| deno | `deno.json` | `deno cache` | `deno test -A` | `deno lint` |
| php | `composer.json` | `composer install` | pest → phpunit → codecept | pint → php-cs-fixer → phpcs → phpstan → psalm |
| python | `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile` | uv → poetry → pipenv → pip | `manage.py test` (Django) / `pytest` | ruff → flake8 |
| ruby | `Gemfile` | `bundle install` | `bin/rails test` / rspec / rake | rubocop |
| go | `go.mod` | `go mod download` | `go test ./...` | golangci-lint → `go vet` |
| rust | `Cargo.toml` | `cargo fetch` | `cargo test --locked` | `cargo clippy` |
| java | `pom.xml` | `mvnw`/`mvn` | `mvn test` | — |
| gradle | `build.gradle[.kts]` | `gradlew`/`gradle` | `gradle test` | — |
| scala | `build.sbt` | `sbt update` | `sbt test` | — |
| dotnet | `*.csproj`, `*.sln`, `*.fsproj` | `dotnet restore` | `dotnet test` | `dotnet format --verify-no-changes` |
| elixir | `mix.exs` | `mix deps.get` | `mix test` | credo → `mix format --check` |
| dart | `pubspec.yaml` | `flutter`/`dart pub get` | `flutter`/`dart test` | `analyze` |
| swift | `Package.swift` | `swift package resolve` | `swift test` | — |
| cmake | `CMakeLists.txt`, `meson.build` | `cmake -S . -B build` | `ctest` | — |
| zig | `build.zig` | — | `zig build test` | `zig fmt --check` |
| make | `Makefile` | target `setup` | target `test` | target `lint` |

Package manager Node mengikuti lockfile: `bun.lockb` → bun, `pnpm-lock.yaml` →
pnpm, `yarn.lock` → yarn, sisanya npm. Tidak ada asumsi npm.

## Framework

Dikenali untuk memilih command yang tepat dan untuk muncul di pesan `no_op`.

| Stack | Framework |
|---|---|
| php | laravel (`artisan`), symfony (`bin/console`), thinkphp |
| python | django (`manage.py`), fastapi, flask |
| ruby | rails (`bin/rails`), sinatra |
| elixir | phoenix |
| dart | flutter |
| java/gradle | spring-boot, android |
| node | nextjs, nuxt, sveltekit, astro, remix, angular, nestjs, expo, react-native, express, fastify, vue, react, vite |

Framework hanya mengubah command bila memang perlu. Django memakai
`manage.py test`, bukan `pytest`. Laravel memakai Pint dengan `--test` supaya ia
memeriksa alih-alih menulis ulang file.

## Stack sekunder

Aset frontend di repo backend ditangani terpisah:

```text
Laravel + Vite  → primer php, sekunder node
setup:  composer install  DAN  npm install
build:  (php no_op)       DAN  npm run build
test:   ./vendor/bin/pest      ← hanya primer
```

Test sekunder sengaja tidak dijalankan. Mencampur output test PHP dan JS
mengaburkan mana yang gagal, dan test primer adalah milik bahasa utama. Kalau
memang butuh keduanya, jadikan step terpisah di `.agent/evidence.yaml`.

## Override

Semua hasil deteksi hanya default. Environment selalu menang:

```bash
# .env di repo
AL_CMD_TEST=./vendor/bin/pest --parallel
AL_CMD_LINT=./vendor/bin/phpstan analyse --level=8
AL_STACK=php          # paksa stack kalau deteksi salah
AL_FRAMEWORK=laravel  # paksa framework
```

Periksa hasil efektifnya:

```bash
al doctor
```

## Menambah stack baru

1. Tambah marker atau manifest di `detect.sh`. Marker framework masuk ke
   `_detect_by_marker`; manifest generik masuk ke fallback di bawahnya.
2. Tambah blok `case` untuk command-nya. Gunakan `al_first_bin`,
   `al_first_script`, atau `al_make_target` untuk memprobe — jangan berasumsi.
3. Tambah kasus di `tests/detect_test.sh`. Minimal: stack terdeteksi benar, dan
   command kosong bila tool tidak ada.
4. `./bin/al selftest detect`

Aturan yang tidak boleh dilanggar: kalau tool tidak ada, hasilnya string kosong,
bukan tebakan. `al_step` yang mengubahnya menjadi `no_op` beralasan.

## Belum diverifikasi

- Deteksi dijalankan terhadap fixture minimal, bukan repo produksi tiap
  framework. Yang terbukti: command yang benar diturunkan dari marker yang ada.
  Yang belum: bahwa command itu lulus di repo Laravel/Rails/Spring sungguhan
  dengan dependency lengkap.
- `mix.exs`, `Gemfile`, `pyproject.toml` diperiksa dengan `grep`, bukan parser.
  Dependency yang disebut di komentar bisa memicu false positive.
- Monorepo dengan beberapa stack di subdirektori berbeda belum ditangani; deteksi
  hanya melihat root repo.

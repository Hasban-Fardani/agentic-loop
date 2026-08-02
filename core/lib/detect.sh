#!/usr/bin/env bash
# Deteksi stack + framework, lalu turunkan command yang benar-benar ada.
#
# Tiga aturan yang membentuk file ini:
#
# 1. Repo polyglot adalah norma, bukan pengecualian. Laravel 11 mengirim
#    package.json untuk Vite; Rails punya package.json untuk jsbundling; Django
#    punya package.json untuk Tailwind. Urutan pemeriksaan file TIDAK boleh
#    menentukan stack primer — marker framework (artisan, manage.py, mix.exs)
#    lebih kuat daripada manifest generik.
#
# 2. Jangan pernah mengemisikan command yang tool-nya tidak ada. Tebakan salah
#    menghasilkan exit 127, dan run.sh memetakan itu ke UNKNOWN — budget infra
#    recovery terpakai untuk kesalahan kita, bukan masalah infrastruktur.
#    Lebih jujur: no_op yang dinyatakan beserta alasannya.
#
# 3. Stack sekunder tetap dijalankan bila ada. Repo Laravel dengan aset Vite
#    perlu `composer install` DAN `npm install`, bukan salah satu.
#
# Presedensi per step: AL_CMD_<STEP> dari env/.env > yang terdeteksi > no_op.

[ -n "${_AL_DETECT_LOADED:-}" ] && return 0
_AL_DETECT_LOADED=1

_d()   { [ -f "$AL_REPO_ROOT/$1" ]; }
_dir() { [ -d "$AL_REPO_ROOT/$1" ]; }
_any() { for _f in "$@"; do [ -f "$AL_REPO_ROOT/$_f" ] && return 0; done; return 1; }
_grep(){ [ -f "$AL_REPO_ROOT/$1" ] && grep -qs "$2" "$AL_REPO_ROOT/$1"; }

# --- helper manifest ---------------------------------------------------------

al_node_pm() {
  if   _any bun.lockb bun.lock;  then echo bun
  elif _d pnpm-lock.yaml;        then echo pnpm
  elif _d yarn.lock;             then echo yarn
  else echo npm
  fi
}

al_has_script() {
  _d package.json || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg s "$1" '.scripts[$s] // empty' "$AL_REPO_ROOT/package.json" >/dev/null 2>&1
}

# al_has_dep NAME — terdaftar di manifest, bukan sekadar terpasang.
al_has_dep() {
  case "${2:-$AL_STACK}" in
    node|deno)
      _d package.json && command -v jq >/dev/null 2>&1 || return 1
      jq -e --arg d "$1" \
        '((.dependencies//{})+(.devDependencies//{})+(.peerDependencies//{}))[$d] // empty' \
        "$AL_REPO_ROOT/package.json" >/dev/null 2>&1 ;;
    php)
      _d composer.json && command -v jq >/dev/null 2>&1 || return 1
      jq -e --arg d "$1" '((.require//{})+(."require-dev"//{}))[$d] // empty' \
        "$AL_REPO_ROOT/composer.json" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

al_make_target() { _d Makefile && grep -qE "^$1:" "$AL_REPO_ROOT/Makefile"; }

# al_first_bin REL... — binary pertama yang benar-benar ada. Ini yang mencegah
# `./vendor/bin/phpunit` di repo yang sebenarnya memakai Pest.
al_first_bin() {
  for _b in "$@"; do
    [ -x "$AL_REPO_ROOT/$_b" ] && { printf '%s' "$_b"; return 0; }
  done
  return 1
}

# al_script_cmd NAME — "<pm> run NAME" hanya bila script-nya ada.
al_script_cmd() {
  al_has_script "$1" || return 1
  case "$1" in
    test|start) printf '%s %s' "$(al_node_pm)" "$1" ;;   # npm test, bukan npm run test
    *)          printf '%s run %s' "$(al_node_pm)" "$1" ;;
  esac
}

# al_first_script NAME... — script pertama yang ada, sebagai command siap pakai.
al_first_script() {
  for _s in "$@"; do
    _c=$(al_script_cmd "$_s") && { printf '%s' "$_c"; return 0; }
  done
  return 1
}

# --- framework: marker kuat menentukan stack primer --------------------------
#
# Setiap entri: "framework:stack:marker-file". Marker adalah file yang hanya ada
# kalau framework itu benar-benar dipakai, sehingga aman mengalahkan manifest
# generik yang mungkin ada karena toolchain aset.

_detect_by_marker() {
  # PHP — artisan/bin console hanya ada di app-nya, bukan di paket aset.
  _d artisan                        && { AL_FRAMEWORK=laravel;   AL_STACK=php;    return 0; }
  _d bin/console                    && { AL_FRAMEWORK=symfony;   AL_STACK=php;    return 0; }
  _d think                          && { AL_FRAMEWORK=thinkphp;  AL_STACK=php;    return 0; }
  # Python
  _d manage.py                      && { AL_FRAMEWORK=django;    AL_STACK=python; return 0; }
  # Ruby
  _d bin/rails                      && { AL_FRAMEWORK=rails;     AL_STACK=ruby;   return 0; }
  _grep Gemfile 'rails'             && { AL_FRAMEWORK=rails;     AL_STACK=ruby;   return 0; }
  _grep Gemfile 'sinatra'           && { AL_FRAMEWORK=sinatra;   AL_STACK=ruby;   return 0; }
  # Elixir
  _grep mix.exs 'phoenix'           && { AL_FRAMEWORK=phoenix;   AL_STACK=elixir; return 0; }
  _d mix.exs                        && { AL_FRAMEWORK=;          AL_STACK=elixir; return 0; }
  # Dart / Flutter
  _grep pubspec.yaml 'flutter'      && { AL_FRAMEWORK=flutter;   AL_STACK=dart;   return 0; }
  _d pubspec.yaml                   && { AL_FRAMEWORK=;          AL_STACK=dart;   return 0; }
  # Java / Kotlin / Scala
  _any pom.xml                      && {
    _grep pom.xml 'spring-boot'     && AL_FRAMEWORK=spring-boot
    AL_STACK=java; return 0; }
  _any build.gradle build.gradle.kts && {
    _grep build.gradle 'spring-boot' || _grep build.gradle.kts 'spring-boot' \
      && AL_FRAMEWORK=spring-boot
    _grep build.gradle 'com.android' || _grep build.gradle.kts 'com.android' \
      && AL_FRAMEWORK=android
    AL_STACK=gradle; return 0; }
  _d build.sbt                      && { AL_FRAMEWORK=;          AL_STACK=scala;  return 0; }
  # .NET
  for _f in "$AL_REPO_ROOT"/*.sln "$AL_REPO_ROOT"/*.csproj "$AL_REPO_ROOT"/*.fsproj; do
    [ -f "$_f" ] && { AL_FRAMEWORK=dotnet; AL_STACK=dotnet; return 0; }
  done
  # Swift
  _d Package.swift                  && { AL_FRAMEWORK=;          AL_STACK=swift;  return 0; }
  # Deno — deno.json menang atas package.json karena runtime-nya beda.
  _any deno.json deno.jsonc         && { AL_FRAMEWORK=;          AL_STACK=deno;   return 0; }
  return 1
}

al_set_default AL_STACK ""
al_set_default AL_FRAMEWORK ""

if [ -z "$AL_STACK" ]; then
  AL_FRAMEWORK_AUTO=""
  if _detect_by_marker; then
    AL_FRAMEWORK_AUTO="$AL_FRAMEWORK"
  else
    # Tanpa marker framework, jatuh ke manifest. Urutan di sini pun disengaja:
    # composer/go/cargo lebih spesifik daripada package.json yang bisa muncul
    # di repo bahasa apa pun untuk keperluan tooling.
    if   _d composer.json;  then AL_STACK=php
    elif _d go.mod;         then AL_STACK=go
    elif _d Cargo.toml;     then AL_STACK=rust
    elif _any pyproject.toml requirements.txt setup.py Pipfile; then AL_STACK=python
    elif _d Gemfile;        then AL_STACK=ruby
    elif _d package.json;   then AL_STACK=node
    elif _any CMakeLists.txt meson.build; then AL_STACK=cmake
    elif _d build.zig;      then AL_STACK=zig
    elif _d Makefile;       then AL_STACK=make
    else AL_STACK=unknown
    fi
  fi
fi

# Framework Node dideteksi setelah stack diketahui, karena butuh al_has_dep.
if [ -z "$AL_FRAMEWORK" ] && [ "$AL_STACK" = node ]; then
  if   _any next.config.js next.config.mjs next.config.ts || al_has_dep next node;        then AL_FRAMEWORK=nextjs
  elif _any nuxt.config.ts nuxt.config.js  || al_has_dep nuxt node;                        then AL_FRAMEWORK=nuxt
  elif _d svelte.config.js || al_has_dep '@sveltejs/kit' node;                             then AL_FRAMEWORK=sveltekit
  elif _any astro.config.mjs astro.config.ts || al_has_dep astro node;                     then AL_FRAMEWORK=astro
  elif _d remix.config.js || al_has_dep '@remix-run/dev' node;                             then AL_FRAMEWORK=remix
  elif _any angular.json  || al_has_dep '@angular/core' node;                              then AL_FRAMEWORK=angular
  elif al_has_dep '@nestjs/core' node;                                                     then AL_FRAMEWORK=nestjs
  elif al_has_dep expo node;                                                               then AL_FRAMEWORK=expo
  elif al_has_dep react-native node;                                                       then AL_FRAMEWORK=react-native
  elif al_has_dep express node;                                                            then AL_FRAMEWORK=express
  elif al_has_dep fastify node;                                                            then AL_FRAMEWORK=fastify
  elif al_has_dep vue node;                                                                then AL_FRAMEWORK=vue
  elif al_has_dep react node;                                                              then AL_FRAMEWORK=react
  elif al_has_dep vite node;                                                               then AL_FRAMEWORK=vite
  fi
fi
if [ -z "$AL_FRAMEWORK" ] && [ "$AL_STACK" = python ]; then
  if   _grep pyproject.toml 'fastapi' || _grep requirements.txt 'fastapi'; then AL_FRAMEWORK=fastapi
  elif _grep pyproject.toml 'flask'   || _grep requirements.txt 'flask';   then AL_FRAMEWORK=flask
  fi
fi
export AL_STACK AL_FRAMEWORK

# --- stack sekunder ----------------------------------------------------------
#
# Aset frontend di repo backend itu umum. Kalau package.json ada tetapi stack
# primer bukan node, script build/lint-nya tetap layak dijalankan.

AL_STACK_SECONDARY=""
if [ "$AL_STACK" != node ] && [ "$AL_STACK" != deno ] && _d package.json; then
  AL_STACK_SECONDARY=node
fi
export AL_STACK_SECONDARY

# --- command per stack -------------------------------------------------------

case "$AL_STACK" in
  node|deno)
    if [ "$AL_STACK" = deno ]; then
      al_set_default AL_CMD_SETUP "deno cache --reload ."
      al_set_default AL_CMD_BUILD ""
      al_set_default AL_CMD_TEST  "deno test -A"
      al_set_default AL_CMD_LINT  "deno lint"
      al_set_default AL_CMD_SECURITY ""
    else
      pm="$(al_node_pm)"
      al_set_default AL_CMD_SETUP "$pm install"
      al_set_default AL_CMD_BUILD "$(al_first_script build compile || true)"
      al_set_default AL_CMD_TEST  "$(al_first_script test test:unit || true)"
      # typecheck lebih baik daripada tidak ada gate sama sekali.
      al_set_default AL_CMD_LINT  "$(al_first_script lint typecheck type-check tsc || true)"
      al_set_default AL_CMD_SECURITY "$pm audit --audit-level=high"
      unset pm
    fi
    ;;

  php)
    al_set_default AL_CMD_SETUP "composer install --no-interaction --prefer-dist"
    al_set_default AL_CMD_BUILD ""
    # Laravel 11 mengirim Pest, bukan PHPUnit. Probe apa yang ada.
    if t=$(al_first_bin vendor/bin/pest vendor/bin/phpunit vendor/bin/codecept); then
      al_set_default AL_CMD_TEST "./$t"
    else
      al_set_default AL_CMD_TEST ""
    fi
    if l=$(al_first_bin vendor/bin/pint vendor/bin/php-cs-fixer vendor/bin/phpcs vendor/bin/phpstan vendor/bin/psalm); then
      case "$l" in
        */pint)         al_set_default AL_CMD_LINT "./$l --test" ;;
        */php-cs-fixer) al_set_default AL_CMD_LINT "./$l fix --dry-run --diff" ;;
        */phpstan)      al_set_default AL_CMD_LINT "./$l analyse --no-progress" ;;
        */psalm)        al_set_default AL_CMD_LINT "./$l --no-progress" ;;
        *)              al_set_default AL_CMD_LINT "./$l" ;;
      esac
    else
      al_set_default AL_CMD_LINT ""
    fi
    al_set_default AL_CMD_SECURITY "composer audit"
    unset t l
    ;;

  python)
    if   _d uv.lock;          then al_set_default AL_CMD_SETUP "uv sync"
    elif _d poetry.lock;      then al_set_default AL_CMD_SETUP "poetry install"
    elif _d Pipfile.lock;     then al_set_default AL_CMD_SETUP "pipenv sync"
    elif _d requirements.txt; then al_set_default AL_CMD_SETUP "python -m pip install -r requirements.txt"
    else                           al_set_default AL_CMD_SETUP "python -m pip install -e ."
    fi
    al_set_default AL_CMD_BUILD ""
    if [ "$AL_FRAMEWORK" = django ]; then
      al_set_default AL_CMD_TEST "python manage.py test"
    else
      al_set_default AL_CMD_TEST "python -m pytest -q"
    fi
    if _any ruff.toml .ruff.toml || _grep pyproject.toml 'ruff'; then
      al_set_default AL_CMD_LINT "python -m ruff check ."
    elif _any .flake8 setup.cfg tox.ini; then
      al_set_default AL_CMD_LINT "python -m flake8"
    else
      al_set_default AL_CMD_LINT ""
    fi
    al_set_default AL_CMD_SECURITY ""
    ;;

  ruby)
    al_set_default AL_CMD_SETUP "bundle install"
    al_set_default AL_CMD_BUILD ""
    if [ "$AL_FRAMEWORK" = rails ]; then
      al_set_default AL_CMD_TEST "bin/rails test"
    elif _grep Gemfile 'rspec'; then
      al_set_default AL_CMD_TEST "bundle exec rspec"
    else
      al_set_default AL_CMD_TEST "bundle exec rake test"
    fi
    _grep Gemfile 'rubocop' \
      && al_set_default AL_CMD_LINT "bundle exec rubocop" \
      || al_set_default AL_CMD_LINT ""
    _grep Gemfile 'brakeman' \
      && al_set_default AL_CMD_SECURITY "bundle exec brakeman -q" \
      || al_set_default AL_CMD_SECURITY "bundle audit check --update"
    ;;

  go)
    al_set_default AL_CMD_SETUP "go mod download"
    al_set_default AL_CMD_BUILD "go build ./..."
    al_set_default AL_CMD_TEST  "go test ./..."
    if _any .golangci.yml .golangci.yaml && command -v golangci-lint >/dev/null 2>&1; then
      al_set_default AL_CMD_LINT "golangci-lint run"
    else
      al_set_default AL_CMD_LINT "go vet ./..."
    fi
    al_set_default AL_CMD_SECURITY ""
    ;;

  rust)
    al_set_default AL_CMD_SETUP "cargo fetch"
    al_set_default AL_CMD_BUILD "cargo build --locked"
    al_set_default AL_CMD_TEST  "cargo test --locked"
    al_set_default AL_CMD_LINT  "cargo clippy -- -D warnings"
    command -v cargo-audit >/dev/null 2>&1 \
      && al_set_default AL_CMD_SECURITY "cargo audit" \
      || al_set_default AL_CMD_SECURITY ""
    ;;

  java)   # maven
    mvnw="mvn"; [ -x "$AL_REPO_ROOT/mvnw" ] && mvnw="./mvnw"
    al_set_default AL_CMD_SETUP "$mvnw -q -B dependency:go-offline"
    al_set_default AL_CMD_BUILD "$mvnw -q -B -DskipTests package"
    al_set_default AL_CMD_TEST  "$mvnw -B test"
    al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    unset mvnw
    ;;

  gradle)
    gw="gradle"; [ -x "$AL_REPO_ROOT/gradlew" ] && gw="./gradlew"
    al_set_default AL_CMD_SETUP "$gw --quiet dependencies"
    al_set_default AL_CMD_BUILD "$gw --quiet assemble"
    al_set_default AL_CMD_TEST  "$gw test"
    al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    unset gw
    ;;

  scala)
    al_set_default AL_CMD_SETUP "sbt update"
    al_set_default AL_CMD_BUILD "sbt compile"
    al_set_default AL_CMD_TEST  "sbt test"
    al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    ;;

  dotnet)
    al_set_default AL_CMD_SETUP "dotnet restore"
    al_set_default AL_CMD_BUILD "dotnet build --no-restore"
    al_set_default AL_CMD_TEST  "dotnet test --no-build"
    al_set_default AL_CMD_LINT  "dotnet format --verify-no-changes"
    al_set_default AL_CMD_SECURITY "dotnet list package --vulnerable"
    ;;

  elixir)
    al_set_default AL_CMD_SETUP "mix deps.get"
    al_set_default AL_CMD_BUILD "mix compile --warnings-as-errors"
    al_set_default AL_CMD_TEST  "mix test"
    _grep mix.exs 'credo' \
      && al_set_default AL_CMD_LINT "mix credo --strict" \
      || al_set_default AL_CMD_LINT "mix format --check-formatted"
    al_set_default AL_CMD_SECURITY ""
    ;;

  dart)
    if [ "$AL_FRAMEWORK" = flutter ]; then
      al_set_default AL_CMD_SETUP "flutter pub get"
      al_set_default AL_CMD_TEST  "flutter test"
      al_set_default AL_CMD_LINT  "flutter analyze"
      al_set_default AL_CMD_BUILD ""
    else
      al_set_default AL_CMD_SETUP "dart pub get"
      al_set_default AL_CMD_TEST  "dart test"
      al_set_default AL_CMD_LINT  "dart analyze"
      al_set_default AL_CMD_BUILD ""
    fi
    al_set_default AL_CMD_SECURITY ""
    ;;

  swift)
    al_set_default AL_CMD_SETUP "swift package resolve"
    al_set_default AL_CMD_BUILD "swift build"
    al_set_default AL_CMD_TEST  "swift test"
    al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    ;;

  cmake)
    al_set_default AL_CMD_SETUP "cmake -S . -B build"
    al_set_default AL_CMD_BUILD "cmake --build build"
    al_set_default AL_CMD_TEST  "ctest --test-dir build --output-on-failure"
    al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    ;;

  zig)
    al_set_default AL_CMD_SETUP ""
    al_set_default AL_CMD_BUILD "zig build"
    al_set_default AL_CMD_TEST  "zig build test"
    al_set_default AL_CMD_LINT  "zig fmt --check ."
    al_set_default AL_CMD_SECURITY ""
    ;;

  make)
    al_set_default AL_CMD_SETUP    "$(al_make_target setup && echo 'make setup')"
    al_set_default AL_CMD_BUILD    "$(al_make_target build && echo 'make build')"
    al_set_default AL_CMD_TEST     "$(al_make_target test  && echo 'make test')"
    al_set_default AL_CMD_LINT     "$(al_make_target lint  && echo 'make lint')"
    al_set_default AL_CMD_SECURITY ""
    ;;

  *)
    al_set_default AL_CMD_SETUP ""; al_set_default AL_CMD_BUILD ""
    al_set_default AL_CMD_TEST  ""; al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    ;;
esac

# Stack sekunder: aset frontend di repo backend. Setup dan build ikut, tetapi
# test TIDAK — test primer adalah milik bahasa utama, dan menggabungkan keduanya
# akan mengaburkan sumber kegagalan.
if [ "$AL_STACK_SECONDARY" = node ]; then
  _pm2="$(al_node_pm)"
  al_set_default AL_CMD_SETUP_SECONDARY "$_pm2 install"
  al_set_default AL_CMD_BUILD_SECONDARY "$(al_first_script build || true)"
  unset _pm2
else
  al_set_default AL_CMD_SETUP_SECONDARY ""
  al_set_default AL_CMD_BUILD_SECONDARY ""
fi

# al_step CMD_STRING STEP_NAME — jalankan, atau umumkan no-op secara eksplisit.
# no-op sengaja exit 0 dan menyebut alasannya; skip diam-diam adalah cara
# evidence gate berbohong.
al_step() {
  if [ -z "$1" ]; then
    printf '%s: no_op (tidak ada command untuk stack=%s%s; set AL_CMD_%s untuk override)\n' \
      "$2" "$AL_STACK" "${AL_FRAMEWORK:+/$AL_FRAMEWORK}" \
      "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
    return 0
  fi
  printf '%s: %s\n' "$2" "$1"
  # shellcheck disable=SC2086 # command string sengaja di-split jadi argumen
  eval "$1"
}

# al_step_with_secondary CMD SECONDARY_CMD STEP — jalankan primer lalu sekunder.
# Dipakai setup/build supaya repo Laravel+Vite mendapat keduanya.
al_step_with_secondary() {
  _rc=0
  al_step "$1" "$3" || _rc=$?
  if [ -n "$2" ]; then
    printf '%s (secondary/%s): %s\n' "$3" "$AL_STACK_SECONDARY" "$2"
    eval "$2" || _rc=$?
  fi
  return "$_rc"
}

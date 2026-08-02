#!/usr/bin/env bash
# Deteksi stack/framework. Yang diuji bukan "tebakannya bagus", tapi dua
# properti yang bisa salah dan merusak gate:
#   1. repo polyglot tidak salah stack (Laravel punya package.json untuk Vite)
#   2. command yang dipancarkan hanya untuk tool yang benar-benar ada
. "${BASH_SOURCE[0]%/*}/lib.sh"

# mkproj NAME — repo git kosong di sandbox
mkproj() {
  local d="$TEST_TMP/proj-$1"
  mkdir -p "$d"
  ( cd "$d"; git init -q; git config user.name t; git config user.email t@example.test )
  printf '%s' "$d"
}

# det DIR VAR — nilai satu variabel hasil deteksi
det() {
  AL_REPO_ROOT="$1" bash -c ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; printf '%s' \"\$$2\""
}

echo "# stack primer"
for spec in \
  'php:composer.json:{}' \
  'go:go.mod:module x' \
  'rust:Cargo.toml:[package]' \
  'python:pyproject.toml:[project]' \
  'ruby:Gemfile:source "x"' \
  'node:package.json:{}' \
  'elixir:mix.exs:defmodule M do end' \
  'dart:pubspec.yaml:name: app' \
  'swift:Package.swift:// swift-tools' \
  'zig:build.zig:pub fn build() void {}' \
  'cmake:CMakeLists.txt:project(x)' \
  'make:Makefile:test:' ; do
  want="${spec%%:*}"; rest="${spec#*:}"; file="${rest%%:*}"; body="${rest#*:}"
  d="$(mkproj "$want")"; printf '%s\n' "$body" > "$d/$file"
  assert_eq "stack $want dari $file" "$want" "$(det "$d" AL_STACK)"
done

d="$(mkproj none)"
assert_eq "tanpa manifest -> unknown" unknown "$(det "$d" AL_STACK)"

echo "# .NET terdeteksi lewat glob, bukan nama file tetap"
d="$(mkproj dotnet)"; printf '<Project/>\n' > "$d/App.csproj"
assert_eq "csproj -> dotnet" dotnet "$(det "$d" AL_STACK)"

echo "# marker framework mengalahkan manifest generik"
# Regresi: Laravel 11 mengirim package.json untuk Vite. Urutan pemeriksaan file
# yang naif membuatnya terdeteksi sebagai repo Node dan menjalankan `npm test`
# sebagai gate utama, bukan Pest.
d="$(mkproj laravel)"
printf '{"require":{"laravel/framework":"^11"}}\n' > "$d/composer.json"
printf '{"devDependencies":{"vite":"^6"},"scripts":{"build":"vite build"}}\n' > "$d/package.json"
touch "$d/artisan"
assert_eq "artisan menang atas package.json" php "$(det "$d" AL_STACK)"
assert_eq "framework laravel dikenali"      laravel "$(det "$d" AL_FRAMEWORK)"
assert_eq "node menjadi stack sekunder"     node "$(det "$d" AL_STACK_SECONDARY)"

d="$(mkproj rails)"
printf 'source "x"\ngem "rails"\n' > "$d/Gemfile"
printf '{"scripts":{"build":"esbuild"}}\n' > "$d/package.json"
mkdir -p "$d/bin"; touch "$d/bin/rails"
assert_eq "bin/rails menang atas package.json" ruby "$(det "$d" AL_STACK)"
assert_eq "framework rails dikenali"           rails "$(det "$d" AL_FRAMEWORK)"

d="$(mkproj django)"
printf '[project]\ndependencies=["django"]\n' > "$d/pyproject.toml"
printf '{"devDependencies":{"tailwindcss":"^4"}}\n' > "$d/package.json"
touch "$d/manage.py"
assert_eq "manage.py menang atas package.json" python "$(det "$d" AL_STACK)"
assert_eq "test memakai manage.py" "python manage.py test" "$(det "$d" AL_CMD_TEST)"

d="$(mkproj deno)"
printf '{"tasks":{}}\n' > "$d/deno.json"; printf '{}\n' > "$d/package.json"
assert_eq "deno.json menang atas package.json" deno "$(det "$d" AL_STACK)"

echo "# framework node"
for spec in \
  'nextjs:next.config.js' \
  'nuxt:nuxt.config.ts' \
  'sveltekit:svelte.config.js' \
  'astro:astro.config.mjs' \
  'angular:angular.json' ; do
  want="${spec%%:*}"; file="${spec#*:}"
  d="$(mkproj "fw-$want")"; printf '{}\n' > "$d/package.json"; printf '{}\n' > "$d/$file"
  assert_eq "framework $want dari $file" "$want" "$(det "$d" AL_FRAMEWORK)"
done
d="$(mkproj fw-nestjs)"
printf '{"dependencies":{"@nestjs/core":"^10"}}\n' > "$d/package.json"
assert_eq "framework dari dependency" nestjs "$(det "$d" AL_FRAMEWORK)"

echo "# package manager mengikuti lockfile"
for spec in 'npm:package-lock.json' 'pnpm:pnpm-lock.yaml' 'yarn:yarn.lock' 'bun:bun.lockb'; do
  want="${spec%%:*}"; lock="${spec#*:}"
  d="$(mkproj "pm-$want")"; printf '{"scripts":{"build":"x"}}\n' > "$d/package.json"; touch "$d/$lock"
  assert_eq "pm $want dari $lock" "$want install" "$(det "$d" AL_CMD_SETUP)"
done

echo "# JANGAN pancarkan command untuk script yang tidak ada"
# Regresi: `npm run lint` pada repo tanpa script lint keluar 1, dan itu tampak
# seperti kode yang gagal lint padahal linter-nya memang tidak ada.
d="$(mkproj noscripts)"; printf '{"name":"x"}\n' > "$d/package.json"
assert_eq "tanpa script build -> kosong" "" "$(det "$d" AL_CMD_BUILD)"
assert_eq "tanpa script lint -> kosong"  "" "$(det "$d" AL_CMD_LINT)"
d="$(mkproj withscripts)"
printf '{"scripts":{"build":"x","lint":"y","test":"z"}}\n' > "$d/package.json"
assert_eq "ada script build" "npm run build" "$(det "$d" AL_CMD_BUILD)"
assert_eq "ada script lint"  "npm run lint"  "$(det "$d" AL_CMD_LINT)"
# `npm test`, bukan `npm run test` — keduanya jalan, tapi yang pertama kanonik.
assert_eq "test tanpa 'run'" "npm test" "$(det "$d" AL_CMD_TEST)"
d="$(mkproj tsonly)"
printf '{"scripts":{"typecheck":"tsc --noEmit"}}\n' > "$d/package.json"
assert_eq "typecheck dipakai bila lint absen" "npm run typecheck" "$(det "$d" AL_CMD_LINT)"

echo "# PHP: probe binary yang benar-benar ada"
# Laravel 11 mengirim Pest, bukan PHPUnit. Menebak phpunit -> exit 127 -> UNKNOWN.
d="$(mkproj php-pest)"; printf '{}\n' > "$d/composer.json"
mkdir -p "$d/vendor/bin"; printf '#!/bin/sh\n' > "$d/vendor/bin/pest"; chmod +x "$d/vendor/bin/pest"
assert_eq "pest dipilih bila ada" "./vendor/bin/pest" "$(det "$d" AL_CMD_TEST)"
d="$(mkproj php-phpunit)"; printf '{}\n' > "$d/composer.json"
mkdir -p "$d/vendor/bin"; printf '#!/bin/sh\n' > "$d/vendor/bin/phpunit"; chmod +x "$d/vendor/bin/phpunit"
assert_eq "phpunit dipilih bila itu yang ada" "./vendor/bin/phpunit" "$(det "$d" AL_CMD_TEST)"
d="$(mkproj php-none)"; printf '{}\n' > "$d/composer.json"
assert_eq "tanpa runner -> kosong, bukan tebakan" "" "$(det "$d" AL_CMD_TEST)"
d="$(mkproj php-pint)"; printf '{}\n' > "$d/composer.json"
mkdir -p "$d/vendor/bin"; printf '#!/bin/sh\n' > "$d/vendor/bin/pint"; chmod +x "$d/vendor/bin/pint"
assert_eq "pint dipakai dengan --test" "./vendor/bin/pint --test" "$(det "$d" AL_CMD_LINT)"

echo "# Python: setup mengikuti lockfile yang dipakai repo"
for spec in 'uv.lock:uv sync' 'poetry.lock:poetry install' 'requirements.txt:python -m pip install -r requirements.txt'; do
  lock="${spec%%:*}"; want="${spec#*:}"
  d="$(mkproj "py-${lock%%.*}")"; printf '[project]\n' > "$d/pyproject.toml"; touch "$d/$lock"
  assert_eq "setup dari $lock" "$want" "$(det "$d" AL_CMD_SETUP)"
done

echo "# wrapper dipakai bila ada"
d="$(mkproj mvn-wrapper)"; printf '<project/>\n' > "$d/pom.xml"
touch "$d/mvnw"; chmod +x "$d/mvnw"
assert_contains "mvnw dipakai" "$(det "$d" AL_CMD_TEST)" "./mvnw"
d="$(mkproj mvn-plain)"; printf '<project/>\n' > "$d/pom.xml"
assert_contains "tanpa wrapper pakai mvn" "$(det "$d" AL_CMD_TEST)" "mvn "
d="$(mkproj gradle-wrapper)"; printf 'plugins {}\n' > "$d/build.gradle"
touch "$d/gradlew"; chmod +x "$d/gradlew"
assert_contains "gradlew dipakai" "$(det "$d" AL_CMD_TEST)" "./gradlew"

echo "# override env selalu menang"
d="$(mkproj override)"; printf '{"scripts":{"test":"vitest"}}\n' > "$d/package.json"
got=$(AL_REPO_ROOT="$d" AL_CMD_TEST="custom runner" bash -c \
  ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; printf '%s' \"\$AL_CMD_TEST\"")
assert_eq "AL_CMD_TEST mengalahkan deteksi" "custom runner" "$got"
got=$(AL_REPO_ROOT="$d" AL_STACK=php bash -c \
  ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; printf '%s' \"\$AL_STACK\"")
assert_eq "AL_STACK mengalahkan deteksi" php "$got"

echo "# no_op menyebut stack dan cara override"
d="$(mkproj noop)"; printf '{"name":"x"}\n' > "$d/package.json"
out=$(AL_REPO_ROOT="$d" bash -c \
  ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; al_step \"\$AL_CMD_LINT\" lint")
assert_contains "no_op menyebut alasan"      "$out" "no_op"
assert_contains "no_op menyebut stack"       "$out" "stack=node"
assert_contains "no_op menyebut cara override" "$out" "AL_CMD_LINT"

echo "# stack sekunder: setup+build ikut, test tidak"
d="$(mkproj secondary)"
printf '{"require":{"laravel/framework":"^11"}}\n' > "$d/composer.json"
printf '{"scripts":{"build":"vite build","test":"vitest"}}\n' > "$d/package.json"
touch "$d/artisan"
assert_eq "setup sekunder di-set" "npm install" "$(det "$d" AL_CMD_SETUP_SECONDARY)"
assert_eq "build sekunder di-set" "npm run build" "$(det "$d" AL_CMD_BUILD_SECONDARY)"
# Test sekunder sengaja TIDAK ada: mencampur test PHP dan JS mengaburkan sumber
# kegagalan, dan test primer adalah milik bahasa utama.
out=$(AL_REPO_ROOT="$d" bash -c \
  ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; printf '%s' \"\${AL_CMD_TEST_SECONDARY:-unset}\"")
assert_eq "tidak ada test sekunder" unset "$out"
out=$(AL_REPO_ROOT="$d" bash -c \
  ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh
   al_step_with_secondary 'echo P' 'echo S' setup")
assert_contains "primer dijalankan"  "$out" "P"
assert_contains "sekunder dijalankan" "$out" "S"
assert_contains "sekunder diberi label" "$out" "secondary/node"

echo "# repo murni node tidak punya stack sekunder"
d="$(mkproj purenode)"; printf '{}\n' > "$d/package.json"
assert_eq "node saja -> sekunder kosong" "" "$(det "$d" AL_STACK_SECONDARY)"

test_summary

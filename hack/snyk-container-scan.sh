#!/usr/bin/env bash
# Find every Dockerfile/Containerfile and Docker Compose file in the repository and run
# `snyk container test` against the images they produce or reference.
#
# Usage: hack/snyk-container-scan.sh [options] [root]
#
#   --list                     only print the discovered files
#   --base-only                don't build: scan the base image of each Dockerfile's final stage
#                              (what ships) and the images referenced by compose files instead
#   --all-stages               with --base-only, also scan builder-stage base images
#   --platform <os/arch>       platform to build and scan (default linux/amd64, what we ship)
#   --severity-threshold <s>   passed to snyk (low|medium|high|critical)
#   --json-dir <dir>           write one snyk JSON report per scanned image into <dir>
#   -h, --help                 show this help
#
# Snyk must be authenticated (`snyk auth`, or SNYK_TOKEN). `snyk` is used if installed,
# otherwise `npx --yes snyk`. Exits non-zero if any scan finds issues or fails.
# Compatible with macOS' bash 3.2.
set -euo pipefail

LIST_ONLY=0
BASE_ONLY=0
ALL_STAGES=0
PLATFORM=linux/amd64
SEVERITY=
JSON_DIR=
ROOT=

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
	case $1 in
	--list) LIST_ONLY=1 ;;
	--base-only) BASE_ONLY=1 ;;
	--all-stages) ALL_STAGES=1 ;;
	--platform) PLATFORM=${2:?}; shift ;;
	--platform=*) PLATFORM=${1#*=} ;;
	--severity-threshold) SEVERITY=${2:?}; shift ;;
	--severity-threshold=*) SEVERITY=${1#*=} ;;
	--json-dir) JSON_DIR=${2:?}; shift ;;
	--json-dir=*) JSON_DIR=${1#*=} ;;
	-h | --help) usage; exit 0 ;;
	-*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
	*) ROOT=$1 ;;
	esac
	shift
done

ROOT=$(cd "${ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)

# Print container build/compose files under ROOT, one per line, relative to ROOT.
discover() {
	(cd "$ROOT" && find . \
		\( -name .git -o -name vendor -o -name node_modules -o -name bin -o -name .ignore \
		-o -path ./test/results \) -prune -o \
		-type f \( \
		-name Dockerfile -o -name 'Dockerfile.*' -o -name '*.Dockerfile' -o -name '*.dockerfile' \
		-o -name Containerfile -o -name 'Containerfile.*' \
		-o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \
		-o -name 'compose*.yml' -o -name 'compose*.yaml' \
		\) -print | sed 's|^\./||' | sort)
}

is_compose() {
	case $(basename "$1") in
	docker-compose*.yml | docker-compose*.yaml | compose*.yml | compose*.yaml) return 0 ;;
	*) return 1 ;;
	esac
}

files=$(discover)
if [ -z "$files" ]; then
	echo "No Dockerfiles or compose files found under $ROOT"
	exit 0
fi

if [ "$LIST_ONLY" = 1 ]; then
	for f in $files; do
		if is_compose "$f"; then echo "compose     $f"; else echo "dockerfile  $f"; fi
	done
	exit 0
fi

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
if command -v snyk >/dev/null; then SNYK=(snyk); else SNYK=(npx --yes snyk); fi
[ -z "$JSON_DIR" ] || mkdir -p "$JSON_DIR"

slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'; }

failures=0
scanned=0

# snyk_scan <image> [dockerfile]
snyk_scan() {
	local image=$1 dockerfile=${2:-} args
	args=(container test "$image" --platform="$PLATFORM")
	[ -z "$dockerfile" ] || args+=(--file="$ROOT/$dockerfile")
	[ -z "$SEVERITY" ] || args+=(--severity-threshold="$SEVERITY")
	[ -z "$JSON_DIR" ] || args+=(--json-file-output="$JSON_DIR/$(slug "$image").json")
	echo
	echo "==> snyk ${args[*]}"
	scanned=$((scanned + 1))
	if ! "${SNYK[@]}" "${args[@]}"; then
		failures=$((failures + 1))
		echo "!! issues found or scan failed for $image" >&2
	fi
}

# Base images of a Dockerfile: FROM lines, skipping scratch and earlier stage names, with
# ${ARG}/$ARG references resolved from ARG defaults. Only the final stage unless ALL_STAGES=1.
base_images() {
	awk -v all="$ALL_STAGES" '
		toupper($1) == "ARG" { split($2, kv, "="); if (kv[2] != "") args[kv[1]] = kv[2]; next }
		toupper($1) == "FROM" {
			i = 2; while ($i ~ /^--/) i++
			img = $i
			for (a in args) { gsub("\\$\\{" a "\\}", args[a], img); gsub("\\$" a, args[a], img) }
			if (tolower($(i+1)) == "as") stages[tolower($(i+2))] = 1
			last = (img == "scratch" || (tolower(img) in stages)) ? "" : img
			if (all == 1 && last != "") print last
		}
		END { if (all != 1 && last != "") print last }' "$1" | sort -u
}

# Dockerfiles that ADD/COPY a file which doesn't exist yet expect a prior build step
# (e.g. coredns-plugin ADDs a prebuilt `coredns` binary). Run `make build` for those.
prebuild_if_needed() {
	local dockerfile=$1 dir missing
	dir=$(dirname "$ROOT/$dockerfile")
	missing=$(awk 'toupper($1) == "ADD" || toupper($1) == "COPY" {
			if ($0 ~ /--from=/) next
			for (i = 2; i < NF; i++) if ($i !~ /^--/) print $i
		}' "$ROOT/$dockerfile" | while read -r src; do
		# (no `case` here: bash 3.2 can't parse `case` inside $(...))
		if [[ $src == *'*'* || $src == http* ]]; then continue; fi
		[ -e "$dir/$src" ] || echo "$src"
	done)
	[ -n "$missing" ] || return 0
	if [ -f "$dir/Makefile" ] && grep -q '^build:' "$dir/Makefile"; then
		echo "==> $dockerfile needs prebuilt $(echo $missing): running make build"
		make -C "$dir" build GOOS="${PLATFORM%%/*}" GOARCH="${PLATFORM##*/}"
	else
		echo "!! $dockerfile references missing files: $(echo $missing)" >&2
	fi
}

for f in $files; do
	if is_compose "$f"; then
		echo
		echo "### compose file $f"
		if [ "$BASE_ONLY" = 0 ]; then
			docker compose -f "$ROOT/$f" build || { failures=$((failures + 1)); continue; }
		fi
		for image in $(docker compose -f "$ROOT/$f" config --images); do
			snyk_scan "$image"
		done
	else
		echo
		echo "### Dockerfile $f"
		if [ "$BASE_ONLY" = 1 ]; then
			images=$(base_images "$ROOT/$f")
			[ -n "$images" ] || echo "final stage is FROM scratch (or a local stage): no base image to scan"
			for image in $images; do
				snyk_scan "$image" "$f"
			done
		else
			prebuild_if_needed "$f"
			tag="snyk-scan/$(slug "$f"):local"
			if docker buildx build --platform "$PLATFORM" --load -t "$tag" -f "$ROOT/$f" "$(dirname "$ROOT/$f")"; then
				snyk_scan "$tag" "$f"
			else
				failures=$((failures + 1))
				echo "!! docker build failed for $f" >&2
			fi
		fi
	fi
done

echo
echo "Scanned $scanned image(s); $failures with issues or errors."
[ "$failures" -eq 0 ]

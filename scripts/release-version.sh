#!/usr/bin/env bash
# Derives the release version in CI (same rules as scripts/bundle.sh --version).
#
#   scripts/release-version.sh <ref_type> <ref_name> <sha> [input_version]
#   scripts/release-version.sh --self-test
#
# Prints key=value lines (append them to $GITHUB_OUTPUT):
#   versionArg     the version to pass to `bundle.sh --version` (empty = bundle.sh default 0.0.1)
#   bundleVersion  CFBundleShortVersionString / CFBundleVersion (suffix cut off)
#   fileVersion    version in the file name (a suffix such as -rc1 stays)
#   release        true only for ref_type "tag"; a manual run with an input version is never a release
#
# Single source of the version rules: scripts/bundle.sh --version calls this script too.
# Deviation from the Gradle build, accepted: `+build` metadata is rejected rather than cut off. As there, leading zeros
# of the numbers are normalized in the bundle version (`01.2` -> `1.2`; the file name keeps the text as given), the
# input is trimmed, and a number of more than 9 digits is an error.
# A non-empty input_version on a tag ref must equal the tag (it cannot silently be ignored).
#
# The version is the tag (or, for a non-tag run, the optional input_version); `v` optional, 1 to 3 dot-separated
# numbers, not all zero (0.9.0 is fine), an optional `-suffix`. Without a tag and without input: 0.0.1, file name
# `dev-<first 7 of sha>`. An invalid version exits 2.
set -euo pipefail

derive() {
  local ref_type="$1" ref_name="$2" sha="$3" input="${4:-}"
  local release=false arg=""
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  if [ "$ref_type" = "tag" ]; then
    release=true
    arg="$ref_name"
    if [ -n "$input" ] && [ "$input" != "$ref_name" ]; then
      echo "version input '$input' conflicts with the tag '$ref_name' (leave the input empty on a tag)" >&2
      return 2
    fi
  elif [ -n "$input" ]; then
    arg="$input"
  fi
  if [ -z "$arg" ]; then
    echo "versionArg="
    echo "bundleVersion=0.0.1"
    echo "fileVersion=dev-${sha:0:7}"
    echo "release=$release"
    return 0
  fi
  local raw="${arg#v}"
  local core="${raw%%-*}"
  if ! [[ "$core" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "version '$arg': expected 1 to 3 dot-separated numbers (got '$core')" >&2
    return 2
  fi
  local -a parts
  IFS=. read -r -a parts <<< "$core"
  local part norm=()
  for part in "${parts[@]}"; do
    if [ "${#part}" -gt 9 ]; then
      echo "version '$arg': the number '$part' is too long (at most 9 digits)" >&2
      return 2
    fi
    norm+=("$((10#$part))")
  done
  local nonzero=0
  for n in "${norm[@]}"; do
    [ "$n" -gt 0 ] && nonzero=1
  done
  if [ "$nonzero" -eq 0 ]; then
    echo "version '$arg': at least one number must be greater than 0" >&2
    return 2
  fi
  core="$(IFS=.; echo "${norm[*]}")"
  if ! [[ "$raw" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "version '$arg': unsupported characters" >&2
    return 2
  fi
  echo "versionArg=$arg"
  echo "bundleVersion=$core"
  echo "fileVersion=$raw"
  echo "release=$release"
}

self_test() {
  local fails=0
  # ref_type | ref_name | input | expected output (joined by ;) or "ERR"
  check() {
    local expect="$4" out
    if out="$(derive "$1" "$2" 0123456789abcdef "$3" 2>/dev/null)"; then
      out="$(echo "$out" | paste -sd';' -)"
    else
      out=ERR
    fi
    if [ "$out" != "$expect" ]; then
      echo "FAIL: ($1, $2, $3) expected '$expect', got '$out'" >&2
      fails=$((fails + 1))
    fi
  }
  check tag v1.2.3 "" "versionArg=v1.2.3;bundleVersion=1.2.3;fileVersion=1.2.3;release=true"
  check tag v1.2.3-rc1 "" "versionArg=v1.2.3-rc1;bundleVersion=1.2.3;fileVersion=1.2.3-rc1;release=true"
  check tag 1.0 "" "versionArg=1.0;bundleVersion=1.0;fileVersion=1.0;release=true"
  check tag v2 "" "versionArg=v2;bundleVersion=2;fileVersion=2;release=true"
  check tag v1.0.0-beta.2 "" "versionArg=v1.0.0-beta.2;bundleVersion=1.0.0;fileVersion=1.0.0-beta.2;release=true"
  check tag v01.2.3 "" "versionArg=v01.2.3;bundleVersion=1.2.3;fileVersion=01.2.3;release=true"
  check tag v0.1.0 "" "versionArg=v0.1.0;bundleVersion=0.1.0;fileVersion=0.1.0;release=true"
  check tag v00.1.0 "" "versionArg=v00.1.0;bundleVersion=0.1.0;fileVersion=00.1.0;release=true"
  check tag v99999999999999999999.1 "" ERR
  check tag v1.2.3 v1.2.3 "versionArg=v1.2.3;bundleVersion=1.2.3;fileVersion=1.2.3;release=true"
  check tag v1.2.3 v1.2.4 ERR
  check workflow_dispatch main "  v1.2.3  " "versionArg=v1.2.3;bundleVersion=1.2.3;fileVersion=1.2.3;release=false"
  check workflow_dispatch main "   " "versionArg=;bundleVersion=0.0.1;fileVersion=dev-0123456;release=false"
  check workflow_dispatch main v1.2.3+b1 ERR
  check tag v0.9.0-rc1 "" "versionArg=v0.9.0-rc1;bundleVersion=0.9.0;fileVersion=0.9.0-rc1;release=true"
  check tag v0.9.0 "" "versionArg=v0.9.0;bundleVersion=0.9.0;fileVersion=0.9.0;release=true"
  check tag v0.0.0 "" ERR
  check tag v0 "" ERR
  check tag v1.2.3.4 "" ERR
  check tag vfoo "" ERR
  check tag v1.x "" ERR
  check tag v "" ERR
  check branch main "" "versionArg=;bundleVersion=0.0.1;fileVersion=dev-0123456;release=false"
  check workflow_dispatch main "" "versionArg=;bundleVersion=0.0.1;fileVersion=dev-0123456;release=false"
  check workflow_dispatch main v1.2.3-rc1 "versionArg=v1.2.3-rc1;bundleVersion=1.2.3;fileVersion=1.2.3-rc1;release=false"
  check pull_request 7/merge "" "versionArg=;bundleVersion=0.0.1;fileVersion=dev-0123456;release=false"
  check workflow_dispatch main v0.5.0 "versionArg=v0.5.0;bundleVersion=0.5.0;fileVersion=0.5.0;release=false"
  # a branch named like a tag must not become a release or a version
  check branch v1.2.3 "" "versionArg=;bundleVersion=0.0.1;fileVersion=dev-0123456;release=false"
  if [ "$fails" -ne 0 ]; then
    echo "release-version self-test: $fails failure(s)" >&2
    return 1
  fi
  echo "release-version self-test passed"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi
if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "usage: $0 <ref_type> <ref_name> <sha> [input_version] | --self-test" >&2
  exit 2
fi
derive "$@"

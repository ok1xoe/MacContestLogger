#!/usr/bin/env bash
# Sets the modification time of every tracked file to the time of the last commit that changed it.
# Used in CI before restoring the build cache (see .github/workflows/ci.yml).
set -euo pipefail
git log --format='@%ct' --name-only --no-renames HEAD | perl -ne '
  chomp;
  if (/^@(\d+)$/) { $t = $1; next }
  next if $_ eq "" || $seen{$_}++;
  utime($t, $t, $_) if -e $_;
'

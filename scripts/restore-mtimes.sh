#!/usr/bin/env bash
# Sets the modification time of every tracked file to the time of the last commit that changed it.
# Used in CI before restoring the build cache (see .github/workflows/ci.yml).
# Merge commits list their changes against the first parent: a file whose content was settled in a merge
# (a resolved conflict, or every change of a pull request's merge ref) gets the merge's time. Without that
# `git log` lists no files for merges, the file kept an older commit's time, the restored build looked newer
# and SwiftPM ran stale code against the new sources.
set -euo pipefail
git log --format='@%ct' --name-only --no-renames --diff-merges=first-parent HEAD | perl -ne '
  chomp;
  if (/^@(\d+)$/) { $t = $1; next }
  next if $_ eq "" || $seen{$_}++;
  utime($t, $t, $_) if -e $_;
'

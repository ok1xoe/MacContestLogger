# mcl-scorecheck: verifying scores against claimed results

`mcl-scorecheck` is a command-line tool that loads Cabrillo logs, evaluates the QSOs with the
contest engine of MacContestLogger, and writes a **reference** (a TSV file) with the computed
score next to the value of **`CLAIMED-SCORE`** from the log header. It is a regression and
verification tool for real-world logs: the reference of one build can be compared with the
reference of another.

## What it does

1. For each log it reads `CONTEST:` (the contest), `CALLSIGN:` (own station, needed for points
   by continent) and `CLAIMED-SCORE:` (the claimed score) from the header.
2. It maps the contest to a definition (`cabrillo.contestName` in the YAML), parses the `QSO:`
   lines, and evaluates points and multipliers.
3. For every log it writes one TSV line with the status, QSO count, points, multipliers,
   computed score and claimed score.

The tool deliberately does not classify logs (OK / close / failed) or draw histograms. It
only produces the data; compare the computed and claimed columns with the tool of your choice
(a spreadsheet, `awk`, ...).

## Prerequisites

- Contest definitions: a directory with `contests/*.yaml` and `multipliers/*.yaml`
  (the repository contains `contest-data/` as a baseline).
- DXCC data in `~/dxcc-json/`:
  - **`cty.dat`** (default, preferred: precise, handles special prefixes and callsign exceptions),
  - alternatively **`dxcc.json`** (less precise).
- The location of the DXCC file can be changed with `--dxcc-file`.

## Building and running

The tool is a SwiftPM executable (`mcl-scorecheck`):

```bash
swift build -c release

# a single log
swift run -c release mcl-scorecheck /path/to/log.cbr --contest-data contest-data

# a directory (recursive; only .log / .cbr / .cabrillo files)
swift run -c release mcl-scorecheck /path/to/directory --contest-data contest-data

# a large batch: 8 threads, output to a file
swift run -c release mcl-scorecheck /path/to/logs --contest-data contest-data --jobs 8 --out reference.tsv
```

## Options

| Option | Meaning | Default |
|---|---|---|
| `<file\|directory>` | the input: one log (any extension), or a directory processed recursively | required |
| `--contest-data <dir>` | the directory with `contests/` and `multipliers/` | required |
| `--dxcc cty\|json` | the DXCC source: `cty.dat` or `dxcc.json` | `cty` |
| `--dxcc-file <path>` | path to `cty.dat` or `dxcc.json` | `~/dxcc-json/cty.dat` or `~/dxcc-json/dxcc.json` |
| `--jobs N` | number of threads; the order of the output is always the same | `1` |
| `--set <name>` | the value of the `set` header line | the name of the input |
| `--out <file>` | write to a file instead of standard output | standard output |
| `-h`, `--help` | print the usage | |

On completion the tool prints a one-line summary to standard error, for example
`1234 logů (ERR=3 OK=1229 UNREADABLE=2) za 4.1 s` (log counts by status and the elapsed time).

## Output: the TSV reference

The output starts with header lines `# key: value`, followed by one data line per log in
the order of the file path:

```
# format: scorecheck-reference 1
# set: logs-2025
# implementation: mcl-scorecheck (swift)
# contest-data-sha256: ...
# dxcc-source: cty
# cty.dat-sha256: ...
# logs: 1234
# columns: key file status contest qsoCount qsoPoints multTotal multByGroup computed claimed unresolvedCount skipReason errorClass error
```

The header records exactly what the result was computed from (hashes of the contest data and
of the DXCC file, number of logs), so two references are comparable only when these lines match.

Data lines are tab-separated, with the columns listed in the `columns` line:

| Column | Meaning |
|---|---|
| `key` | the first 16 hex characters of the SHA-256 of the log content (identifies the log regardless of its name) |
| `file` | the file name |
| `status` | `OK` (evaluated), `ERR` (the log could not be evaluated, e.g. an unknown contest), `EXC` (an exception during evaluation), `UNREADABLE` (the file could not be read) |
| `contest` | the contest from the header |
| `qsoCount`, `qsoPoints` | the number of QSOs and the points for QSOs |
| `multTotal` | the total number of multipliers |
| `multByGroup` | multipliers by group, `group=count` separated by commas |
| `computed` | the computed score |
| `claimed` | `CLAIMED-SCORE` from the header (`\N` when missing) |
| `unresolvedCount` | the number of callsigns that could not be resolved to a DXCC entity |
| `skipReason` | why the log should be skipped in statistics (`checklog`, no `CLAIMED-SCORE`), otherwise `\N` |
| `errorClass`, `error` | the exception class and the error message (`\N` when none) |

Text values are escaped: a backslash becomes `\\`, characters outside printable ASCII become
`\uXXXX`, and a missing value is `\N`. Free text from a log longer than 80 characters is
replaced by `#sha256:` and a hash, so the reference does not carry text from the logs.

## Notes

- Logs without `CLAIMED-SCORE` and checklogs are still evaluated; the `skipReason` column tells
  you to leave them out of any comparison.
- A residual deviation of about 1 % from the claimed score is expected (border continents and
  zones, maritime mobile, small errors in other people's logs). In CQ WW the own DXCC entity
  counts as a multiplier (0 points).

# Feature B — CLI command

## Purpose

A command-line tool, `featureb`, that ingests a JSON file of records and produces a normalized output stream. Used in the migration fixture to exercise the translator's handling of real command specs that include argument parsing, error paths, and structured Given/When/Then test cases.

## Behavior

`featureb` accepts the following arguments:

- `--input <path>` (required) — Path to the input JSON file. Must exist and be readable.
- `--format <format>` (optional, default `ndjson`) — Output format. One of `ndjson`, `csv`.
- `--strict` (optional flag) — Fail on the first malformed record instead of skipping.

When invoked, the tool reads the input file, validates each record against a fixed schema, normalizes the records (lowercases string fields, trims whitespace), and writes them to stdout in the requested format. Malformed records are skipped with a warning to stderr unless `--strict` is set.

Exit codes:

- `0` — All records processed successfully (or skipped under non-strict mode)
- `1` — Input file missing or unreadable
- `2` — Invalid argument combination
- `3` — A malformed record was encountered while `--strict` was set

## Test cases

### Argument parsing

- **Given** `featureb` is invoked with no `--input` argument
  **When** the tool runs
  **Then** the tool exits with code `2` and prints "missing required argument: --input" to stderr

- **Given** `featureb` is invoked with `--input nonexistent.json`
  **When** the tool runs
  **Then** the tool exits with code `1` and prints "input file not found: nonexistent.json" to stderr

- **Given** `featureb` is invoked with `--format yaml`
  **When** the tool runs
  **Then** the tool exits with code `2` and prints "invalid format: yaml" to stderr

### Normalization

- **Given** an input file containing one record with leading/trailing whitespace and mixed-case strings
  **When** the tool runs in default mode
  **Then** the output stream contains the record with whitespace trimmed and string fields lowercased

- **Given** an input file with three valid records and one malformed record
  **When** the tool runs without `--strict`
  **Then** the output contains three normalized records and stderr contains one warning

- **Given** an input file with three valid records and one malformed record
  **When** the tool runs with `--strict`
  **Then** the tool exits with code `3` after the malformed record is encountered

### Output format

- **Given** valid input and `--format csv`
  **When** the tool runs
  **Then** the output is a CSV stream with a header row matching the record schema

## Notes

- Input schema is documented in `docs/schema.md` (out of scope for this fixture).
- The tool reads the entire input file before producing output; streaming mode is not supported in this version.

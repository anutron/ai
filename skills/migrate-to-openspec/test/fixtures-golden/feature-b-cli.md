# Feature B — CLI command

## Purpose

A command-line tool, `featureb`, that ingests a JSON file of records and produces a normalized output stream. Used in the migration fixture to exercise the translator's handling of real command specs that include argument parsing, error paths, and structured Given/When/Then test cases.

## Requirements

### Requirement: Argument parsing

`featureb` SHALL accept the following arguments: `--input <path>` (required), `--format <format>` (optional, default `ndjson`, one of `ndjson` or `csv`), and `--strict` (optional flag). When required arguments are missing or values are invalid, the tool MUST exit with code `2` and write a diagnostic message to stderr.

#### Scenario: missing --input

- **WHEN** `featureb` is invoked with no `--input` argument
- **THEN** the tool exits with code `2` and prints "missing required argument: --input" to stderr

#### Scenario: input file not found

- **WHEN** `featureb` is invoked with `--input nonexistent.json`
- **THEN** the tool exits with code `1` and prints "input file not found: nonexistent.json" to stderr

#### Scenario: invalid format value

- **WHEN** `featureb` is invoked with `--format yaml`
- **THEN** the tool exits with code `2` and prints "invalid format: yaml" to stderr

### Requirement: Record normalization

When invoked with valid arguments, `featureb` SHALL read the input file, validate each record against a fixed schema, normalize the records by lowercasing string fields and trimming whitespace, and write them to stdout in the requested format. Malformed records MUST be skipped with a warning to stderr unless `--strict` is set, in which case the tool MUST exit with code `3` upon encountering the first malformed record.

#### Scenario: whitespace and case normalization

- **WHEN** an input file contains one record with leading/trailing whitespace and mixed-case strings and the tool runs in default mode
- **THEN** the output stream contains the record with whitespace trimmed and string fields lowercased

#### Scenario: malformed record skipped without --strict

- **WHEN** an input file with three valid records and one malformed record is processed without `--strict`
- **THEN** the output contains three normalized records and stderr contains one warning

#### Scenario: malformed record fails under --strict

- **WHEN** an input file with three valid records and one malformed record is processed with `--strict`
- **THEN** the tool exits with code `3` after the malformed record is encountered

### Requirement: Output format selection

The tool SHALL emit records to stdout in the format specified by `--format`. Valid formats are `ndjson` (default) and `csv`. CSV output MUST include a header row matching the record schema.

#### Scenario: CSV output includes header row

- **WHEN** the tool runs with valid input and `--format csv`
- **THEN** the output is a CSV stream with a header row matching the record schema

## Notes

- Input schema is documented in `docs/schema.md` (out of scope for this fixture).
- The tool reads the entire input file before producing output; streaming mode is not supported in this version.
- Exit codes: `0` (success), `1` (input file missing or unreadable), `2` (invalid argument combination), `3` (malformed record encountered while `--strict` is set).

# Provenance

This repository is a community fork of **Antares**, a self-hosted AI agent
(Go backend, React dashboard, terminal UI, one binary).

It exists because the original repository was deleted, and it is maintained to
keep the project buildable and installable.

## Upstream

| | |
|---|---|
| Original project | Antares — a self-hosted AI agent |
| Original repository | `github.com/enowdev/antares` |
| Original author | Enow Dev. (`enowdev`), enowxlabs.com |
| First commit | `7674617` — *Antares: Go agent core, React dashboard, RAG, skills, cron, gateways* (2026-07-26) |
| Status | Repository **and owner account deleted** (both return HTTP 404 as of 2026-10-18) |

Deleting the repository also deleted its fork list, so no canonical inventory of
the 25 forks survives. The forks below were reconstructed by probing the GitHub
API, commit author identities, and the fork-lineage HTML that GitHub still
renders on surviving forks (`forked from enowdev/antares`).

### Surviving forks found

| Repository | Type | Head commit | Notes |
|---|---|---|---|
| `elliottophellia/antares` | true fork | `4dd05ab` (2026-09-19) | **Newest** surviving tree; 451 commits. Maintained by a project contributor. |
| `hshinosa/antares` | true fork | `af18562` (2026-09-15) | 417 commits, near-identical to the above |
| `nvdorman/antares` | true fork | `52d2fbf` (2026-07-31) | 213 commits, early snapshot |
| `Aphelios01-sdk/antares` | true fork | `9bd81cb` (2026-08-01) | 229 commits, early snapshot |
| `DevKuroX/antares` | re-upload | `9e82730` (2026-09-06) | 415 commits; not a GitHub fork, but carries full history plus 7 unique ChatUI docs |

Other repositories named `antares` that were checked and rejected as unrelated:
`antares-sql/antares` (SQL client), `microsoft/antares` (kernel generation),
`arescentral/antares` (space combat game), `CantorAI/Antares`,
`cristian/antares`-style scaffolding repos, and several unrelated projects.

## How this tree was assembled

No single surviving fork was both the newest *and* the most complete:

- `DevKuroX/antares` had full history and unique documentation, but stale code.
- `elliottophellia/antares` had the newest code, but its tree lacked the
  ChatUI documents.

So this repository was built by merging the newer branch onto the older one,
which preserves **both histories** rather than picking a winner.

| | |
|---|---|
| Base | `DevKuroX/antares` @ `9e82730b8c0454e89ad6858419eded4a7b8a3bac` |
| Merged in | `elliottophellia/antares` @ `4dd05aba6944a36d47cf570885fdadfd2e8888d7` |
| Merge base | `fb875906fcf017f80d9b9187b6cc65a1c7a121c0` |
| Divergence | 10 commits only in the base, 46 only in the merged branch |
| Merge commit | `2d95bdf` |
| Result | 462 commits, full upstream history retained |

### Conflict resolutions

| Path | Resolution | Why |
|---|---|---|
| `cmd/antares/main.go`, `internal/agent/{compact,skills}.go`, `internal/server/handlers_config.go`, `internal/tools/{background_process,browser,imagegen}.go`, `internal/tui/pickers.go` | Took the merged (elliottophellia) side | Import blocks only; the newer side's added packages (`creator`, `media`, `config`, `store`, `skills`) are real features |
| `cmd/antares/cli.go` | Accepted deletion | Upstream removed the line-based REPL deliberately in `09b213c`: *"the old line-based REPL (chat / repl / cli, plus cli.go) is gone"*. Restoring it would resurrect dead code |
| `internal/config/load.go` | Took upstream whole, repointed the URL | The naive merge produced a structurally invalid function |
| `web/tsconfig.tsbuildinfo` | Accepted deletion, added to `.gitignore` | Generated build artifact |
| `docs/superpowers/**` | Restored from the base | 7 documents unique to `DevKuroX/antares` |

## Divergences from upstream

This fork is not a byte-for-byte copy of any single snapshot. Intentional
changes, each in its own commit:

1. **Single module path.** The tree had been split between `github.com/enowdev/antares`
   and `github.com/DevKuroX/antares` imports. Both were unified to
   `github.com/pandamoon21/antares` across 229 files. Without this, version
   stamping silently broke: the Makefile and `scripts/release-build.sh` injected
   `-X github.com/enowdev/antares/internal/version.Version=…`, a symbol that
   stops existing once `go.mod` is renamed, so binaries reported `0.1.0-dev`
   regardless of the tag.
2. **Restored `internal/server/dist/.gitkeep`.** Required by
   `//go:embed all:dist`, gitignored upstream, so a bare checkout could not build.
3. **Config read/write race fixed.** `config.Reload` now serialises its
   `os.ReadFile` against the save mutex. On Windows, renaming a temp file over a
   concurrently open handle fails with `ERROR_SHARING_VIOLATION`, which surfaced
   to users as a spurious HTTP 500 during a model switch.
   `TestModelSetConcurrentWithConfigReads` went from 4/12 to 20/20 passing.
4. **Installers repointed and fixed.** See the commit message for
   `fix(install)`; the scripts pointed at the deleted repository, refused
   `latest` without the `gh` CLI, and were unusable from a Windows checkout
   because of CRLF and a non-ASCII byte that broke PowerShell 5.1 parsing.

## Build verification

Checked on Windows 11 (Go 1.26.3, Bun 1.4.2):

- `go build ./...` — clean
- `go vet ./...` — clean
- `go test ./...` — clean except **19 Windows-only failures that fail
  identically on the unmodified upstream tree** (POSIX permission bits,
  `/tmp`-style path handling). No regressions were introduced.
- Single-binary build with the dashboard embedded — works, and reports the
  injected version, e.g. `Antares v0.3.0 (commit 2d95bdf, built …)`.

## Licensing and attribution

Antares is licensed under the **Apache License 2.0**; see [LICENSE](LICENSE)
and [NOTICE](NOTICE). That license is why this fork can exist: it permits use,
modification and redistribution provided the license and attribution notices are
kept and changed files are marked as changed — which is why every divergence
above is isolated in its own explicit commit.

Original work is copyright Enow Dev. and the Antares contributors. This fork
claims no authorship of that work and adds no restrictions on top of Apache-2.0.

If you are the original author: open an issue if you want this fork promoted,
redirected, renamed, or removed, and it will be handled promptly.

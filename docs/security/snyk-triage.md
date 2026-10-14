# Snyk triage

How the findings from `snyk test` (open source / SCA) and `snyk code test` (SAST) were handled.
To re-run the scans, see [Re-running](#re-running).

## `snyk test`: dependency vulnerabilities (42 issues, 2026-10-13)

| Finding | Cause | Fix |
|---|---|---|
| 40 × Go standard library (`std/crypto/tls`, `std/net/http`, `std/os`, `std/net/url`, …) | `go.mod` pinned `toolchain go1.23.4` | `toolchain go1.26.9` in both modules; Dockerfile builder `golang:1.26.9` |
| `golang.org/x/net/http2` infinite loop (fixed in 0.53.0) | x/net v0.34.0 via client-go | x/net v0.61.0 |
| `golang.org/x/net/idna` improper authentication, critical (fixed in 0.54.0) | same | x/net v0.61.0 |

`govulncheck` also flagged required (but unreachable) modules, which were upgraded too:
- root module: `klauspost/compress`, `golang.org/x/oauth2`
- coredns-plugin: CoreDNS v1.13.2 → v1.14.7, plus gRPC, etcd client and otel

**Accepted (no fix available):** `SNYK-GOLANG-GITHUBCOMCOREDNSCOREDNSPLUGINPKGPROXY-12558120`
(medium, authentication bypass by spoofing in CoreDNS `plugin/pkg/proxy`, reached through the `forward`
plugin). No CoreDNS release fixes it yet; v1.14.7 is the latest. It is ignored in
[`coredns-plugin/.snyk`](../../coredns-plugin/.snyk) until 2027-01-13, so it resurfaces for review.
Dependabot will propose the CoreDNS upgrade once a fix ships.

CI runs `govulncheck` on every PR and weekly, so new advisories surface without Snyk credentials.

## `snyk code test`: static analysis (8 issues, all in `vendor/`)

Every finding was in third-party code under `vendor/`. Patching vendored files is wrong, since
`go mod vendor` overwrites them, and these are not exploitable in how the operator uses them. `vendor/`
is now excluded from Snyk Code via [`.snyk`](../../.snyk). Vulnerabilities in those modules are still
covered by `snyk test` and govulncheck.

| Severity | Location | Finding | Assessment |
|---|---|---|---|
| High | `sigs.k8s.io/controller-runtime/pkg/log/log.go:64` | Error message with stack trace | Prints a stack to stderr once if `log.SetLogger` was never called within 30s of start-up (main.go calls it). This is local process output, not a response to a remote caller. False positive. |
| Medium | `k8s.io/client-go/util/cert/server_inspection.go:33,67` | Permissive TLS (`InsecureSkipVerify`) | Helper that *fetches* a server's certificate chain for inspection. Skipping verification is its purpose, and the operator never calls it. |
| Medium | `sigs.k8s.io/controller-runtime/pkg/webhook/server.go:275` | Permissive TLS | `StartedChecker` dials the webhook server's own local port for a readiness check. main.go configures a webhook server but registers no webhooks and never uses `StartedChecker`. |
| Low | `sigs.k8s.io/controller-runtime/pkg/internal/testing/process/process.go:218` | Permissive TLS | envtest health probe against a locally started test kube-apiserver. Only used by tests. |
| Low | `github.com/google/uuid/hash.go:50,58` | MD5 / SHA1 "password hash" | RFC 4122 version 3/5 name-based UUIDs, which the RFC defines with MD5/SHA1. Not password hashing. |
| Low | `k8s.io/klog/v2/klog_file.go:48` | Hard-coded credential `userName` | The OS user name used in log file names (`"unknownuser"` fallback). Not a credential. |

## Container images

`hack/snyk-container-scan.sh` finds every Dockerfile/Containerfile and compose file in the repo,
builds the Dockerfiles locally, and runs `snyk container test` on the result (or on the base
images, with `--base-only`).

## Re-running

```bash
npx snyk auth                         # once
npx snyk test --all-projects          # both Go modules
npx snyk code test                    # first-party code only (see .snyk)
hack/snyk-container-scan.sh           # all Dockerfiles / compose files
go run golang.org/x/vuln/cmd/govulncheck@latest ./...   # no account needed
```

# Go and the MCP Adapter

**Read when:** editing Go MCP tools, protocol handling, or backend transport.

Write direct Go: small concrete structs, explicit control flow, early error returns, and normal loops. Prefer narrow consumer-owned interfaces when substitution is necessary. Avoid speculative repositories, generic dependency-injection frameworks, or functional collection libraries. Format with `gofmt`. [effective-go] [go-review]

Accept `context.Context` explicitly at cancellable operation boundaries and propagate it into backend HTTP requests. Reuse configured HTTP clients, set appropriate timeout/size limits, close response bodies, and preserve useful error context with wrapping. Test error meaning with `errors.Is`/`errors.As`, not string matching. A goroutine must have an owner and a termination path; bound concurrency and retries. Never blindly retry non-idempotent writes. [go-review]

The MCP adapter translates tool inputs/outputs, protocol errors, and transport concerns. It MUST call the Haskell API for canonical validation, persistence, and authoritative calculations. It MUST NOT connect directly to PostgreSQL, become another FIT decoder, or reproduce training algorithms. AI/natural-language input may produce an untrusted draft; it does not become canonical merely because an AI generated it.

Prefer the official Go SDK, pinned after checking the selected protocol/transport support. Local stdio and remote HTTP are different deployment decisions. **For stdio, only protocol output belongs on stdout; logs go to stderr.** Tool names, descriptions, schemas, units, and write effects must be specific. Tool annotations describe behavior but are not authorization controls. [mcp-sdk] [mcp-server]

Resolve the acting user from authenticated context, not a model-supplied `userId`. Treat tool text and returned content as untrusted data rather than executable instructions. Keep backend credentials separate from the inbound MCP authentication boundary; do not blindly forward an arbitrary client token downstream. Remote exposure requires an explicit design against the current MCP authorization/security requirements, not the abandoned token table. [mcp-security]

Suggested checks: `gofmt`, `go vet`, `go test`, race-enabled tests on supported runners, and small protocol tests for schema errors, cancellation, authorization failure, and backend failure. Include a test that diagnostic logging does not corrupt stdio protocol output.

[effective-go]: references.md#effective-go
[go-review]: references.md#go-review
[mcp-sdk]: references.md#mcp-sdk
[mcp-security]: references.md#mcp-security
[mcp-server]: references.md#mcp-server

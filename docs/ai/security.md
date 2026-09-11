# Authentication and Sensitive Data

**Read when:** changing authentication, authorization, health/route-data exposure, logging, or external-provider access.

The accepted [API authentication contract](../api-contract.md#authentication-and-ownership) uses username/password login and one opaque database-session model: a Secure/HttpOnly cookie plus CSRF/Origin checks for browsers, and a Keychain-held Bearer credential for native clients. Authentication handlers and persistence are not implemented yet. Do not restore the superseded token design or infer MCP authorization from native sessions.

Implement password verification through maintained Argon2id facilities, never bespoke cryptography, plaintext passwords, or a fast unsalted digest. SHA-256 is used only to index high-entropy random session secrets. Enforce owner-scoped access from the authenticated principal, expiry/revocation, enumeration resistance and rate limits. Reject ambiguous cookie/Bearer credentials. [owasp-auth]

Do not log credentials, complete FIT uploads, precise routes, or bulk health records by default. Use synthetic/minimized fixtures. Authorization and data ownership must be enforced server-side even when the interface is used only by a personal client. Sending records to an AI service must follow the user's chosen provider/data-sharing settings rather than occur as a hidden side effect.

[owasp-auth]: references.md#owasp-auth

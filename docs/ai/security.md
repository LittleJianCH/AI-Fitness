# Authentication and Sensitive Data

**Read when:** changing authentication, authorization, health/route-data exposure, logging, or external-provider access.

Authentication remains an active design decision. Implement username/password login using maintained password-verification facilities, never bespoke cryptography, plaintext passwords, or a fast unsalted digest. Handle user enumeration, rate limiting, session lifecycle, and authorization deliberately when that feature is implemented. Cookie-based designs require their own cookie/CSRF controls; choosing them is not implied by this guide. [owasp-auth]

Do not log credentials, complete FIT uploads, precise routes, or bulk health records by default. Use synthetic/minimized fixtures. Authorization and data ownership must be enforced server-side even when the interface is used only by a personal client. Sending records to an AI service must follow the user's chosen provider/data-sharing settings rather than occur as a hidden side effect.

[owasp-auth]: references.md#owasp-auth

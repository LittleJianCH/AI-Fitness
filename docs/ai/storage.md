# PostgreSQL and Local File Storage

**Read when:** changing queries, migrations, transactions, database constraints, or filesystem persistence.

The backend owns database access. Use parameterized queries and explicit transaction boundaries. Enforce stored invariants with primary/foreign keys, uniqueness, `NOT NULL`, and appropriate checks; Haskell types do not protect writes from every source. Test migrations against the actual PostgreSQL behavior rather than treating an in-memory mock as equivalent. Preserve one authoritative migration/schema workflow compatible with the selected IHP version. [postgres]

Do not hold database transactions open during lengthy network/AI/SDK work without a demonstrated consistency need. File writes and PostgreSQL commits do not form one automatic atomic transaction: design temporary files, commit ordering, cleanup, and recovery explicitly. Restrict storage paths to the designated data root rather than trusting filenames supplied by clients.

[postgres]: references.md#postgres

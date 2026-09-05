Here's a phase-by-phase breakdown ordered by how often each thing actually shows up in real backend work and interviews. Phases 1-3 are the 20% that covers ~80% of daily use and interview questions; 4-5 are what gets you from "can use Postgres" to "can be trusted with it in production."

**Phase 1 — Core querying (the daily bread)**
- SELECT, WHERE, ORDER BY, LIMIT/OFFSET
- JOINs: INNER, LEFT, RIGHT (know these cold — most asked in interviews)
- GROUP BY, HAVING, aggregate functions (COUNT, SUM, AVG, MIN, MAX)
- Basic data types: INT, VARCHAR/TEXT, BOOLEAN, TIMESTAMP, NUMERIC
- INSERT, UPDATE, DELETE, basic constraints (NOT NULL, UNIQUE, DEFAULT)

**Phase 2 — Schema design & relationships**
- Primary keys, foreign keys, CASCADE behavior
- Normalization basics (1NF-3NF) — just enough to design sane schemas, not academic depth
- One-to-many, many-to-many (junction tables)
- SERIAL/IDENTITY columns, UUID as PK (common in real backends)
- ALTER TABLE for migrations

**Phase 3 — Indexes & performance basics**
- What an index is, when Postgres uses one, B-tree index
- EXPLAIN / EXPLAIN ANALYZE — reading query plans (huge interview + real-world skill)
- Composite indexes, when NOT to index
- N+1 query problem awareness (ties directly to your Node.js backend work)

**Phase 4 — Transactions & data integrity**
- BEGIN/COMMIT/ROLLBACK, ACID basics
- Isolation levels (at least know READ COMMITTED vs SERIALIZABLE conceptually)
- Row locking basics (SELECT FOR UPDATE)
- Upserts (ON CONFLICT DO UPDATE) — very common in real APIs

**Phase 5 — Postgres-specific power features**
- JSONB — storing/querying JSON (extremely common in Node backends)
- Window functions (ROW_NUMBER, RANK, PARTITION BY) — shows up a lot in interviews once you're past basics
- CTEs (WITH clauses), including recursive CTEs
- Full-text search basics (if you ever need search without Elasticsearch)

**Phase 6 — DBA-adjacent **
- Connection pooling concepts (pgbouncer, why Node apps need it)
- Backup/restore (pg_dump/pg_restore)
- VACUUM/ANALYZE and why bloat happens
- Partitioning (only if you want to go deep — table partitioning for large datasets)
- Replication basics (streaming replication, read replicas — conceptual is enough)


#!/usr/bin/env bash
set -euo pipefail

unset PGHOSTADDR PGSERVICE PGSERVICEFILE PGOPTIONS

# Always use a new private cluster; never consume a developer's DATABASE_URL.
test_root=$(mktemp -d /tmp/ai-fitness-storage.XXXXXX)
cleanup() {
    pg_ctl -D "$test_root/data" -m immediate -w stop >/dev/null 2>&1 || true
    rm -rf -- "$test_root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$test_root/socket"
initdb -D "$test_root/data" --username=fitness_storage_test --no-locale --encoding=UTF8 --auth-local=trust --auth-host=reject >"$test_root/init.log"
start_database() {
    pg_ctl -D "$test_root/data" -l "$test_root/postgres.log" -o "-k $test_root/socket -c listen_addresses=''" -w start >/dev/null
}
start_database
createdb -h "$test_root/socket" -p 5432 -U fitness_storage_test fitness_storage_test
export DATABASE_URL="host=$test_root/socket port=5432 dbname=fitness_storage_test user=fitness_storage_test"
export AI_FITNESS_TEST_DATABASE_URL="$DATABASE_URL"
export IHP_MIGRATION_DIR=Application/Migration/
unset MINIMUM_REVISION
migrate
migrate
test "$(psql "$DATABASE_URL" -Atqc 'SELECT count(*) FROM schema_migrations')" = 1

# A failed IHP migration must roll back its DDL and leave its revision unapplied.
mkdir "$test_root/migrations"
cat >"$test_root/migrations/1789171201-failing.sql" <<'SQL'
CREATE TABLE must_rollback (id INTEGER);
SELECT 1 / 0;
SQL
if IHP_MIGRATION_DIR="$test_root/migrations/" migrate >"$test_root/migration-error.log" 2>&1; then
    echo "Expected the invalid migration to fail" >&2
    exit 1
fi
test "$(psql "$DATABASE_URL" -Atqc "SELECT to_regclass('must_rollback') IS NULL")" = t
test "$(psql "$DATABASE_URL" -Atqc 'SELECT count(*) FROM schema_migrations')" = 1
if [[ "${1:-storage}" == http ]]; then
    ./build/http-tests
    exit 0
fi
./build/storage-tests
pg_ctl -D "$test_root/data" -m fast -w stop >/dev/null
start_database
./build/storage-tests verify-restart

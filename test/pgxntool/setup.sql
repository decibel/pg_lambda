\i test/pgxntool/psql.sql
BEGIN;
-- I suspect it's a bad idea to have deps on pgTap...
\i test/deps.sql

\i test/pgxntool/tap_setup.sql


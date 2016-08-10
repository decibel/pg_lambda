\set ECHO none

\i test/pgxntool/setup.sql

SELECT plan(
  1
);

SELECT is(
  lambda(
    $l$( i1 int, i2 int ) RETURNS int LANGUAGE sql AS 'SELECT i1 + i2'$l$
    , 1::int
    , 2
  )
  , 3
  , 'Test simple addition function'
);


\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2

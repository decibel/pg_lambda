CREATE OR REPLACE FUNCTION lambda(
  code text
  , VARIADIC inputs anyarray
) RETURNS anyelement LANGUAGE plpgsql AS $body$
DECLARE
  c_prefix CONSTANT text := 'lambda_function_';
  c_pattern CONSTANT text := '^' || c_prefix || '([0-9]+)$';
  fname text;
  foid regprocedure;
  fargs regtype[];
  call_args text[];

  i int;
  sql text;
  out text;
BEGIN
  RAISE DEBUG 'c_prefix = %, c_pattern = %', c_prefix, c_pattern;

  -- Get highest defined number. Need to do this in case stuff is nested
  SELECT INTO i
      coalesce(
        max( substring(proname from c_pattern)::int ) + 1
        ,0
      )
    FROM pg_proc
    WHERE pronamespace=pg_my_temp_schema()
      AND proname ~ c_pattern
  ;
  fname := 'pg_temp.' || quote_ident( c_prefix || i );

  sql := format(
    'CREATE FUNCTION %s%s;'
    , fname
    , code
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;

  -- This will return an error if the function is overloaded, which is what we want
  foid := fname::regproc::oid;
  SELECT INTO fargs
      proargtypes::regtype[]
    FROM pg_proc
    WHERE oid = foid
  ;

  -- TODO: Verify # of fargs matches # of inputs

  -- Build call arguments by iterating through fargs and casting our inputs appropriately.
  call_args := array(
    SELECT format( '%L::%s', input, argtype )
      FROM unnest( inputs, fargs ) u( input, argtype )
  );

  sql := format(
    E'SELECT %s(\n%s\n)'
    , foid::oid::regproc
    , array_to_string( call_args, E'\n  , ' )
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql INTO out USING inputs;

  sql := 'DROP FUNCTION ' || foid::text;
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;
  RETURN out;
END
$body$;

-- vi: expandtab ts=2 sw=2

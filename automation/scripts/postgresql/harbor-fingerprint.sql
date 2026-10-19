-- 書き込み停止後に旧 DB と移行先の出力を比較する。行データは出力しない。
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
SET timezone = 'UTC';
SELECT format(
  'SELECT %L, count(*), md5(coalesce(string_agg(row_to_json(t)::text, E''\n'' ORDER BY row_to_json(t)::text), '''')) FROM %I.%I t;',
  schemaname || '.' || tablename, schemaname, tablename)
FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename
\gexec
SELECT format('SELECT %L, last_value, is_called FROM %I.%I;',
  schemaname || '.' || sequencename, schemaname, sequencename)
FROM pg_sequences WHERE schemaname = 'public' ORDER BY sequencename
\gexec

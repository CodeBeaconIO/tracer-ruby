-- Templating-trace inspection queries.
-- Run with:
--   tools/.venv/bin/python3 -c "import duckdb; c=duckdb.connect('test_applications/templating/.code-beacon/db/codebeacon_graph.duckdb'); print(c.sql(open('test_applications/templating/inspect.sql').read()))"
-- or just paste sections interactively.

-- 1. Every method that came from a .erb file.
--    Shows the raw mangled names, defined_class, file, and how many invocations
--    across the two traces. If "same template" is staying not-merged, we'll see
--    multiple rows that point at the same .erb file with different `method` names.
SELECT
  m.id                      AS method_id,
  m.tp_defined_class,
  m.method,
  m.block,
  m.file,
  m.line,
  COUNT(i.id)               AS invocations,
  COUNT(DISTINCT i.trace_id) AS traces_seen_in
FROM methods m
LEFT JOIN invocations i ON i.method_id = m.id
WHERE m.file LIKE '%.erb'
GROUP BY m.id, m.tp_defined_class, m.method, m.block, m.file, m.line
ORDER BY m.file, m.method;

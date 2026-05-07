# Plan: Capture method arguments in the tracer

## Context

The original `runtime_analysis` gem (predecessor to this gem, archived at `../original project/runtime_analysis/`) captured method arguments — as part of a broader "all locals + ivars + return" capture via `tp.binding` — and persisted them to a `locals` SQLite table. None of this survived the reduction that produced `codebeacon_tracer` for the release.

This plan ports the **arguments-only** subset back. Return values are already captured (column on `treenodes`) and stay where they are. No instance variables, no full locals, no per-line variable state. Schema and code mirror the original verbatim where possible; adapt only where this gem's structure demands.

A companion plan in `../integration-vscode/INLINE_VARIABLES_PLAN.md` covers the VS Code side (rendering these args inline). The contract between them is the `locals` table schema described below.

**Constraints:**
- Args only.
- Args go in a revived `locals` table with the original schema, verbatim.
- Return values stay on the `treenodes` column.
- Stay close to original; don't future-proof (no `kind` column, no `line` column, no instance vars, no block-call args yet).

---

## Schema contract (for the VS Code side)

```sql
CREATE TABLE IF NOT EXISTS locals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  value TEXT,
  to_s TEXT,
  inspect TEXT,
  treenode_id INTEGER,
  FOREIGN KEY (treenode_id) REFERENCES treenodes(id)
);
CREATE INDEX IF NOT EXISTS IDX_locals_treenode_id ON locals(treenode_id);
```

In Phase 1 every row is a method argument (one row per arg, FK to its treenode). The three string columns (`value`, `to_s`, `inspect`) all hold serialized representations of the same value — kept identical to original schema.

---

## Implementation

### 1. Revive `LocalVariableMapper` (new file)

**Create** `lib/codebeacon/tracer/src/data/local_variable_mapper.rb`. Port the original at `../original project/runtime_analysis/lib/runtime_analysis/src/data/local_variable_mapper.rb` verbatim, with two adaptations:

- Namespace it under `Codebeacon::Tracer` (matches sibling mappers like `TreeNodeMapper`, `MetadataMapper`).
- Replace the original's bare `(local[1].to_s rescue nil)` / `.inspect rescue nil` with `Codebeacon::Tracer::SafeSerializer.serialize(local[1], Codebeacon::Tracer.config.max_value_length)` for each of the three columns (`value`, `to_s`, `inspect`). This inherits the existing 10ms timeout + length cap (see `lib/codebeacon/tracer/src/data/safe_serializer.rb`). Schema stays unchanged.

### 2. Register the new mapper in `Database`

**Edit** `lib/codebeacon/tracer/src/data/database.rb`:

- In `create_tables` (lines 32–37), append `LocalVariableMapper.create_table(db)` after `BoundaryCallerMapper.create_table(db)`.
- In `create_indexes` (lines 39–44), append `LocalVariableMapper.create_indexes(db)`.

### 3. Auto-load the new file

**Edit** `lib/codebeacon-tracer.rb` to add a `require_relative` for the new mapper consistent with the existing auto-load pattern.

### 4. Capture args in `NodeBuilder.trace_call`

**Edit** `lib/codebeacon/tracer/src/models/node_builder.rb`:

- After line 102 (`current_context.self_type = klass.type`), and before the `gem_entry` block, add: `record_args(current_context, tp)`.
- Add a private class method `record_args` that mirrors the *shape* of the original's `record_locals` (original `node_builder.rb:260–273`) but only iterates `tp.parameters`:

  ```ruby
  private def record_args(current_context, tp)
    binding_obj = tp.binding
    current_context.locals = tp.parameters.filter_map do |(_kind, name)|
      next if name.nil?  # anonymous splats / blocks
      [name.to_s, binding_obj.local_variable_get(name)] rescue nil
    end
  rescue StandardError
    current_context.locals = []
  end
  ```

  Stores `[name_string, raw_value]` tuples — same shape original used. The mapper indexes via `local[0]` (name) / `local[1]` (value).

- Reuse the existing vestigial `:locals` attr_accessor on `TreeNode` (`lib/codebeacon/tracer/src/models/tree_node.rb:36`). No new field.

### 5. Persist args in `PersistenceManager`

**Edit** `lib/codebeacon/tracer/src/data/persistence_manager.rb`:

- In `initialize`, instantiate `@local_variable_mapper = LocalVariableMapper.new(@database)` alongside the other mappers (mirrors original line 28).
- In `_save_tree`, after `node_id` is captured (line 78) and before recursing into children (lines 99–102), add the inserts loop — mirrors original lines 56–58:

  ```ruby
  tree_node.locals.each do |local|
    @local_variable_mapper.insert(local, node_id)
  end
  ```

  The single transaction wrapping `save_trees` (lines 41 & 51) already covers these inserts — no extra transaction work needed.

### 6. Spec

**Create** `spec/data/local_variable_mapper_spec.rb`. Follow the structure of `spec/data/tree_node_mapper_spec.rb` (in-memory SQLite, `before(:all)` for table creation, `before(:each)` for row reset). Cover:

- `#insert` writes the row with name/value/to_s/inspect/treenode_id populated.
- `.create_table` produces expected columns.
- `.create_indexes` creates `IDX_locals_treenode_id`.

---

## Files modified / created

| File | Change |
|---|---|
| `lib/codebeacon/tracer/src/data/local_variable_mapper.rb` | **NEW** |
| `lib/codebeacon-tracer.rb` | `require_relative` the new mapper |
| `lib/codebeacon/tracer/src/data/database.rb` | Register `create_table` + `create_indexes` |
| `lib/codebeacon/tracer/src/models/node_builder.rb` | Add `record_args`, call from `trace_call` |
| `lib/codebeacon/tracer/src/data/persistence_manager.rb` | Instantiate mapper, insert locals after node_id |
| `spec/data/local_variable_mapper_spec.rb` | **NEW** |

---

## Verification

1. `bundle exec rspec spec/data/local_variable_mapper_spec.rb` — new spec passes.
2. `bundle exec rspec` — full suite stays green.
3. `bundle exec rubocop` — clean.
4. End-to-end: write a small script with a method taking a few args of varied types (string, integer, hash, anonymous splat). Run via `bin/codebeacon path/to/script.rb`. Then:
   ```
   sqlite3 .code-beacon/codebeacon_tracer_<latest>.db \
     "SELECT name, value, treenode_id FROM locals ORDER BY id LIMIT 20;"
   ```
   Confirm arg names + serialized values appear with correct FK to their treenode. Anonymous splats should be silently dropped (no row, no crash).

---

## Known limitations (intentional)

- `:call` events only — block calls (`:b_call`) don't capture args yet. Original captured both; defer until needed.
- No instance variables, no full locals, no per-line variable state.
- Return value still uses `treenodes.return_value` column, not the locals table. (Original lumped return as `['return', val]` into locals; the current column-based storage is strictly better and already shipped.)
- `tp.binding` is expensive; this is the first place in the current tracer that calls it. Acceptable for the feature; can be gated behind a config flag later if profiling demands.

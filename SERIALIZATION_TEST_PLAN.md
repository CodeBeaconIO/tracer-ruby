# Plan: Exercise tracer arg-capture serializers via Rails endpoint

## Goal

Generate controller + model code in `rails-base-app` that, when hit via a single
HTTP request, invokes a method per value-type below — each accepting a parameter
of that type. We then inspect the resulting `locals` table to verify all five
serializer columns (`to_s`, `inspect`, `json`, `yaml`, `pp`) handle each type
without crashing, truncate appropriately, and produce useful output.

This is **not** a test suite — no RSpec, no assertions. It's a reproducible
runtime exercise. Verification is manual SQL inspection.

## How the tracer captures

The tracer captures named method args at `:call` events via `tp.parameters` +
`tp.binding.local_variable_get`. Each arg becomes one row in `locals`, keyed
to its `treenodes.id`. Anonymous splats (`def foo(*)`) are silently dropped
(no row, no crash). Each row populates `to_s`, `inspect`, `json`, `yaml`, `pp`
columns via `Codebeacon::Tracer::SafeSerializer.safe_*` methods (timeout +
length cap + rescue → nil on failure).

Tracing only fires inside the configured `root_path` (the Rails app dir), so
methods must be defined in app code (controller / models / lib), not in stdlib
or gems.

## Endpoint shape

Add a single GET endpoint, e.g. `GET /tracer_probe` (route + controller
action). The action calls a series of one-line methods on a probe object,
each method taking one named arg of a specific type. Example pattern:

```ruby
class TracerProbeController < ApplicationController
  def show
    probe = Probe.new
    probe.with_nil(nil)
    probe.with_true(true)
    probe.with_integer(42)
    # ... one call per type below
    head :ok
  end
end

class Probe
  def with_nil(value); end
  def with_true(value); end
  def with_integer(value); end
  # ... one method per type
end
```

Method bodies can be empty — we only care that `:call` fires and `tp.binding`
exposes the named param. Method names should reflect the type so the
`treenodes.method` column makes the SQL inspection self-describing.

The endpoint must NOT require authentication (use `skip_before_action
:authenticate_user!` or mount it outside the auth chain) so we can hit it with
a plain `curl`.

## Type matrix

For each type, the agent should generate one method whose single named param is
that type. Sample values are suggestions — pick whatever exercises the
serializer.

### Primitives
- `nil`
- `true`, `false`
- `Integer` — small (`42`), large (`10**20`), negative
- `Float` — normal (`3.14`), `Float::INFINITY`, `Float::NAN`
- `BigDecimal` — `BigDecimal("3.14159265358979")`
- `Rational` — `Rational(1, 3)`
- `Complex` — `Complex(2, 3)`
- `Symbol` — `:hello_world`
- `String` — empty, ascii, utf-8 (`"héllo 🌍"`), multi-line (`"a\nb\nc"`), with quotes/backslashes (`'he said "hi" \\n'`)
- `String` (binary encoding) — `"\xff\xfe".b`
- `String` (very long) — 10_000-char string to verify length cap kicks in

### Collections
- `Array` — empty, of primitives (`[1, 2, 3]`), mixed (`[1, "two", :three, nil]`), nested (`[[1,[2,[3]]]]`)
- `Hash` — empty, symbol keys (`{a: 1, b: 2}`), string keys (`{"a" => 1}`), nested, mixed-key (`{1 => "a", :b => 2}`)
- `Range` — `(1..10)`, `(1...10)`, `("a".."z")`
- `Set` — `Set.new([1, 2, 3])` (`require "set"`)
- `Struct` — define a small Struct, instantiate it
- `OpenStruct` — `OpenStruct.new(name: "Alice", age: 30)`
- `Data` — `Data.define(:x, :y).new(x: 1, y: 2)` (Ruby 3.2+)

### Time / Date
- `Time` — `Time.now`
- `Date` — `Date.today`
- `DateTime` — `DateTime.now`
- `ActiveSupport::TimeWithZone` — `Time.zone.now`

### Rails-specific
- `ActiveRecord` model (unsaved, no associations) — `Post.new(title: "x")`
- `ActiveRecord` model (persisted) — find or create one
- `ActiveRecord::Relation` — `Post.where(title: "x")` (unloaded)
- `ActionController::Parameters` — `ActionController::Parameters.new(a: 1, b: { c: 2 })`
- `ActiveSupport::HashWithIndifferentAccess` — `{a: 1}.with_indifferent_access`

### Tricky / adversarial
- Class with `to_s` that raises (`def to_s; raise "boom"; end`)
- Class with `inspect` that raises
- Class that doesn't respond to `to_json`
- Circular reference: `a = []; a << a` (the array contains itself)
- Anonymous class instance: `Class.new.new`
- Proc — `->(x) { x }`
- Lambda — `lambda { |x| x }`
- Method — `Object.method(:itself)`
- File / IO — `File.open("/tmp/x", "w")` (close after; or use `StringIO.new("x")`)
- Object with custom `to_s` that takes >10ms (sleep loop) — verify timeout fallback `(serialization timeout)`

### Anonymous params (negative case)
- A method `def with_anon_splat(*); end` called with some args. Confirm: NO
  rows produced for this method's `treenode_id` (anonymous splats are silently
  dropped at capture time).

## Trigger + verify

After the agent generates the code:

```bash
# Restart rails server (TracePoint binds at boot — the tracer must reload)
# Then:
curl "http://localhost:3000/?rf__debug=true"           # warm-up (first request bypassed)
curl "http://localhost:3000/tracer_probe?rf__debug=true"

DB=/path/to/.code-beacon/db/codebeacon_tracer.db
sqlite3 "$DB" -header -column "
  SELECT t.method, l.name,
         substr(l.to_s,1,40)    AS to_s,
         substr(l.inspect,1,40) AS inspect,
         substr(l.json,1,40)    AS json,
         substr(l.yaml,1,40)    AS yaml,
         substr(l.pp,1,40)      AS pp
  FROM locals l JOIN treenodes t ON t.id = l.treenode_id
  ORDER BY l.id;"
```

## What to look for

- **Every type produces a row** with the expected `name` and a non-empty
  serialization in at least `to_s` and `inspect`.
- **Adversarial cases don't crash** the request — `to_s`-raising and
  `inspect`-raising columns return `nil`; circular array doesn't OOM.
- **JSON column is nil for non-JSON-serializable types** (Procs, IO, classes
  with no `to_json`) — that's fine and expected.
- **Length cap fires** on the 10k string — value ends with `"..."` and is
  ≤ `max_value_length` chars.
- **Timeout fires** on the slow `to_s` — column reads `"(serialization timeout)"`.
- **Anonymous splat method** has zero rows in `locals` for its `treenode_id`.

Document any types that produce surprising / unhelpful output — those become
candidates for follow-up serializer improvements.

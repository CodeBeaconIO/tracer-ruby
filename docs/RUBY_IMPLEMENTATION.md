# Ruby Implementation Notes

Specification-adjacent details that are specific to this Ruby tracer and do not
generalize to other-language implementations. Anything in the cross-language
specification lives in `SPECIFICATION.md`; rules that exist only because of
Ruby/Rails/Tilt internals live here.

## `node_label` resolvers

The `treenodes.node_label` column is defined in the cross-language spec
(`SPECIFICATION.md` §4 and §8.2). Implementations are free to choose their own
detection rules and rewrite formats. The rules below are what the Ruby tracer
uses today; they live in
`lib/codebeacon/tracer/src/data/node_label_resolver.rb`.

All resolvers run at persistence time only, inside the async persistence worker
— never inside a TracePoint callback.

### ActionView templates (Stage 1: path-only)

Triggered when `tree_node.file` ends in any of:

| Extension | Engine | Notes |
|-----------|--------|-------|
| `.erb`      | ERB / Erubi via `ActionView::Template` | Also covers plain `Tilt::ERBTemplate` files until the Tilt resolver lands. |
| `.haml`     | Haml via `ActionView::Template` | |
| `.slim`     | Slim via `ActionView::Template` (Temple-wrapped) | |
| `.builder`  | `ActionView::Template::Handlers::Builder` | XML builder DSL. |
| `.jbuilder` | `Jbuilder` handler for `ActionView::Template` | JSON builder DSL. |

Rewrite: take the substring after the last `/app/views/` segment in the file
path. So `…/app/views/pages/index.html.erb` → `pages/index.html.erb`. If the
file does not contain `/app/views/`, the resolver falls back to `File.basename`
of the file (the bare leaf name). For non-template files the resolver falls
back to `tree_node.method.to_s` so the column is **never null** — see the
specification's `node_label` definition (§4) for why this is the convention.

**Known limitation in Stage 1:** A method whose `tp.path` ends in a template
extension but whose `method_id` is *not* an ActionView-mangled name — most
commonly an inline `<% def helper %>` defined inside a template — will receive
a label that points at the enclosing template file, even though the method
itself is not the template's compiled body. Stage 2 adds a method-id-pattern
gate to drop these false positives.

### Planned

- **Stage 2**: also require `tree_node.method` to match the ActionView
  mangled-name shape `/\A_.+__-?\d+_\d+\z/`. The shape comes from
  `actionview/lib/action_view/template.rb` `method_name`:
  `"_#{identifier_method_name}__#{@identifier.hash}_#{__id__}"`.

- **Stage 3**: Tilt resolver. Tilt names compiled methods with the
  thread-object-id-based pattern `__tilt_<digits>` (see
  `tilt/lib/tilt/template.rb` `compile_template_method`). Because Tilt
  re-uses a single method-name slot on a given thread, two different
  templates produce the *same* method id within a process. The Tilt
  resolver detects the pattern and incorporates `tree_node.file` into the
  rewrite so different templates produce different `node_label` values.

## Out of scope (for now)

- `tp_defined_class` rewriting. The anonymous `Class.new(ActionView::Base)`
  subclasses that ActionView uses as `compiled_method_container` produce
  `tp_defined_class` values like `"#<Class:0x000…>"` whose pointer changes
  per process — fragmenting deduplication even for stably-named methods
  (e.g. inline helpers). This is a real problem but a separate, larger
  change; not addressed by the current `node_label` resolvers.

# frozen_string_literal: true

# Templating-tracing demonstrator.
#
# Pass one or more engine tags to scope the run. With no tag, runs everything.
# Each tag's engine-specific requires happen lazily, so a `tilt`-only run does
# NOT load ActionView/Haml/Slim/Sinatra/etc. (Keeps per-engine traces small
# enough to be useful in isolation.)
#
#   ruby run.rb                # all engines
#   ruby run.rb erb            # ERB through ActionView only
#   ruby run.rb tilt sinatra   # Tilt + Sinatra
#
# Tags & what each covers:
#
#   erb        Scenarios 1-5: ActionView ERB template fundamentals
#                1. same Template instance rendered 3x  -> SHOULD merge
#                2. different template rendered 2x      -> SHOULD merge with self
#                3. parent template calls child template
#                4. same identifier compiled as TWO different Template instances
#                   -> different __id__ -> different mangled name -> won't merge
#                5. inline <% def inline_helper %>: friendly method_id, but on the
#                   same anonymous ActionView::Base subclass
#   plain_erb  Scenario 6: ERB.new(src).result(binding) -> tp.path is "(erb)"
#   builder    Scenario 7: .xml.builder via ActionView
#   jbuilder   Scenario 8: .json.jbuilder via ActionView
#   inline     Scenario 9: ActionView Template from a string identifier (simulates
#              `render inline: "..."` -- no backing file)
#   generic    Scenarios 10-11: control cases. (10) class_eval'd attribute method
#              with friendly name -> should NOT trigger any template-rewrite.
#              (11) class_eval'd method whose NAME matches the ActionView mangled
#              shape but lives in a .rb file -> tests whether a method-name-only
#              rewrite (no path check) would false-fire.
#   haml       Scenario 12: .html.haml via ActionView
#   slim       Scenario 13: .html.slim via ActionView (Temple-wrapped handler)
#   tilt       Scenario 14: Tilt::ERBTemplate#render direct, no framework. Same
#              instance 2x + new instance 1x.
#   sinatra    Scenario 15: Sinatra::Base + ERB through Sinatra's Tilt pipeline.

SELECTED_TAGS = (ARGV.empty? ? [] : ARGV.flat_map { |a| a.split(",") }.map(&:to_sym)).freeze
puts "Scenario filter: #{SELECTED_TAGS.empty? ? '(all)' : SELECTED_TAGS.join(', ')}"

# Override the trace name (set by bin/codebeacon to "run.rb") so each per-engine
# trace can be identified in the derived graph's `traces.name` column. The script
# is loaded after Codebeacon::Tracer.start, so the active tracer already exists.
if defined?(Codebeacon::Tracer) && (label = ENV["CODEBEACON_TRACE_NAME"])
  active = Codebeacon::Tracer.instance_variable_get(:@tracer)
  active.name = label if active
end

def tag_active?(tag)
  SELECTED_TAGS.empty? || SELECTED_TAGS.include?(tag)
end

def scenario(name, tag:)
  return unless tag_active?(tag)

  puts "=== #{name} ==="
  yield
rescue => e
  puts "  !! #{name} FAILED: #{e.class}: #{e.message}"
  puts "     #{e.backtrace.first(3).join("\n     ")}"
end

# Per-engine setup runs only if at least one scenario for that tag will run.
# This is what keeps trace files small when filtering.
def with_setup(tag)
  yield if tag_active?(tag)
end

VIEWS_DIR = File.expand_path("app/views", __dir__)

# Shared ActionView bootstrap, used by erb/builder/jbuilder/inline/haml/slim.
# We don't want this work to show up in the tilt/plain_erb/generic/sinatra traces.
def setup_actionview
  return @actionview_setup if @actionview_setup

  require "action_view"
  require "action_view/template"
  require "action_view/template/handlers/erb"

  view_class = ActionView::Base.with_empty_template_cache
  view = view_class.with_view_paths([VIEWS_DIR])
  erb_handler = ActionView::Template.registered_template_handler(:erb)

  @actionview_setup = { view: view, erb_handler: erb_handler }
end

def build_template(handler, path, virtual_path, format: :html)
  source = File.read(path)
  ActionView::Template.new(
    source,
    path,
    handler,
    format: format,
    variant: nil,
    virtual_path: virtual_path,
    locals: [:greeting, :id, :render_partial]
  )
end

# --- ERB ---------------------------------------------------------------------
with_setup(:erb) do
  s = setup_actionview
  view, erb_handler = s[:view], s[:erb_handler]

  index_tmpl      = build_template(erb_handler, File.join(VIEWS_DIR, "pages/index.html.erb"),           "pages/index")
  show_tmpl       = build_template(erb_handler, File.join(VIEWS_DIR, "pages/show.html.erb"),            "pages/show")
  parent_tmpl     = build_template(erb_handler, File.join(VIEWS_DIR, "pages/with_partial.html.erb"),    "pages/with_partial")
  partial_tmpl    = build_template(erb_handler, File.join(VIEWS_DIR, "pages/_partial.html.erb"),        "pages/_partial")
  inline_def_tmpl = build_template(erb_handler, File.join(VIEWS_DIR, "pages/with_inline_def.html.erb"), "pages/with_inline_def")

  scenario("Scenario 1: index rendered 3x (same Template instance)", tag: :erb) do
    3.times { |i| index_tmpl.render(view, { greeting: "world-#{i}" }) }
  end

  scenario("Scenario 2: show rendered 2x (same Template instance)", tag: :erb) do
    2.times { |i| show_tmpl.render(view, { id: i }) }
  end

  scenario("Scenario 3: parent calls child template", tag: :erb) do
    render_partial = -> { partial_tmpl.render(view, {}) }
    parent_tmpl.render(view, { render_partial: render_partial })
  end

  scenario("Scenario 4: index recompiled as a NEW Template instance, rendered 2x", tag: :erb) do
    index_tmpl_again = build_template(erb_handler, File.join(VIEWS_DIR, "pages/index.html.erb"), "pages/index")
    2.times { |i| index_tmpl_again.render(view, { greeting: "redo-#{i}" }) }
  end

  scenario("Scenario 5: template with inline <% def %>, rendered 2x", tag: :erb) do
    2.times { inline_def_tmpl.render(view, {}) }
  end
end

# --- Plain ERB ---------------------------------------------------------------
with_setup(:plain_erb) do
  require "erb"

  scenario("Scenario 6: plain ERB.new(src).result(binding)", tag: :plain_erb) do
    def plain_erb_caller
      src = "<p>plain erb says <%= 1 + 1 %></p>"
      ERB.new(src).result(binding)
    end
    plain_erb_caller
    plain_erb_caller
  end
end

# --- Builder -----------------------------------------------------------------
with_setup(:builder) do
  s = setup_actionview
  view = s[:view]
  require "action_view/template/handlers/builder"
  builder_handler = ActionView::Template.registered_template_handler(:builder)
  builder_tmpl = build_template(builder_handler, File.join(VIEWS_DIR, "pages/feed.xml.builder"), "pages/feed", format: :xml)

  scenario("Scenario 7: Builder feed.xml.builder rendered 2x", tag: :builder) do
    2.times { builder_tmpl.render(view, {}) }
  end
end

# --- Jbuilder ----------------------------------------------------------------
with_setup(:jbuilder) do
  s = setup_actionview
  view = s[:view]
  require "jbuilder"
  require "jbuilder/jbuilder_template"
  unless ActionView::Template.registered_template_handler(:jbuilder)
    ActionView::Template.register_template_handler(:jbuilder, JbuilderHandler)
  end
  jbuilder_handler = ActionView::Template.registered_template_handler(:jbuilder)
  jbuilder_tmpl = build_template(jbuilder_handler, File.join(VIEWS_DIR, "pages/feed.json.jbuilder"), "pages/feed", format: :json)

  scenario("Scenario 8: Jbuilder feed.json.jbuilder rendered 2x", tag: :jbuilder) do
    2.times { jbuilder_tmpl.render(view, {}) }
  end
end

# --- Inline (ActionView from string identifier) ------------------------------
with_setup(:inline) do
  s = setup_actionview
  view, erb_handler = s[:view], s[:erb_handler]

  scenario("Scenario 9: ActionView Template from a string identifier, rendered 2x", tag: :inline) do
    inline_src = "<p>inline says hi to <%= local_assigns[:greeting] || 'anon' %></p>"
    inline_tmpl = ActionView::Template.new(
      inline_src,
      "inline:greeting",
      erb_handler,
      format: :html, variant: nil,
      virtual_path: nil,
      locals: [:greeting]
    )
    2.times { |i| inline_tmpl.render(view, { greeting: "n#{i}" }) }
  end
end

# --- Generic metaprogramming controls ----------------------------------------
with_setup(:generic) do
  scenario("Scenario 10: module_eval'd 'attribute' method, called 3x", tag: :generic) do
    require_relative "generated_accessors"
    gen = GeneratedAccessors.new(42)
    3.times { gen.attr_value }
  end

  scenario("Scenario 11: method with a mangled-looking name in a .rb file, called 2x", tag: :generic) do
    require_relative "mangled_name_lookalike"
    look = MangledNameLookalike.new
    2.times { look.send(:_app_views_fake_html_erb__1234567890_42) }
  end
end

# --- Haml --------------------------------------------------------------------
with_setup(:haml) do
  s = setup_actionview
  view = s[:view]
  require "haml"
  require "haml/rails_template"           # auto-registers :haml with ActionView::Template
  haml_handler = ActionView::Template.registered_template_handler(:haml)
  haml_tmpl = build_template(haml_handler, File.join(VIEWS_DIR, "pages/index.html.haml"), "pages/index_haml")

  scenario("Scenario 12: Haml index.html.haml rendered 2x", tag: :haml) do
    2.times { |i| haml_tmpl.render(view, { greeting: "haml-#{i}" }) }
  end
end

# --- Slim --------------------------------------------------------------------
with_setup(:slim) do
  s = setup_actionview
  view = s[:view]
  require "slim"
  require "temple"
  unless ActionView::Template.registered_template_handler(:slim)
    Temple::Templates::Rails(Slim::Engine,
                             register_as: :slim,
                             generator: Temple::Generators::RailsOutputBuffer,
                             disable_capture: true,
                             streaming: true)
  end
  slim_handler = ActionView::Template.registered_template_handler(:slim)
  slim_tmpl = build_template(slim_handler, File.join(VIEWS_DIR, "pages/index.html.slim"), "pages/index_slim")

  scenario("Scenario 13: Slim index.html.slim rendered 2x", tag: :slim) do
    2.times { |i| slim_tmpl.render(view, { greeting: "slim-#{i}" }) }
  end
end

# --- Tilt direct (no framework) ----------------------------------------------
with_setup(:tilt) do
  require "tilt"
  require "tilt/erb"

  tilt_scope_class = Class.new do
    def initialize(name) @name = name; end
    def name; @name; end
  end
  Object.const_set(:TiltScope, tilt_scope_class) unless defined?(TiltScope)

  scenario("Scenario 14: Tilt::ERBTemplate direct, same instance 2x + new instance 1x", tag: :tilt) do
    tilt_path = File.expand_path("tilt_direct.erb", __dir__)
    tilt_a = Tilt::ERBTemplate.new(tilt_path)
    2.times { |i| tilt_a.render(TiltScope.new("a-#{i}")) }
    tilt_b = Tilt::ERBTemplate.new(tilt_path)
    tilt_b.render(TiltScope.new("b"))
  end
end

# --- Sinatra -----------------------------------------------------------------
with_setup(:sinatra) do
  scenario("Scenario 15: Sinatra app /hello hit 2x", tag: :sinatra) do
    require_relative "sinatra_app"
    require "rack/mock"
    2.times do |i|
      env = Rack::MockRequest.env_for("/hello?greeting=sin-#{i}")
      SinatraApp.call(env)
    end
  end
end

puts "done."

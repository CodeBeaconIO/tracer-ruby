# frozen_string_literal: true

module Codebeacon
  module Tracer
    # Computes the `treenodes.node_label` value at persistence time.
    #
    # The trace-time hot path (TracePoint callbacks) does not call this; it runs
    # in the persistence worker thread, once per node, after the trace has
    # already been captured. Keep the per-call work cheap regardless — millions
    # of nodes can flow through here in a single trace.
    #
    # Stage 1: ActionView template detection by file-extension only. When the
    # node's file ends in a known template extension, returns the path under
    # `app/views/` (e.g. `pages/index.html.erb`); otherwise returns the raw
    # method name. Never returns nil — downstream tooling uses this column as
    # the primary identity key in place of the unstable raw `method` value.
    #
    # See docs/RUBY_IMPLEMENTATION.md for the rule catalogue and the upcoming
    # method-id-pattern (Stage 2) and Tilt (Stage 3) refinements.
    module NodeLabelResolver
      TEMPLATE_EXTENSIONS = %w[.erb .haml .slim .builder .jbuilder].freeze
      VIEWS_SEGMENT = "/app/views/"

      def self.resolve(tree_node)
        file = tree_node.file
        if file && TEMPLATE_EXTENSIONS.any? { |ext| file.end_with?(ext) }
          idx = file.rindex(VIEWS_SEGMENT)
          return idx ? file[(idx + VIEWS_SEGMENT.length)..] : File.basename(file)
        end

        tree_node.method.to_s
      end
    end
  end
end

# frozen_string_literal: true

module Codebeacon
  module Tracer
    module Compatibility
      # Compatibility shim for the `debug` gem (https://github.com/ruby/debug).
      #
      # When `debug` is loaded it installs an always-on `:script_compiled`
      # TracePoint regardless of whether any breakpoints are set or not.
      # In CodeBeacon, during persistence, we serialize values with `PP.pp`.
      # `PP.pp` reads each instance variable via instance_eval(String) which
      # triggers the `debug` :script_compiled TracePoint. This causes two
      # problems:
      # 
      # First, it adds enough overhead that it can easily push
      # the `PP.pp` serialization call beyond the default timeout, preventing
      # the data capture. Secondly, because Timeout functions by
      # asynchronously raising an exception in whatever code is currently
      # being executed, a problematic side effect occurs. The debug gem
      # aggressively captures Exceptions in its TracePoint handler and thus,
      # captures our Timeout. It does reraise, so from our perspective it
      # functions properly and doesn't cause a logic problem. The problem is
      # that the debug gem outputs an enormous amount of log data in its
      # exception handler. This is output to the users main process,
      # looks like real errors occurred and obfuscates the main process'
      # own logs. This issue as discovered on a relatively thin rails
      # endpoint yet still managed to output 10MB+ of debug error logs. 
      #
      # Marking a thread as a debug "management" thread makes debug's wait_reply
      # short-circuit (`return if management?`), so the handler does nothing on
      # that thread. This is exactly what debug does for its own internal
      # threads, and it is scoped per-thread: other threads' breakpoints and
      # source cataloging are unaffected. Running ruby debug against CodeBeacon
      # is an unlikely use case, but I left it as a config option to:
      # 1. Add visibility that we are doing this and
      # 2. Enable it to be turned back on, because it DOES technically work
      # 3. Disabling debug is an unexpected thing to do in general and not
      #    officially supported by ruby debug for external code AFAIK
      # 
      module DebugGem
        module_function

        # @return [Boolean] checks to see if the debug gem is loaded
        def active?
          defined?(DEBUGGER__::SESSION) && !DEBUGGER__::SESSION.nil?
        end

        # Marks the CURRENT thread as a debug "management" thread so debug does
        # no work on it. No-op when debug is absent.
        def suppress_current_thread
          return unless active?

          tc = DEBUGGER__::ThreadClient.current
          return unless tc.respond_to?(:mark_as_management)

          tc.mark_as_management
        rescue StandardError => e
          Codebeacon::Tracer.logger.debug("Compatibility::DebugGem: could not suppress current thread: #{e.message}")
        end
      end
    end
  end
end

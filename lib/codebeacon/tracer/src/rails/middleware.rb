module Codebeacon
  module Tracer
    class Middleware
      def initialize(app)
        @app = app
        @first_run = true
      end

      def call(env)
        response = nil
        # tracer = Tracer.news
        begin
          Codebeacon::Tracer.config.set_query_config(env['QUERY_STRING'])
          if !@first_run #Codebeacon::Tracer.config.trace_enabled? && !@first_run
            Codebeacon::Tracer.trace do |tracer|
              dry_run_log = Codebeacon::Tracer.config.dry_run? ? "--DRY RUN-- " : ""
              Codebeacon::Tracer.logger.info(dry_run_log + "Tracing enabled for URI=#{env['REQUEST_URI']}")
              response = @app.call(env).tap do |_|
                Codebeacon::Tracer.logger.info("Tracing disabled for URI=#{env['REQUEST_URI']}")
              end
              begin
                params = env['action_dispatch.request.parameters'].dup
                tracer.name = "#{params.delete('controller')}##{params.delete('action')}"
                tracer.description = params.to_json
              rescue => e
                Codebeacon::Tracer.logger.error("Error setting tracer metadata: #{e.message}")
              end
              response
            end
          else
            if Codebeacon::Tracer.config.trace_enabled? && @first_run
              Codebeacon::Tracer.logger.info("Bypassing first request for performance.")
            end
            @first_run = false if @first_run
            response = @app.call(env)
          end
        rescue => e
          Codebeacon::Tracer.logger.error("Error in middleware: #{e.message}")
          Codebeacon::Tracer.logger.error(e.backtrace.join("\n")) if Codebeacon::Tracer.config.debug?
          # Ensure the request is processed even if tracing fails
          response = @app.call(env) if response.nil?
        end
        response
      end
    end
  end
end

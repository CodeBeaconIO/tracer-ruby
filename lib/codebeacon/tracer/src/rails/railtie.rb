$first_run = true
module Codebeacon
  module Tracer
    class Railtie < Rails::Railtie
      initializer "codebeacon_tracer.middleware" do |app|
        app.middleware.use Codebeacon::Tracer::Middleware
      end
    end
  end
end

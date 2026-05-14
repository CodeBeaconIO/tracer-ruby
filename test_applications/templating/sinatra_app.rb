# frozen_string_literal: true

# Minimal Sinatra::Base subclass with an inline ERB template. Sinatra uses Tilt
# under the hood, so the rendered method lives on a Tilt-managed module, not
# on ActionView::Base. Useful for comparing tp.defined_class shape.
# Pin to a rack-2-compatible Sinatra; sinatra 4.x requires rack 3 which collides
# with actionview 7.0's rack-2 requirement.
gem "sinatra", "~> 3.0"
require "sinatra/base"

class SinatraApp < Sinatra::Base
  set :views, File.expand_path("app/views/pages", __dir__)

  get "/hello" do
    erb :sinatra_hello, locals: { greeting: params[:greeting] || "world" }
  end
end

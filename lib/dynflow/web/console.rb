require 'sprockets'
require 'sprockets-helpers'

module Dynflow
  module Web
    class Console < Sinatra::Base
      set :views, Dynflow::Web.web_dir('views')
      set :public_folder, Dynflow::Web.web_dir('assets')

      helpers Sprockets::Helpers

      set :sprockets, Sprockets::Environment.new

      configure do
        self.sprockets.append_path(Dynflow::Web.web_dir('assets/js'))
        self.sprockets.append_path(Dynflow::Web.web_dir('assets/css'))
        Dir.glob(Dynflow::Web.web_dir('assets/vendor/*')) do |path|
          self.sprockets.append_path(path)
        end

        Sprockets::Helpers.configure do |config|
          config.environment = sprockets
          config.debug = true if development?
          config.prefix = 'console/assets'
          #config.protocol = app.assets_protocol
          #config.asset_host = app.assets_host unless app.assets_host.nil?
        end
      end

      get "/assets/*" do |path|
        env_sprockets = request.env.dup
        env_sprockets['PATH_INFO'] = path
        settings.sprockets.call env_sprockets
      end

      get '/?*' do |path|
        erb :console, :layout => false
      end

    end
  end
end

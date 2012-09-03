require 'sinatra/base'
require 'sprockets'

class TentAdmin < Sinatra::Base
  configure :development do |config|
    require 'sinatra/reloader'
    register Sinatra::Reloader
    config.also_reload "*.rb"

  helpers do
    def path_prefix
      env['SCRIPT_NAME']
    end

    def full_path(path)
      "#{path_prefix}/#{path}"
    end
  end

  assets = Sprockets::Environment.new do |env|
    env.logger = Logger.new(STDOUT)
  end

  paths = %w{ javascripts stylesheets images }
  paths.each do |path|
    assets.append_path("assets/#{path}")
  end

  get '/assets/*' do
    new_env = env.clone
    new_env["PATH_INFO"].gsub!("/assets", "")
    assets.call(new_env)
  end

  get '/' do
    slim :dashboard
  end
end

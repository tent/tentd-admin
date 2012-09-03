require 'sinatra/base'
require 'sprockets'
require 'securerandom'

class TentAdmin < Sinatra::Base
  AdminConfig = Struct.new(:app, :app_authorization).new(nil, nil)

  enable :sessions
  set :session_secret, SecureRandom.hex(32)

  configure :development do |config|
    require 'sinatra/reloader'
    register Sinatra::Reloader
    config.also_reload "*.rb"

    # Setup Database
    DataMapper.setup(:default, ENV['DATABASE_URL'])
    DataMapper.auto_upgrade!

    # Init App/AppAuthorization
    mac_key_id = "00000000"
    unless tent_app = ::TentD::Model::App.first(:mac_key_id => mac_key_id)
      tent_app = ::TentD::Model::App.create(
        :name => "Tent Admin",
        :description => "Default Tent Admin App",
        :mac_key_id => mac_key_id
      )

      tent_app.authorizations.create(
        :scopes => %w{ read_posts write_posts import_posts read_profile write_profile read_followers write_followers read_followings write_followings read_groups write_groups read_permissions write_permissions read_apps write_apps follow_ui read_secrets write_secrets },
        :profile_info_types => ['all'],
        :post_types => ['all']
      )
    end
    AdminConfig.app = tent_app
    AdminConfig.app_authorization = tent_app.authorizations.first
  end

  use Rack::Auth::Basic, "Admin Area" do |username, password|
    username == ENV['ADMIN_USERNAME'] && password == ENV['ADMIN_PASSWORD']
  end

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

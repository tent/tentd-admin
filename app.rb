require 'bundler/setup'
require 'sinatra/base'
require 'sprockets'
require 'hashie'
require 'tentd'
require 'tent-client'
require 'rack/csrf'
require 'slim'

class TentDAdmin < Sinatra::Base
  AdminConfig = Struct.new(:app, :app_authorization).new(nil, nil)

  enable :sessions

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
        :mac_key_id => mac_key_id,
        :redirect_uris => %w{ http://localhost:5000/admin?foo=bar },
        :scopes => {
          "read_posts" => "Show posts feed",
          "write_posts" => "Publish posts",
          "read_profile" => "Read your profile"
        }
      )

      tent_app.authorizations.create(
        :scopes => %w{ read_posts write_posts import_posts read_profile write_profile read_followers write_followers read_followings write_followings read_groups write_groups read_permissions write_permissions read_apps write_apps follow_ui read_secrets write_secrets },
        :profile_info_types => ['all'],
        :post_types => ['all']
      )
    end

    # Set TENT_ENTITY ENV
    if !ENV['TENT_ENTITY']
      if info = ::TentD::Model::ProfileInfo.first(:type => TentD::Model::ProfileInfo::TENT_PROFILE_TYPE_URI)
        ENV['TENT_ENTITY'] = info.content['entity']
      end
    end

    AdminConfig.app = tent_app
    AdminConfig.app_authorization = tent_app.authorizations.first
  end

  use Rack::Auth::Basic, "Admin Area" do |username, password|
    username == ENV['ADMIN_USERNAME'] && password == ENV['ADMIN_PASSWORD']
  end

  use Rack::Csrf

  helpers do
    def path_prefix
      env['SCRIPT_NAME']
    end

    def full_path(path)
      "#{path_prefix}/#{path}".gsub(%r{//}, '/')
    end

    def csrf_tag
      Rack::Csrf.tag(env)
    end

    def scope_name(scope)
      {
        :read_posts        => "Read Posts",
        :write_posts       => "Write Posts",
        :import_posts      => "Import Posts",
        :read_profile      => "Read Profile",
        :write_profile     => "Write Profile",
        :read_followers    => "Read Followers",
        :write_followers   => "Write Followers",
        :read_followings   => "Read Followings",
        :write_followings  => "Write Followings",
        :read_groups       => "Read Groups",
        :write_groups      => "Write Groups",
        :read_permissions  => "Read Permissions",
        :write_permissions => "Write Permissions",
        :read_apps         => "Read Apps",
        :write_apps        => "Write Apps",
        :follow_ui         => "Follow UI",
        :read_secrets      => "Read Secrets",
        :write_secrets     => "Write Secrets"
      }[scope.to_sym]
    end
  end

  def server_url_from_env(env)
    env['rack.url_scheme'] + "://" + env['HTTP_HOST']
  end

  def tent_client(env)
    ::TentClient.new(server_url_from_env(env), AdminConfig.app_authorization.auth_details)
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

  before do
    if ::TentD::Model::ProfileInfo.count == 0 && env['PATH_INFO'] != '/setup' && env['PATH_INFO'] !~ /^\/assets/
      redirect full_path('setup')
      return
    end
  end

  get '/' do
    slim :dashboard
  end

  get '/setup' do
    if ::TentD::Model::ProfileInfo.count > 0
      redirect full_path('')
      return
    end

    @core_profile_info = Hashie::Mash.new(
      :entity => ENV['TENT_ENTITY'] || server_url_from_env(env),
      :servers => [server_url_from_env(env)]
    )

    slim :setup
  end

  post '/setup' do
    core_profile_info = {
      :entity => params[:entity],
      :servers => [params[:servers]],
      :licenses => [],
      :public => true
    }

    client = tent_client(env)
    client.profile.update(TentD::Model::ProfileInfo::TENT_PROFILE_TYPE_URI, core_profile_info)
    redirect full_path('')
  end

  get '/followings' do
    client = tent_client(env)
    @followings = client.following.fetch.body
    slim :followings
  end

  post '/followings' do
    client = tent_client(env)
    client.following.create(params[:entity])
    redirect full_path('/followings')
  end

  get '/auth/confirm' do
    @app_params = %w{ client_id redirect_uri state scope tent_profile_info_types tent_post_types }.inject({}) { |memo, k|
      memo[k] = params[k] if params.has_key?(k)
      memo
    }
    session[:current_app_params] = @app_params
    @app_params = Hashie::Mash.new(@app_params)

    client = tent_client(env)
    @app = session[:current_app] = client.app.find(@app_params.client_id).body
    @app = @app.kind_of?(Hash) ? Hashie::Mash.new(@app) : @app

    @app ||= "Invalid client_id"

    redirect_uri = URI(@app_params.redirect_uri.to_s)
    redirect_uri.query ||= ""
    if @app.kind_of?(String)
      redirect_uri.query += "error=#{URI.encode(@app)}"
      redirect redirect_uri.to_s
      return
    end

    unless @app.redirect_uris.to_a.include?(@app_params.redirect_uri)
      redirect_uri.query += 'error=invalid_redirect_uri'
      redirect redirect_uri.to_s
      return
    end

    if @app.authorizations.any?
      authorization = @app.authorizations.first
      redirect_uri.query +="&code=#{authorization.token_code}"
      redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
      redirect redirect_uri.to_s
      return
    end

    slim :auth_confirm
  end

  post '/auth/confirm' do
    @app = Hashie::Mash.new(session.delete(:current_app))
    @app_params = Hashie::Mash.new(session.delete(:current_app_params))

    redirect_uri = URI(@app_params.redirect_uri.to_s)
    redirect_uri.query ||= ""

    if params[:commit] == 'Abort'
      redirect_uri.query += "error=user_abort"
      redirect redirect_uri.to_s
      return
    end

    data = {
      :scopes => (@app.scopes || {}).inject([]) { |memo, (k,v)|
        params[k] == 'on' ? memo << k : nil
        memo
      },
      :profile_info_types => @app_params.tent_profile_info_types.to_s.split(',').select { |type|
        params[type] == 'on'
      },
      :post_types => @app_params.tent_post_types.to_s.split(',').select { |type|
        params[type] == 'on'
      }
    }
    client = tent_client(env)
    authorization = Hashie::Mash.new(client.app.authorization.create(@app.id, data).body)

    redirect_uri.query +="&code=#{authorization.token_code}"
    redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
    redirect redirect_uri.to_s
  end
end

require 'bundler/setup'
require 'sinatra/base'
require 'sprockets'
require 'hashie'
require 'tentd'
require 'tent-client'
require 'rack/csrf'
require 'slim'
require 'coffee_script'
require 'sass'

module TentD
  class Admin < Sinatra::Base
    AdminConfig = Struct.new(:app, :app_authorization).new(nil, nil)

    enable :sessions

    configure :development do |config|
      require 'sinatra/reloader'
      register Sinatra::Reloader
      config.also_reload "*.rb"

      config.method_override = true
    end

    configure do
      # Setup Database
      DataMapper.setup(:default, ENV['DATABASE_URL'])
      DataMapper.auto_upgrade!

      # Init App/AppAuthorization
      ::TentD::Model::User.current ||= ::TentD::Model::User.first_or_create
      mac_key_id = "00000000"
      unless tent_app = ::TentD::Model::App.first(:mac_key_id => mac_key_id)
        tent_app = ::TentD::Model::App.create(
          :name => "Tent Admin",
          :description => "Default Tent Admin App",
          :url => 'https://tent.io',
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
        core_type = TentD::TentType.new(TentD::Model::ProfileInfo::TENT_PROFILE_TYPE_URI)
        if info = ::TentD::Model::ProfileInfo.first(:type_base => core_type.base)
          ENV['TENT_ENTITY'] = info.content['entity']
        end
      end

      AdminConfig.app = tent_app
      AdminConfig.app_authorization = tent_app.authorizations.first
    end

    use Rack::Auth::Basic, "Admin Area" do |username, password|
      username == ENV['ADMIN_USERNAME'] && password == ENV['ADMIN_PASSWORD']
    end

    use Rack::Session::Cookie,  :key => 'tentd-adminapp.session',
                                :expire_after => 2592000, # 1 month
                                :secret => ENV['COOKIE_SECRET'] || SecureRandom.hex
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

      def method_override(method)
        "<input type='hidden' name='_method' value='#{method}' />"
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

      def nav_active_class(path)
        env['PATH_INFO'] == path ? 'active' : ''
      end

      def server_url
        env['rack.url_scheme'] + "://" + env['HTTP_HOST']
      end

      def tent_client
        ::TentClient.new(server_url, AdminConfig.app_authorization.auth_details)
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

      AdminConfig.app_authorization.update(:follow_url => "#{server_url}#{full_path('/followings')}")

      @core_profile_info = Hashie::Mash.new(
        :entity => ENV['TENT_ENTITY'] || server_url,
        :servers => [server_url]
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

      ENV['TENT_ENTITY'] = params[:entity]

      client = tent_client
      client.profile.update(TentD::Model::ProfileInfo::TENT_PROFILE_TYPE_URI, core_profile_info)
      redirect full_path('')
    end

    get '/profile' do
      client = tent_client
      @profile = client.profile.get.body
      @profile['https://tent.io/types/info/basic/v0.1.0'] ||= {
        'public' => true,
        'name' => 'Name to be displayed publicly',
        'avatar_url' => 'URL to avatar to be displayed publicly',
        'birthdate' => 'Date of birth in one of these formats: YYYY-MM-DD, YYYY-MM, MM-DD',
        'location' => 'Location to be displayed publicly',
        'gender' => 'Gender to be displayed publicly',
        'bio' => 'Biography/self-description to be displayed publicly'
      }
      slim :profile
    end

    put '/profile' do
      client = tent_client
      params.each_pair do |key, val|
        next unless key =~ %r{tent.io/types/info}
        client.profile.update(key, val)
      end

      redirect full_path('/profile')
    end

    get '/followings' do
      client = tent_client
      @followings = client.following.list.body
      @followings.map! { |f| Hashie::Mash.new(f) }
      @entity = URI.decode(params[:entity]) if params[:entity]
      slim :followings
    end

    post '/followings' do
      begin
        client = tent_client
        client.following.create(params[:entity])
        redirect full_path('/followings')
      rescue Faraday::Error::ConnectionFailed
        redirect full_path('/followings')
      end
    end

    delete '/followings/:id' do
      client = tent_client
      client.following.delete(params[:id])
      redirect full_path('/followings')
    end

    get '/followers' do
      client = tent_client
      @followers = client.follower.list.body
      @followers.map! { |f| Hashie::Mash.new(f) }
      slim :followers
    end

    delete '/followers/:id' do
      client = tent_client
      client.follower.delete(params[:id])
      redirect full_path('/followers')
    end

    get '/apps' do
      client = tent_client
      @apps = client.app.list.body
      @apps.kind_of?(Array) ? @apps.map! { |a| Hashie::Mash.new(a) } : @apps = []
      @apps = @apps.sort_by { |a| -a.authorizations.size }
      slim :apps
    end

    delete '/apps/:app_id' do
      client = tent_client
      client.app.delete(params[:app_id])
      redirect full_path('/apps')
    end

    delete '/apps/:app_id/authorizations/:app_auth_id' do
      client = tent_client
      client.app.authorization.delete(params[:app_id], params[:app_auth_id])
      redirect full_path('/apps')
    end

    get '/oauth/confirm' do
      @app_params = %w{ client_id redirect_uri state scope tent_profile_info_types tent_post_types tent_notification_url }.inject({}) { |memo, k|
        memo[k] = params[k] if params.has_key?(k)
        memo
      }
      session[:current_app_params] = @app_params
      @app_params = Hashie::Mash.new(@app_params)

      client = tent_client
      @app = session[:current_app] = client.app.get(@app_params.client_id).body
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

      # TODO: allow updating tent_profile_info_types, tent_post_types, scopes
      #       (user must confirm adding anything)

      if @app.authorizations.any?
        authorization = @app.authorizations.first

        unless authorization.notification_url == @app_params.tent_notification_url
          client = tent_client
          client.app.authorization.update(@app.id, authorization.id, :notification_url => @app_params.notification_url)
        end

        redirect_uri.query +="&code=#{authorization.token_code}"
        redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
        redirect redirect_uri.to_s
        return
      end

      slim :auth_confirm
    end

    post '/oauth/confirm' do
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
        },
        :notification_url => @app_params.tent_notification_url
      }
      client = tent_client
      authorization = Hashie::Mash.new(client.app.authorization.create(@app.id, data).body)

      redirect_uri.query +="&code=#{authorization.token_code}"
      redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
      redirect redirect_uri.to_s
    end
  end
end

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
require 'oj'

module TentD
  class Admin < Sinatra::Base
    require 'tentd-admin/sprockets/environment'

    configure do
      set :asset_manifest, Oj.load(File.read(ENV['ADMIN_ASSET_MANIFEST'])) if ENV['ADMIN_ASSET_MANIFEST']
      set :cdn_url, ENV['ADMIN_CDN_URL']

      set :method_override, true
    end

    use Rack::Csrf

    include SprocketsEnvironment

    helpers do
      def path_prefix
        env['SCRIPT_NAME']
      end

      def asset_path(path)
        path = asset_manifest_path(path) || assets.find_asset(path).digest_path
        if settings.cdn_url?
          "#{settings.cdn_url}/assets/#{path}"
        else
          full_path("/assets/#{path}")
        end
      end

      def asset_manifest_path(asset)
        if settings.respond_to?(:asset_manifest?) && settings.asset_manifest?
          settings.asset_manifest['files'].detect { |k,v| v['logical_path'] == asset }[0]
        end
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
        env['tent.client']
      end

      def current_user
        return unless defined?(TentD)
        current = TentD::Model::User.current
        current if session[:current_user_id] == current.id
      end

      def authenticate!
        halt 403 unless current_user
      end
    end

    if ENV['RACK_ENV'] != 'production' || ENV['SERVE_ASSETS']
      get '/assets/*' do
        new_env = env.clone
        new_env["PATH_INFO"].gsub!("/assets", "")
        assets.call(new_env)
      end
    end

    get '/' do
      authenticate!
      @profile = tent_client.profile.get.body
      @profile['https://tent.io/types/info/basic/v0.1.0'] ||= {
        'public' => true,
        'name' => '',
        'avatar_url' => '',
        'birthdate' => '',
        'location' => '',
        'gender' => '',
        'bio' => ''
      }

      @apps = tent_client.app.list.body
      @apps.kind_of?(Array) ? @apps.map! { |a| Hashie::Mash.new(a) } : @apps = []
      @apps = @apps.sort_by { |a| -a.authorizations.size }

      slim :dashboard
    end

    get '/signout' do
      session.clear
      redirect full_path('/')
    end

    put '/profile' do
      authenticate!
      params.each_pair do |key, val|
        next unless key =~ %r{tent.io/types/info}
        tent_client.profile.update(key, val)
      end

      redirect full_path('/')
    end

    delete '/apps/:app_id' do
      authenticate!
      tent_client.app.delete(params[:app_id])
      redirect full_path('/')
    end

    delete '/apps/:app_id/authorizations/:app_auth_id' do
      authenticate!
      tent_client.app.authorization.delete(params[:app_id], params[:app_auth_id])
      redirect full_path('/')
    end

    get '/oauth/confirm' do
      authenticate!
      @app_params = %w{ client_id redirect_uri state scope tent_profile_info_types tent_post_types tent_notification_url }.inject({}) { |memo, k|
        memo[k] = params[k] if params.has_key?(k)
        memo
      }
      session[:current_app_params] = @app_params
      @app_params = Hashie::Mash.new(@app_params)

      @app = session[:current_app] = tent_client.app.get(@app_params.client_id).body
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
          tent_client.app.authorization.update(@app.id, authorization.id, :notification_url => @app_params.notification_url)
        end

        redirect_uri.query +="&code=#{authorization.token_code}"
        redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
        redirect redirect_uri.to_s
        return
      end

      slim :auth_confirm
    end

    post '/oauth/confirm' do
      authenticate!
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
      authorization = Hashie::Mash.new(tent_client.app.authorization.create(@app.id, data).body)

      redirect_uri.query +="&code=#{authorization.token_code}"
      redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
      redirect redirect_uri.to_s
    end
  end
end

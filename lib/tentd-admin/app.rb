require 'bundler/setup'
require 'sinatra/base'
require 'sprockets'
require 'hashie'
require 'tentd'
require 'tent-client'
require 'slim'
require 'coffee_script'
require 'sass'
require 'securerandom'

module TentD
  class Admin < Sinatra::Base
    require 'tentd-admin/sprockets/environment'

    configure do
      set :assets, SprocketsEnvironment.assets
      set :asset_manifest, Yajl::Parser.parse(File.read(ENV['ADMIN_ASSET_MANIFEST'])) if ENV['ADMIN_ASSET_MANIFEST']
      set :cdn_url, ENV['ADMIN_CDN_URL']

      set :method_override, true
    end

    helpers do
      def path_prefix
        env['SCRIPT_NAME']
      end

      def asset_path(path)
        path = asset_manifest_path(path) || settings.assets.find_asset(path).digest_path
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

      def csrf_token
        session[:csrf_token] ||= SecureRandom.hex
      end

      def csrf_tag
        "<input type='hidden' name='_csrf' value='#{csrf_token}' />"
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

      def authenticate_csrf!
        halt 403 unless params[:_csrf] == session[:csrf_token]
      end

      def authenticate!
        halt 403 unless current_user
      end

      def basic_profile_uri
        'https://tent.io/types/info/basic/v0.1.0'
      end
    end

    if ENV['RACK_ENV'] != 'production' || ENV['SERVE_ASSETS'] || ENV['ADMIN_ASSET_MANIFEST']
      get '/assets/*' do
        asset = params[:splat].first
        path = "./public/assets/#{asset}"
        if File.exists?(path)
          content_type = case asset.split('.').last
                         when 'css'
                           'text/css'
                         when 'js'
                           'application/javascript'
                         end
          headers = { 'Content-Type' => content_type } if content_type
          [200, headers, [File.read(path)]]
        else
          if ENV['RACK_ENV'] != 'production' || ENV['SERVE_ASSETS']
            new_env = env.clone
            new_env["PATH_INFO"].gsub!("/assets", "")
            settings.assets.call(new_env)
          else
            halt 404
          end
        end
      end
    end

    get '/' do
      authenticate!
      @profile = tent_client.profile.get.body
      @profile[basic_profile_uri] ||= {}

      %w( name avatar_url birthdate location gender bio website_url ).each { |k| @profile[basic_profile_uri][k] ||= '' }
      @profile[basic_profile_uri]['public'] ||= true

      blacklist = %w( tent_version version )

      @profile.each_pair do |type, content|
        blacklist.each { |k| content.delete(k) }
      end

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
      authenticate_csrf!
      params.each_pair do |key, val|
        next unless key =~ %r{tent.io/types/info}
        (val['permissions'] ||= {})['public'] = true
        tent_client.profile.update(key, val)
      end

      redirect full_path('/')
    end

    delete '/apps/:app_id' do
      authenticate!
      authenticate_csrf!
      tent_client.app.delete(params[:app_id])
      redirect full_path('/')
    end

    delete '/apps/:app_id/authorizations/:app_auth_id' do
      authenticate!
      authenticate_csrf!
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

      @app = tent_client.app.get(@app_params.client_id).body
      session[:current_app_id] = @app['id']
      @app = @app.kind_of?(Hash) ? Hashie::Mash.new(@app) : @app

      @app ||= "invalid_client_id"

      redirect_uri = URI(@app_params.redirect_uri.to_s)
      redirect_uri.query ||= ""
      if @app.kind_of?(String)
        redirect_uri.query += "error=server_error&error_description=#{URI.encode(@app)}"
        redirect redirect_uri.to_s
        return
      end

      unless @app.redirect_uris.to_a.include?(@app_params.redirect_uri)
        redirect_uri.query += 'error=access_denied&error_description=invalid_redirect_uri'
        redirect redirect_uri.to_s
        return
      end

      if @app.authorizations.any?
        authorization = @app.authorizations.last

        session[:auth_id] = authorization.id

        unless authorization.notification_url == @app_params.tent_notification_url
          tent_client.app.authorization.update(@app.id, authorization.id, :notification_url => @app_params.notification_url)
        end

        if authorization.profile_info_types.to_a.sort == @app_params.tent_profile_info_types.to_s.split(',').sort &&
           authorization.post_types.to_a.sort == @app_params.tent_post_types.to_s.split(',').sort &&
           authorization.scopes.to_a.sort == @app_params.scope.to_s.split(',').sort

          redirect_uri.query += "&code=#{authorization.token_code}"
          redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
          redirect redirect_uri.to_s
          return
        end
      end

      slim :auth_confirm
    end

    post '/oauth/confirm' do
      authenticate!
      authenticate_csrf!
      @app = Hashie::Mash.new(tent_client.app.get(session.delete(:current_app_id)).body)
      @app_params = Hashie::Mash.new(session.delete(:current_app_params))
      auth_id = session.delete(:auth_id)

      redirect_uri = URI(@app_params.redirect_uri.to_s)
      redirect_uri.query ||= ""

      if params[:commit] == 'Abort'
        redirect_uri.query += "error=access_denied&error_description=user_abort"
        redirect redirect_uri.to_s
        return
      end

      data = {
        :scopes => @app_params.scope.to_s.split(',').inject([]) { |memo, scope|
          params[scope] == 'on' ? memo << scope : nil
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

      if auth_id
        res = tent_client.app.authorization.update(@app.id, auth_id, data)
      else
        res = tent_client.app.authorization.create(@app.id, data)
      end

      if res.success?
        authorization = Hashie::Mash.new(res.body)
        redirect_uri.query +="code=#{authorization.token_code}"
      else
        redirect_uri.query +="&error=access_denied&error_description=unknown"
      end

      redirect_uri.query += "&state=#{@app_params.state}" if @app_params.has_key?(:state)
      redirect redirect_uri.to_s
    end
  end
end

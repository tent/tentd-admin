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
    require 'tentd-admin/sprockets/environment'

    configure :development do |config|
      require 'sinatra/reloader'
      register Sinatra::Reloader
      config.also_reload "*.rb"

      config.method_override = true
    end

    use Rack::Csrf

    include SprocketsEnvironment

    helpers do
      def path_prefix
        env['SCRIPT_NAME']
      end

      def asset_path(path)
        path = assets.find_asset(path).digest_path
        if ENV['CDN_URL']
          "#{ENV['CDN_URL']}/assets/#{path}"
        else
          full_path("/assets/#{path}")
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
    end

    get '/assets/*' do
      new_env = env.clone
      new_env["PATH_INFO"].gsub!("/assets", "")
      assets.call(new_env)
    end

    get '/' do
      slim :dashboard
    end

    get '/profile' do
      @profile = tent_client.profile.get.body
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
      params.each_pair do |key, val|
        next unless key =~ %r{tent.io/types/info}
        tent_client.profile.update(key, val)
      end

      redirect full_path('/profile')
    end

    get '/followings' do
      @followings = tent_client.following.list.body
      @followings.map! { |f| Hashie::Mash.new(f) }
      @entity = URI.decode(params[:entity]) if params[:entity]
      slim :followings
    end

    post '/followings' do
      begin
        tent_client.following.create(params[:entity])
        redirect full_path('/followings')
      rescue Faraday::Error::ConnectionFailed
        redirect full_path('/followings')
      end
    end

    delete '/followings/:id' do
      tent_client.following.delete(params[:id])
      redirect full_path('/followings')
    end

    get '/followers' do
      @followers = tent_client.follower.list.body
      @followers.map! { |f| Hashie::Mash.new(f) }
      slim :followers
    end

    delete '/followers/:id' do
      tent_client.follower.delete(params[:id])
      redirect full_path('/followers')
    end

    get '/apps' do
      @apps = tent_client.app.list.body
      @apps.kind_of?(Array) ? @apps.map! { |a| Hashie::Mash.new(a) } : @apps = []
      @apps = @apps.sort_by { |a| -a.authorizations.size }
      slim :apps
    end

    delete '/apps/:app_id' do
      tent_client.app.delete(params[:app_id])
      redirect full_path('/apps')
    end

    delete '/apps/:app_id/authorizations/:app_auth_id' do
      tent_client.app.authorization.delete(params[:app_id], params[:app_auth_id])
      redirect full_path('/apps')
    end

    get '/oauth/confirm' do
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

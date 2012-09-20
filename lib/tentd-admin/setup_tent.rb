class SetupTent
  def initialize(app)
    @app = app
  end

  def call(env)
    TentD::Model::User.current = user = TentD::Model::User.first_or_create
    env['rack.session']['current_user_id'] = user.id
    set_client(env)
    create_core_profile(env)
    @app.call(env)
  end

  private

  def set_client(env)
    app = TentD::Model::App.first(:url => 'http://tent-admin') || create_app(env)
    auth = app.authorizations.first
    env['tent.app'] = app
    env['tent.app_auth'] = auth
    env['tent.client'] = TentClient.new(server_url(env), auth.auth_details)
  end

  def create_app(env)
    app = TentD::Model::App.create(
      :name => "Tent Admin",
      :description => "Tent Admin App",
      :url => 'http://tent-admin'
    )
    app.authorizations.create(
      :scopes => %w(read_posts write_posts import_posts read_profile write_profile read_followers write_followers read_followings write_followings read_groups write_groups read_permissions write_permissions read_apps write_apps follow_ui read_secrets write_secrets),
      :profile_info_types => ['all'],
      :post_types => ['all'],
      :follow_url => "#{server_url(env)}/admin/followings"
    )
    app
  end

  def create_core_profile(env)
    TentD::Model::ProfileInfo.first_or_create({ :type_base => 'https://tent.io/types/info/core' },
      :content => {
        :entity => server_url(env),
        :licenses => [],
        :servers => [server_url(env)]
      },
      :type_version => '0.1.0',
      :public => true
    )
  end

  def server_url(env)
    (env['HTTP_X_FORWARDED_PROTO'] || env['rack.url_scheme']) + '://' + env['HTTP_HOST']
  end
end

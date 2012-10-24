class SetEntity
  def initialize(app)
    @app = app
  end

  def call(env)
    env['tent.entity'] = ENV['TENT_ENTITY'] || ((env['HTTP_X_FORWARDED_PROTO'] || env['rack.url_scheme']) + '://' + env['HTTP_HOST'])
    @app.call(env)
  end
end

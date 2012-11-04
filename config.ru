lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'tentd'
require 'tentd-admin/app'
require 'tentd-admin/setup_tent'
require 'tentd-admin/set_entity'
require 'rack/ssl-enforcer'

DataMapper.finalize
DataMapper.setup(:default, ENV['DATABASE_URL'])
DataMapper.auto_upgrade!

use Rack::SslEnforcer, hsts: true if ENV['RACK_ENV'] == 'production'

map '/' do
  use SetEntity
  run TentD.new
end

map '/oauth' do
  run lambda { |env|
    auth_url = (env['HTTP_X_FORWARDED_SCHEME'] || env['rack.url_scheme']) + '://
' + (env['HTTP_X_FORWARDED_SERVER'] || env['HTTP_HOST'])
    auth_url += '/admin/oauth/confirm'
    auth_url += "?#{env['QUERY_STRING']}"
    [301, { "Location" => auth_url }, []] }
end

map '/admin' do
  use Rack::Session::Cookie,  :key => 'tent.session',
                              :expire_after => 2592000, # 1 month
                              :secret => ENV['COOKIE_SECRET'] || SecureRandom.hex
  use(Rack::Auth::Basic, 'Tent Admin') { |u,p| u == ENV['ADMIN_USERNAME'] && p == ENV['ADMIN_PASSWORD'] }
  use SetupTent
  run TentD::Admin
end

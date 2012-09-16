lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'tentd-admin/app'

map '/' do
  run TentD.new
end

map '/oauth' do
  run lambda { |env|
    auth_url = env['rack.url_scheme'] + '://' + env['HTTP_HOST']
    auth_url += '/admin/oauth/confirm'
    auth_url += "?#{env['QUERY_STRING']}"
    [301, { "Location" => auth_url }, []] }
end

map '/admin' do
  use Rack::Session::Cookie,  :key => 'tentd-adminapp.session',
                              :expire_after => 2592000, # 1 month
                              :secret => ENV['COOKIE_SECRET'] || SecureRandom.hex
  run TentD::Admin
end

require './app'

map '/' do
  run TentD.new
end

map '/auth' do
  run lambda { |env|
    auth_url = env['rack.url_scheme'] + '://' + env['HTTP_HOST']
    auth_url += '/admin/auth/confirm'
    auth_url += "?#{env['QUERY_STRING']}"
    [301, { "Location" => auth_url }, []] }
end

map '/admin' do
  run TentDAdmin
end

require 'bundler'
Bundler.require

require './app'

map '/' do
  run TentD.new(
    :database => "postgres://localhost/tent-admin"
  )

  DataMapper.auto_upgrade!
end

map '/admin' do
  run TentAdmin
end

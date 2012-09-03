require 'bundler'
Bundler.require

require './app'

map '/' do
  run TentD.new
end

map '/admin' do
  run TentAdmin
end

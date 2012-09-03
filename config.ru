require 'bundler'
Bundler.require

require './app'

use Rack::CommonLogger

map '/' do
  run TentD.new
end

map '/admin' do
  run TentAdmin
end

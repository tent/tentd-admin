require "bundler/gem_tasks"
require 'rake/sprocketstask'
require 'tentd-admin/sprockets/environment'
require 'uglifier'

Rake::SprocketsTask.new do |t|
  t.environment = Sprockets::Environment.new
  %w{ javascripts stylesheets images }.each do |path|
    t.environment.append_path("assets/#{path}")
  end
  t.environment.js_compressor = Uglifier.new
  t.output      = "./public/assets"
  t.assets      = %w( application.js application.css chosen-sprite.png )

  t.environment.context_class.class_eval do
    include SprocketsHelpers
  end
end

task :deploy_assets => :assets do
  require './config/asset_sync'
  AssetSync.sync
end

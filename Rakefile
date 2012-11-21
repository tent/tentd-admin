require 'bundler/gem_tasks'
require 'bundler/setup'
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

task :gzip_assets => :assets do
  Dir['public/assets/**/*.*'].reject { |f| f =~ /\.gz\z/ }.each do |f|
    sh "gzip -c #{f} > #{f}.gz" unless File.exist?("#{f}.gz")
  end
end

task :deploy_assets => :gzip_assets do
  require './config/asset_sync'
  AssetSync.sync
end

namespace :db do
  task :migrate do
    %x{bundle exec sequel -m `bundle show tentd`/db/migrations #{ENV['DATABASE_URL']}}
  end
end

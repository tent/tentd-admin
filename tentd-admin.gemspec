# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'tentd-admin/version'

Gem::Specification.new do |gem|
  gem.name          = "tentd-admin"
  gem.version       = Tentd::Admin::VERSION
  gem.authors       = ["Jesse Stuart", "Jonathan Rudenberg"]
  gem.email         = ["jessestuart@gmail.com", "jonathan@titanous.com"]
  gem.description   = %q{Default app for managing Tent server administration (e.g. apps, profile, followings, followers)}
  gem.summary       = %q{Admin app for Tent}
  gem.homepage      = "https://github.com/tent/tentd-admin"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency 'tent-client'
  gem.add_runtime_dependency 'tentd'

  gem.add_runtime_dependency 'sinatra'
  gem.add_runtime_dependency 'sprockets', '~> 2.0'
  gem.add_runtime_dependency 'sass'
  gem.add_runtime_dependency 'coffee-script'
  gem.add_runtime_dependency 'hashie'
  gem.add_runtime_dependency 'slim', '1.3.0'
  gem.add_runtime_dependency 'uglifier'

  gem.add_development_dependency 'rake'
end

require 'tentd-admin/sprockets/helpers'

module TentD
  class Admin
    module SprocketsEnvironment
      def self.assets
        return @assets if defined?(@assets)
        @assets = Sprockets::Environment.new do |env|
          env.logger = Logger.new(STDOUT)
          env.context_class.class_eval do
            include SprocketsHelpers
          end
        end

        paths = %w{ javascripts stylesheets images }
        paths.each do |path|
          @assets.append_path((File.join(File.expand_path('../../../../', __FILE__), "assets/#{path}")))
        end
        @assets
      end
    end
  end
end

# frozen_string_literal: true

module ::DiscourseRssOnebox
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseRssOnebox

    config.to_prepare do
      Dir[File.expand_path(File.join("..", "..", "..", "app", "jobs", "**", "*.rb"), __FILE__)].each do |job|
        require_dependency job
      end
    end
  end
end

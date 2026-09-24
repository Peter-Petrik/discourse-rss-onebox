# frozen_string_literal: true

DiscourseRssOnebox::Engine.routes.draw do
  get "display_names" => "display_names#index", :constraints => AdminConstraint.new
  post "display_names/refresh" => "display_names#refresh", :constraints => AdminConstraint.new
  put "display_names/:feed_id" => "display_names#update", :constraints => AdminConstraint.new
end

# Serves the admin application for direct loads of the Display names page, the same way core serves its own admin pages.
Discourse::Application.routes.draw do
  scope "/admin/plugins/discourse-rss-onebox", constraints: AdminConstraint.new do
    get "/display-names" => "admin/admin#index"
  end
end

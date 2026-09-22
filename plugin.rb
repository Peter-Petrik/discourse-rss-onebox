# frozen_string_literal: true

# name: discourse-rss-onebox
# about: Renders RSS Polling imports in selected categories as a onebox of the article URL and hides "Show Full Post" there
# version: 0.1.0
# authors: Peter Petrik
# url: https://github.com/Peter-Petrik/discourse-rss-onebox

enabled_site_setting :rss_onebox_enabled

after_initialize do
  # Core's TopicEmbed.import passes its PostCreator arguments through this modifier before creating the topic. Replacing the body with the bare article URL lets core's onebox build the preview (title, og:image, og:description) from the article page, instead of the feed body truncated to its first paragraphs. The modifier only runs while the plugin is enabled (DiscoursePluginRegistry.apply_modifier checks plugin enabled state).
  register_modifier(:topic_embed_import_create_args) do |args|
    category_id = args[:category].to_i

    if SiteSetting.rss_onebox_categories_map.include?(category_id) && args[:embed_url].present?
      args[:raw] = args[:embed_url]
      # Imports are stored as raw HTML unless embed_support_markdown is enabled; raw HTML is never oneboxed, so Markdown cooking is forced here.
      args[:cook_method] = Post.cook_methods[:regular]
    end

    args
  end

  # "Show Full Post" re-scrapes the article page and is redundant once the post is a onebox. The attribute is omitted for topics in the configured categories; elsewhere core's original condition applies. respect_plugin_enabled is false because the default would hide the button site-wide whenever the plugin is disabled, so the enabled check is made explicitly instead.
  add_to_serializer(
    :topic_view,
    :expandable_first_post,
    respect_plugin_enabled: false,
    include_condition: -> do
      object.topic.expandable_first_post? &&
        !(
          SiteSetting.rss_onebox_enabled &&
            SiteSetting.rss_onebox_categories_map.include?(object.topic.category_id)
        )
    end,
  ) { true }
end

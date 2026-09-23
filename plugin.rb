# frozen_string_literal: true

# name: discourse-rss-onebox
# about: Renders RSS Polling imports in selected categories as a onebox of the article URL and hides "Show Full Post" there
# version: 0.1.2
# authors: Peter Petrik
# url: https://github.com/Peter-Petrik/discourse-rss-onebox

enabled_site_setting :rss_onebox_enabled

module ::DiscourseRssOnebox
  # TopicEmbed.normalize_url lowercases the URL stored in embed_url, which breaks case-sensitive URLs such as YouTube video IDs. Before normalising, TopicEmbed.import appends an "imported from" footer that links to the original URL, so the last link in that footer is taken as the original. It is accepted only if it normalises to the same value as embed_url; otherwise embed_url is returned unchanged.
  def self.original_url(raw, embed_url)
    href = Nokogiri::HTML5.fragment(raw.to_s).css("small a[href]").last&.[]("href")
    return embed_url if href.blank?

    TopicEmbed.normalize_url(href) == embed_url ? href : embed_url
  rescue StandardError
    embed_url
  end
end

after_initialize do
  # Core's TopicEmbed.import passes its PostCreator arguments through this modifier before creating the topic. Replacing the body with the bare article URL lets core's onebox build the preview (title, og:image, og:description) from the article page, instead of the feed body truncated to its first paragraphs. The modifier only runs while the plugin is enabled (DiscoursePluginRegistry.apply_modifier checks plugin enabled state).
  register_modifier(:topic_embed_import_create_args) do |args|
    category_id = args[:category].to_i

    if SiteSetting.rss_onebox_categories_map.include?(category_id) && args[:embed_url].present?
      args[:raw] = ::DiscourseRssOnebox.original_url(args[:raw], args[:embed_url])
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

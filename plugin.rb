# frozen_string_literal: true

# name: discourse-rss-onebox
# about: Renders RSS Polling imports in selected categories as a onebox of the article URL, with optional feed summaries and YouTube descriptions, and hides "Show Full Post" there
# version: 0.2.0
# authors: Peter Petrik
# url: https://github.com/Peter-Petrik/discourse-rss-onebox

enabled_site_setting :rss_onebox_enabled

register_asset "stylesheets/rss-onebox.scss"

require_relative "lib/discourse_rss_onebox/feed_reader"
require_relative "lib/discourse_rss_onebox/renderer"

module ::DiscourseRssOnebox
  def self.configured?(category_id)
    SiteSetting.rss_onebox_enabled &&
      SiteSetting.rss_onebox_categories_map.include?(category_id.to_i)
  end

  # TopicEmbed.normalize_url lowercases the URL stored in embed_url, which breaks case-sensitive URLs such as YouTube video IDs. Before normalising, TopicEmbed.import appends an "imported from" footer that links to the original URL, so the last link in that footer is taken as the original. It is accepted only if it normalises to the same value as embed_url; otherwise embed_url is returned unchanged.
  def self.original_url(raw, embed_url)
    href = Nokogiri::HTML5.fragment(raw.to_s).css("small a[href]").last&.[]("href")
    return embed_url if href.blank?

    TopicEmbed.normalize_url(href) == embed_url ? href : embed_url
  rescue StandardError
    embed_url
  end

  # A post is correct when its body is a bare URL that normalises to the embed URL; this accepts original-case URLs and trailing slashes.
  def self.onebox_body?(raw, embed_url)
    body = raw.to_s.strip
    body.match?(%r{\Ahttps?://\S+\z}) && TopicEmbed.normalize_url(body) == embed_url
  end

  # Restores the onebox body without creating a revision, bump, or notification.
  def self.restore_body!(post, url)
    post.update_columns(raw: url, cook_method: Post.cook_methods[:regular])
    post.rebake!
  end

  # Wraps TopicEmbed.import. For topics already imported into a configured category, feed-content changes are ignored: the stored content fingerprint is set to the value core is about to compute, so core does not revise the body. Title, tag, and author changes still go through core. If core revises the body anyway (a title or tag change always rewrites it, as would a future change to core's processing), the body is restored silently afterwards.
  # Wraps RSS Polling's poll job so that, during a poll, the plugin knows which feed is being imported and can read that feed's XML once for summaries and video descriptions.
  module PollFeedPatch
    def execute(args)
      Thread.current[:rss_onebox_feed_url] = args[:feed_url]
      Thread.current[:rss_onebox_feed_data] = nil
      super
    ensure
      Thread.current[:rss_onebox_feed_url] = nil
      Thread.current[:rss_onebox_feed_data] = nil
    end
  end

  module TopicEmbedImportPatch
    def import(user, url, title, contents, category_id: nil, cook_method: nil, tags: nil)
      embed = url.to_s.match?(%r{\Ahttps?://}) ? topic_embed_by_url(url) : nil
      protect = embed&.topic.present? && ::DiscourseRssOnebox.configured?(embed.topic.category_id)

      if protect
        # Mirrors the contents processing at the top of TopicEmbed.import (truncation, then the "imported from" footer) so the fingerprint matches what core computes.
        processed = contents.to_s
        processed = first_paragraph_from(processed) if SiteSetting.embed_truncate && cook_method.nil?
        processed = (processed || "").dup << imported_from_html(url)
        sha1 = Digest::SHA1.hexdigest(processed)
        embed.update_column(:content_sha1, sha1) if embed.content_sha1 != sha1
      end

      post = super

      if protect && post && !::DiscourseRssOnebox.onebox_body?(post.raw, embed.embed_url)
        ::DiscourseRssOnebox.restore_body!(post, url)
      end

      post
    end
  end
end

after_initialize do
  reloadable_patch do
    TopicEmbed.singleton_class.prepend(::DiscourseRssOnebox::TopicEmbedImportPatch)
    begin
      ::Jobs::DiscourseRssPolling::PollFeed.prepend(::DiscourseRssOnebox::PollFeedPatch)
    rescue NameError
      # RSS Polling is not present; new imports get no stored feed data.
    end
  end

  # Adds stored feed data (summary, YouTube description) to the rendered post. Runs only while the plugin is enabled.
  on(:post_process_cooked) { |doc, post| ::DiscourseRssOnebox::Renderer.apply(doc, post) }

  # Core's TopicEmbed.import passes its PostCreator arguments through this modifier before creating the topic. Replacing the body with the bare article URL lets core's onebox build the preview (title, og:image, og:description) from the article page, instead of the feed body truncated to its first paragraphs. The modifier only runs while the plugin is enabled (DiscoursePluginRegistry.apply_modifier checks plugin enabled state).
  register_modifier(:topic_embed_import_create_args) do |args|
    if ::DiscourseRssOnebox.configured?(args[:category]) && args[:embed_url].present?
      args[:raw] = ::DiscourseRssOnebox.original_url(args[:raw], args[:embed_url])
      # Imports are stored as raw HTML unless embed_support_markdown is enabled; raw HTML is never oneboxed, so Markdown cooking is forced here.
      args[:cook_method] = Post.cook_methods[:regular]

      # Stores the item's feed summary or YouTube description on the post, whether or not the display settings are on, so turning them on later needs only a rebake.
      if (data = ::DiscourseRssOnebox::FeedReader.current_item(args[:embed_url]))
        fields = {}
        fields[::DiscourseRssOnebox::SUMMARY_FIELD] = data[:summary] if data[:summary].present?
        fields[::DiscourseRssOnebox::VIDEO_FIELD] = data[:video_description] if data[:video_description].present?
        args[:custom_fields] = (args[:custom_fields] || {}).merge(fields) if fields.present?
      end
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
        !::DiscourseRssOnebox.configured?(object.topic.category_id)
    end,
  ) { true }
end

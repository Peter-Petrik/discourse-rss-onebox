# frozen_string_literal: true

# name: discourse-rss-onebox
# about: Renders RSS Polling imports in selected categories as a onebox of the article URL, with optional feed summaries, YouTube descriptions, and title formats, and hides "Show Full Post" there
# version: 0.2.6
# authors: Peter Petrik
# url: https://github.com/Peter-Petrik/discourse-rss-onebox

enabled_site_setting :rss_onebox_enabled

register_asset "stylesheets/rss-onebox.scss"

add_admin_route "rss_onebox.title", "discourse-rss-onebox", { use_new_show_route: true }

module ::DiscourseRssOnebox
  PLUGIN_NAME = "discourse-rss-onebox"
end

require_relative "lib/discourse_rss_onebox/engine"
require_relative "lib/discourse_rss_onebox/feed_reader"
require_relative "lib/discourse_rss_onebox/renderer"

Discourse::Application.routes.append { mount ::DiscourseRssOnebox::Engine, at: "/admin/plugins/rss_onebox" }

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

  ORIGINAL_TITLE_FIELD = "rss_onebox_original_title"
  SOURCE_FIELD = "rss_onebox_source_name"
  FEED_ID_FIELD = "rss_onebox_feed_id"

  # Display names are set on the plugin's Display names admin page and stored per RSS Polling feed ID, so they survive changes to a feed's published name or URL.
  def self.display_name(feed_id)
    feed_id.present? ? PluginStore.get(PLUGIN_NAME, "display_name:#{feed_id}").presence : nil
  end

  def self.published_name(feed_id)
    feed_id.present? ? PluginStore.get(PLUGIN_NAME, "published_name:#{feed_id}").presence : nil
  end

  # Records a feed's published name. Returns true when it changed.
  def self.record_published_name(feed_id, name)
    return false if feed_id.blank? || name.blank?
    return false if published_name(feed_id) == name
    PluginStore.set(PLUGIN_NAME, "published_name:#{feed_id}", name)
    true
  end

  # The name used for %{source}: the feed's display name, else its published name.
  def self.resolve_source(feed_id, published)
    display_name(feed_id) || published.presence || published_name(feed_id)
  end

  # Rebuilds a topic's title from its stored original title, feed ID, and published source name, renaming silently when it differs. Used by the re-render job and the enhance task.
  def self.rerender_title!(post)
    topic = post.topic
    fields = post.custom_fields
    original = fields[ORIGINAL_TITLE_FIELD].presence || topic.title
    source = resolve_source(fields[FEED_ID_FIELD], fields[SOURCE_FIELD])
    desired = format_title(original, source, youtube: youtube_url?(post.raw.strip))
    return false if topic.title == desired
    rename!(topic, desired)
    true
  end
  TITLE_PLACEHOLDERS = /%\{(title|source)\}/

  def self.youtube_url?(url)
    url.to_s.match?(%r{\Ahttps?://(www\.)?youtube\.com/watch}i)
  end

  # Builds the displayed title from the feed's original title and source name, using the blog or YouTube format setting. An empty format, a blank original title, or a format needing %{source} when no source name is known leaves the original title unchanged. The result is cut to max_topic_title_length.
  def self.format_title(original, source, youtube:)
    format = youtube ? SiteSetting.rss_onebox_youtube_title_format : SiteSetting.rss_onebox_blog_title_format
    return original if format.blank? || original.blank?
    return original if format.include?("%{source}") && source.blank?

    result = format.gsub(TITLE_PLACEHOLDERS) { $1 == "title" ? original : source }.squish
    return original if result.blank?

    max = SiteSetting.max_topic_title_length
    result.length > max ? "#{result[0, max - 1].rstrip}…" : result
  end

  def self.format_needs_source?(youtube)
    format = youtube ? SiteSetting.rss_onebox_youtube_title_format : SiteSetting.rss_onebox_blog_title_format
    format.to_s.include?("%{source}")
  end

  # Renames a topic without a revision, bump, or notification. Assigning the title updates the slug and fancy title, and saving re-indexes the topic for search.
  def self.rename!(topic, title)
    topic.title = title
    topic.save!(validate: false)
  end

  # Stores the feed's original title, published source name, and feed ID on the first post, saving only when something changed.
  def self.store_title_data!(post, original, source, feed_id = nil)
    fields = post.custom_fields
    changed = false
    { ORIGINAL_TITLE_FIELD => original, SOURCE_FIELD => source, FEED_ID_FIELD => feed_id&.to_s }.each do |key, value|
      next if value.blank? || fields[key] == value
      fields[key] = value
      changed = true
    end
    post.save_custom_fields(true) if changed
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

  # Wraps RSS Polling's poll job so that, during a poll, the plugin knows which feed is being imported and can read that feed's XML once for summaries and video descriptions.
  module PollFeedPatch
    def execute(args)
      Thread.current[:rss_onebox_feed_url] = args[:feed_url]
      Thread.current[:rss_onebox_feed_id] = args[:rss_feed_id]
      Thread.current[:rss_onebox_feed_data] = nil
      super
    ensure
      Thread.current[:rss_onebox_feed_url] = nil
      Thread.current[:rss_onebox_feed_id] = nil
      Thread.current[:rss_onebox_feed_data] = nil
    end
  end

  # Wraps TopicEmbed.import. For topics already imported into a configured category, feed-content changes are ignored: the stored content fingerprint is set to the value core is about to compute, so core does not revise the body. Title, tag, and author changes still go through core. If core revises the body anyway (a title or tag change always rewrites it, as would a future change to core's processing), the body is restored silently afterwards. Keyword arguments added to TopicEmbed.import by newer Discourse versions (such as truncate:) are passed through unchanged.
  module TopicEmbedImportPatch
    def import(user, url, title, contents, category_id: nil, cook_method: nil, tags: nil, **options)
      embed = url.to_s.match?(%r{\Ahttps?://}) ? topic_embed_by_url(url) : nil
      protect = embed&.topic.present? && ::DiscourseRssOnebox.configured?(embed.topic.category_id)
      configured = protect || (embed.nil? && ::DiscourseRssOnebox.configured?(category_id))
      original_title = title

      feed_id = nil
      if configured && title.present?
        youtube = ::DiscourseRssOnebox.youtube_url?(url)
        fields = protect ? embed.post&.custom_fields : nil
        feed_id = Thread.current[:rss_onebox_feed_id].presence || fields&.[](::DiscourseRssOnebox::FEED_ID_FIELD)
        polled = Thread.current[:rss_onebox_feed_data] ? ::DiscourseRssOnebox::FeedReader.current_source : nil
        published = polled || fields&.[](::DiscourseRssOnebox::SOURCE_FIELD)
        needs_source = ::DiscourseRssOnebox.format_needs_source?(youtube)
        if published.blank? && needs_source && ::DiscourseRssOnebox.display_name(feed_id).blank?
          published = ::DiscourseRssOnebox::FeedReader.current_source
        end
        source = ::DiscourseRssOnebox.resolve_source(feed_id, published)
        title = ::DiscourseRssOnebox.format_title(original_title, source, youtube: youtube)
        Thread.current[:rss_onebox_original_title] = original_title
        Thread.current[:rss_onebox_source_name] = published
        Thread.current[:rss_onebox_topic_feed_id] = feed_id
      end

      # For an existing topic, the stored title data is refreshed and the topic renamed silently when the formatted title changed (a new format, display name, source name, or feed title), so core sees matching titles and does not create a revision.
      if protect && embed.post
        ::DiscourseRssOnebox.store_title_data!(embed.post, original_title, Thread.current[:rss_onebox_source_name], feed_id)
        ::DiscourseRssOnebox.rename!(embed.topic, title) if title.present? && embed.topic.title != title
      end

      if protect
        sha1 = Digest::SHA1.hexdigest(rss_onebox_expected_contents(contents, url, cook_method, options))
        embed.update_column(:content_sha1, sha1) if embed.content_sha1 != sha1
      end

      post =
        super(user, url, title, contents, category_id: category_id, cook_method: cook_method, tags: tags, **options)

      if protect && post && !::DiscourseRssOnebox.onebox_body?(post.raw, embed.embed_url)
        ::DiscourseRssOnebox.restore_body!(post, url)
      end

      post
    ensure
      Thread.current[:rss_onebox_original_title] = nil
      Thread.current[:rss_onebox_source_name] = nil
      Thread.current[:rss_onebox_topic_feed_id] = nil
    end

    private

    # Mirrors the contents processing at the top of TopicEmbed.import (truncation, then the "imported from" footer) so the fingerprint matches what core computes. Uses core's own helpers: Discourse 2026.7 truncates whenever embed_truncate is on and cook_method is nil; newer versions take a truncate: argument and keep the full contents when the excerpt would not shorten the text (text_truncated?).
    def rss_onebox_expected_contents(contents, url, cook_method, options)
      processed = contents.to_s
      truncate = options.key?(:truncate) ? options[:truncate] : cook_method.nil?
      if SiteSetting.embed_truncate && truncate
        excerpt = first_paragraph_from(processed)
        if respond_to?(:text_truncated?, true)
          processed = excerpt if text_truncated?(processed, excerpt)
        else
          processed = excerpt || ""
        end
      end
      processed.to_s.dup << imported_from_html(url)
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

      # Stores the item's feed summary or YouTube description on the post, whether or not the display settings are on, so turning them on later needs only a rebake. The feed's original title and source name are stored too, so titles can be re-rendered when a format or source name changes.
      fields = {}
      if (data = ::DiscourseRssOnebox::FeedReader.current_item(args[:embed_url]))
        fields[::DiscourseRssOnebox::SUMMARY_FIELD] = data[:summary] if data[:summary].present?
        fields[::DiscourseRssOnebox::VIDEO_FIELD] = data[:video_description] if data[:video_description].present?
      end
      original = Thread.current[:rss_onebox_original_title]
      source = Thread.current[:rss_onebox_source_name]
      fields[::DiscourseRssOnebox::ORIGINAL_TITLE_FIELD] = original if original.present?
      fields[::DiscourseRssOnebox::SOURCE_FIELD] = source if source.present?
      feed_id = Thread.current[:rss_onebox_topic_feed_id]
      fields[::DiscourseRssOnebox::FEED_ID_FIELD] = feed_id.to_s if feed_id.present?
      args[:custom_fields] = (args[:custom_fields] || {}).merge(fields) if fields.present?
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

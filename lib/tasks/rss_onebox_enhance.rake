# frozen_string_literal: true

# Brings existing RSS-imported topics in rss_onebox_categories up to date. Runs as a dry run unless APPLY=1 is set, and is safe to repeat.
#
# Summaries and descriptions: stores feed summaries and YouTube descriptions for topics that need them (YouTube topics without a stored description, and topics whose onebox has no description, or failed, without a stored summary), then rebakes those topics. Sources are tried in order: the item in the live feed, older pages of the same feed (WordPress's paged parameter), then the article page's first substantial paragraph. REBAKE=1 additionally rebakes every topic that already has stored data, which applies a change to either display setting.
#
# Titles: re-renders each topic's title from its original feed title and source name using the title format settings, renaming silently (no revision, bump, or notification). The source name comes from the feed containing the topic's item, or else from the only configured feed with the same author.
desc "Store feed summaries, YouTube descriptions, and formatted titles for existing RSS-imported topics (dry run unless APPLY=1; REBAKE=1 to re-render all)"
task "rss_onebox:enhance" => :environment do
  category_ids = SiteSetting.rss_onebox_categories_map
  abort "rss_onebox_categories is empty; select at least one category in the plugin settings." if category_ids.empty?

  apply = ENV["APPLY"] == "1"
  rebake_all = ENV["REBAKE"] == "1"
  max_pages = 20
  onebox = DiscourseRssOnebox
  settings_url = "#{Discourse.base_url}/admin/site_settings/category/discourse_rss_onebox?filter=plugin%3Adiscourse-rss-onebox"
  host = ->(url) { URI.parse(url).host.to_s.sub(/\Awww\./, "") rescue "" }

  puts apply ? "APPLY mode: changes will be written." : "Dry run: no changes are made. Set APPLY=1 to apply."
  {
    "rss_onebox_enhanced" => "stored summaries are not displayed",
    "rss_onebox_youtube_descriptions" => "stored YouTube descriptions are not displayed",
  }.each do |setting, effect|
    next if SiteSetting.public_send(setting)
    puts "WARNING: #{setting} is off, so #{effect} until it is turned on and this task is run with REBAKE=1 APPLY=1. Settings: #{settings_url}"
  end

  embeds =
    TopicEmbed
      .joins(:topic)
      .where(topics: { category_id: category_ids })
      .includes(:post, :topic)
      .to_a
      .select(&:post)

  needed = {}
  embeds.each do |embed|
    post = embed.post
    if onebox.youtube_url?(post.raw.strip)
      needed[embed.embed_url] = [embed, :video] if post.custom_fields[onebox::VIDEO_FIELD].blank?
    elsif post.custom_fields[onebox::SUMMARY_FIELD].blank? && onebox::Renderer.needs_summary?(post.cooked)
      needed[embed.embed_url] = [embed, :summary]
    end
  end
  puts "Topics needing data: #{needed.size} of #{embeds.size}."

  found = {}
  record = lambda do |items, source_label|
    items.each do |url, data|
      next unless (entry = needed[url]) && !found.key?(url)
      _, kind = entry
      value = kind == :video ? data[:video_description] : data[:summary]
      found[url] = [value, source_label] if value.present?
    end
  end

  # Every configured feed is read once, for source names; feeds with topics still needing data are paged further.
  feeds = defined?(DiscourseRssPolling::RssFeed) ? DiscourseRssPolling::RssFeed.all.to_a : []
  feed_source = {}
  item_feed = {}
  feeds.each do |feed|
    feed_host = host.(feed.url)
    remaining = -> { needed.keys.count { |u| !found.key?(u) && host.(u) == feed_host } }

    puts "Reading #{feed.url} (#{remaining.()} topics to match)"
    data = onebox::FeedReader.read(feed.url)
    feed_source[feed.id] = data[:source]
    data[:items].each_key { |u| item_feed[u] ||= feed }
    record.(data[:items], "feed")
    puts "  feed: #{data[:items].size} items, source name #{data[:source].inspect}, #{remaining.()} still unmatched"
    seen = data[:items].keys.to_set

    (2..max_pages).each do |page|
      break if remaining.() == 0
      url = onebox::FeedReader.paged_url(feed.url, page)
      page_items = url ? onebox::FeedReader.read(url)[:items] : {}
      break if page_items.empty? || page_items.keys.all? { |k| seen.include?(k) }
      seen.merge(page_items.keys)
      page_items.each_key { |u| item_feed[u] ||= feed }
      record.(page_items, "feed page #{page}")
      puts "  page #{page}: #{page_items.size} items, #{remaining.()} still unmatched"
    end
  end

  article_checks = needed.count { |url, (_, kind)| !found.key?(url) && kind != :video }
  puts "Checking #{article_checks} article pages" if article_checks > 0
  needed.each do |url, (embed, kind)|
    next if found.key?(url) || kind == :video
    text = onebox::FeedReader.page_summary(embed.embed_url)
    found[url] = [text, "article page"] if text.present?
  end

  changed = []
  needed.each do |url, (embed, kind)|
    value, source_label = found[url]
    label = value.present? ? "#{source_label}: #{value.squish[0, 60]}" : "NO SOURCE FOUND"
    puts "topic #{embed.topic_id} | #{kind} | #{label}"
    next if value.blank?
    if apply
      embed.post.custom_fields[kind == :video ? onebox::VIDEO_FIELD : onebox::SUMMARY_FIELD] = value
      embed.post.save_custom_fields(true)
      changed << embed.post
    end
  end

  if rebake_all
    embeds.each do |embed|
      fields = embed.post.custom_fields
      changed << embed.post if fields[onebox::SUMMARY_FIELD].present? || fields[onebox::VIDEO_FIELD].present?
    end
  end

  # Titles. Topics imported before 0.2.3 have no stored original title; their current title is the unformatted feed title.
  feeds_by_author = feeds.group_by { |f| f.user_id || Discourse::SYSTEM_USER_ID }
  renames = 0
  unknown_source = 0
  embeds.each do |embed|
    post = embed.post
    topic = embed.topic
    original = post.custom_fields[onebox::ORIGINAL_TITLE_FIELD].presence || topic.title
    feed = item_feed[embed.embed_url]
    if feed.nil?
      candidates = feeds_by_author[topic.user_id] || []
      feed = candidates.first if candidates.size == 1
    end
    source = (feed && feed_source[feed.id]).presence || post.custom_fields[onebox::SOURCE_FIELD].presence
    youtube = onebox.youtube_url?(post.raw.strip)
    unknown_source += 1 if source.blank? && onebox.format_needs_source?(youtube)
    desired = onebox.format_title(original, source, youtube: youtube)

    if topic.title != desired
      renames += 1
      puts "title | topic #{topic.id} | #{topic.title.truncate(50)} -> #{desired.truncate(70)}"
    end
    if apply
      onebox.store_title_data!(post, original, source)
      onebox.rename!(topic, desired) if topic.title != desired
    end
  end

  changed.uniq(&:id).each(&:rebake!) if apply
  rebaked = rebake_all ? " #{apply ? "Rebaked" : "Would rebake"}: #{changed.uniq(&:id).size}." : ""
  puts "#{apply ? "Stored" : "Would store"}: #{found.size}. Not found: #{needed.size - found.size}.#{rebaked}"
  puts "#{apply ? "Renamed" : "Would rename"}: #{renames} titles.#{unknown_source > 0 ? " Source name unknown (title left unformatted): #{unknown_source}." : ""}"
end

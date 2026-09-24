# frozen_string_literal: true

# Brings existing RSS-imported topics in rss_onebox_categories up to date. Runs as a dry run unless APPLY=1 is set, and is safe to repeat. Prints a short progress line per feed and a summary at the end; VERBOSE=1 adds per-feed detail and a line for every topic that needs data or a new title.
#
# Summaries and descriptions: stores feed summaries and YouTube descriptions for topics that need them (YouTube topics without a stored description, and topics whose onebox has no description, or failed, without a stored summary), then rebakes those topics. Sources are tried in order: the item in the live feed, older pages of the same feed (WordPress's paged parameter), then the article page's first substantial paragraph. REBAKE=1 additionally rebakes every topic that already has stored data, which applies a change to either display setting.
#
# Titles: re-renders each topic's title from its original feed title and source name using the title format settings, renaming silently (no revision, bump, or notification). The topic's feed is the one containing its item, or else the only configured feed with the same author; the source name is that feed's display name (set on the plugin's Display names page), else its published name. The feed's published name and the topic's feed ID are recorded for later re-rendering.
#
# Only feeds enabled in RSS Polling are read.
desc "Store feed summaries, YouTube descriptions, and formatted titles for existing RSS-imported topics (dry run unless APPLY=1; REBAKE=1 to re-render all; VERBOSE=1 for per-topic lines)"
task "rss_onebox:enhance" => :environment do
  category_ids = SiteSetting.rss_onebox_categories_map
  abort "rss_onebox_categories is empty; select at least one category in the plugin settings." if category_ids.empty?

  apply = ENV["APPLY"] == "1"
  rebake_all = ENV["REBAKE"] == "1"
  verbose = ENV["VERBOSE"] == "1"
  max_pages = 20
  onebox = DiscourseRssOnebox
  settings_url = "#{Discourse.base_url}/admin/site_settings/category/discourse_rss_onebox?filter=plugin%3Adiscourse-rss-onebox"
  host = ->(url) { URI.parse(url).host.to_s.sub(/\Awww\./, "") rescue "" }
  detail = ->(line) { puts line if verbose }
  count = ->(n, noun) { "#{n} #{noun.pluralize(n)}" }

  puts apply ? "APPLY mode: changes will be written." : "Dry run: no changes are made. Set APPLY=1 to apply."
  warnings = []
  {
    "rss_onebox_enhanced" => "stored summaries are not displayed",
    "rss_onebox_youtube_descriptions" => "stored YouTube descriptions are not displayed",
  }.each do |setting, effect|
    next if SiteSetting.public_send(setting)
    warnings << "#{setting} is off, so #{effect} until it is turned on and this task is run with REBAKE=1 APPLY=1. Settings: #{settings_url}"
  end
  warnings.each { |w| puts "WARNING: #{w}" }

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

  found = {}
  record = lambda do |items, source_label|
    items.each do |url, data|
      next unless (entry = needed[url]) && !found.key?(url)
      _, kind = entry
      value = kind == :video ? data[:video_description] : data[:summary]
      found[url] = [value, source_label] if value.present?
    end
  end

  # Every enabled feed is read once, for source names; feeds with topics still needing data are paged further. Disabled feeds are only used to match topics to a feed by author.
  all_feeds = defined?(DiscourseRssPolling::RssFeed) ? DiscourseRssPolling::RssFeed.all.to_a : []
  feeds = all_feeds.select(&:enabled)
  feed_source = {}
  item_feed = {}
  unreadable = []
  feeds.each_with_index do |feed, index|
    feed_host = host.(feed.url)
    remaining = -> { needed.keys.count { |u| !found.key?(u) && host.(u) == feed_host } }

    data = onebox::FeedReader.read(feed.url)
    unreadable << feed.url if data[:items].empty? && data[:source].blank?
    feed_source[feed.id] = data[:source]
    onebox.record_published_name(feed.id, data[:source]) if apply
    data[:items].each_key { |u| item_feed[u] ||= feed }
    record.(data[:items], "feed")
    puts "  [#{index + 1}/#{feeds.size}] #{feed_host}: #{count.(data[:items].size, "item")}"
    detail.("      source name #{data[:source].inspect}, #{count.(remaining.(), "topic")} still unmatched")
    seen = data[:items].keys.to_set

    (2..max_pages).each do |page|
      break if remaining.() == 0
      url = onebox::FeedReader.paged_url(feed.url, page)
      page_items = url ? onebox::FeedReader.read(url)[:items] : {}
      break if page_items.empty? || page_items.keys.all? { |k| seen.include?(k) }
      seen.merge(page_items.keys)
      page_items.each_key { |u| item_feed[u] ||= feed }
      record.(page_items, "feed page #{page}")
      detail.("      page #{page}: #{count.(page_items.size, "item")}, #{count.(remaining.(), "topic")} still unmatched")
    end
  end

  article_checks = needed.count { |url, (_, kind)| !found.key?(url) && kind != :video }
  puts "  Checking #{count.(article_checks, "article page")}" if article_checks > 0
  needed.each do |url, (embed, kind)|
    next if found.key?(url) || kind == :video
    text = onebox::FeedReader.page_summary(embed.embed_url)
    found[url] = [text, "article page"] if text.present?
  end

  changed = []
  missing = Hash.new(0)
  needed.each do |url, (embed, kind)|
    value, source_label = found[url]
    detail.("topic #{embed.topic_id} | #{kind} | #{value.present? ? "#{source_label}: #{value.squish[0, 60]}" : "NO SOURCE FOUND"}")
    if value.blank?
      missing[kind] += 1
      next
    end
    next unless apply
    embed.post.custom_fields[kind == :video ? onebox::VIDEO_FIELD : onebox::SUMMARY_FIELD] = value
    embed.post.save_custom_fields(true)
    changed << embed.post
  end

  if rebake_all
    embeds.each do |embed|
      fields = embed.post.custom_fields
      changed << embed.post if fields[onebox::SUMMARY_FIELD].present? || fields[onebox::VIDEO_FIELD].present?
    end
  end

  # Titles. Topics imported before 0.2.3 have no stored original title; their current title is the unformatted feed title.
  feeds_by_author = all_feeds.group_by { |f| f.user_id || Discourse::SYSTEM_USER_ID }
  renames = Hash.new { |h, k| h[k] = { count: 0, example: nil } }
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
    feed_id = feed&.id || post.custom_fields[onebox::FEED_ID_FIELD].presence
    published = (feed && feed_source[feed.id]).presence || post.custom_fields[onebox::SOURCE_FIELD].presence
    source = onebox.resolve_source(feed_id, published)
    youtube = onebox.youtube_url?(post.raw.strip)
    unknown_source += 1 if source.blank? && onebox.format_needs_source?(youtube)
    desired = onebox.format_title(original, source, youtube: youtube)

    if topic.title != desired
      group = renames[source.presence || "(no source)"]
      group[:count] += 1
      group[:example] ||= [topic.title, desired]
      detail.("title | topic #{topic.id} | #{topic.title.truncate(50)} -> #{desired.truncate(70)}")
    end
    if apply
      onebox.store_title_data!(post, original, published, feed_id)
      onebox.rename!(topic, desired) if topic.title != desired
    end
  end

  rebake_count = changed.uniq(&:id).size
  changed.uniq(&:id).each(&:rebake!) if apply
  rename_total = renames.values.sum { |g| g[:count] }
  to_store = needed.size - missing.values.sum

  puts ""
  puts "Summary (#{apply ? "applied" : "dry run"})"
  puts "  Feeds read: #{feeds.size - unreadable.size} of #{feeds.size} enabled.#{unreadable.any? ? " Unreadable: #{unreadable.join(", ")}" : ""}"
  missing_text = missing.map { |kind, n| kind == :video ? "#{count.(n, "YouTube video")} no longer in any feed" : count.(n, "topic") }.join(", ")
  puts "  Summaries and descriptions: #{to_store} #{apply ? "stored" : "to store"}#{missing.any? ? ", no source for #{missing_text}" : ""}"
  puts "  Rebakes: #{rebake_count} #{apply ? "done" : "to do"}" if rebake_count > 0
  puts "  Titles: #{rename_total} #{apply ? "renamed" : "to rename"}#{unknown_source > 0 ? ", #{unknown_source} left unformatted (source name unknown)" : ""}"
  renames.sort_by { |name, g| [-g[:count], name] }.each do |name, g|
    before, after = g[:example]
    puts "    #{name}: #{g[:count]}, e.g. \"#{before.truncate(40)}\" -> \"#{after.truncate(60)}\""
  end
  warnings.each { |w| puts "  Warning: #{w}" }
  if apply
    puts "  Done."
  elsif to_store > 0 || rename_total > 0 || rebake_count > 0
    puts "  Next: re-run with APPLY=1 to write these changes. Add VERBOSE=1 to list every topic."
  else
    puts "  Nothing to change."
  end
end

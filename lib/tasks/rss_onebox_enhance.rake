# frozen_string_literal: true

# Stores feed summaries and YouTube descriptions for topics imported before 0.2.0, then rebakes them so the display settings take effect. Runs as a dry run unless APPLY=1 is set. Only topics that need data are considered: YouTube topics without a stored description, and topics whose onebox has no description (or failed) without a stored summary. Sources are tried in order: the item in the live feed, older pages of the same feed (WordPress's paged parameter), then the article page's first substantial paragraph. REBAKE=1 additionally rebakes every topic that already has stored data, which applies a change to either display setting. Like the convert task, the rewrite is silent.
desc "Store feed summaries and YouTube descriptions for existing RSS-imported topics (dry run unless APPLY=1; REBAKE=1 to re-render all)"
task "rss_onebox:enhance" => :environment do
  category_ids = SiteSetting.rss_onebox_categories_map
  abort "rss_onebox_categories is empty; select at least one category in the plugin settings." if category_ids.empty?

  apply = ENV["APPLY"] == "1"
  rebake_all = ENV["REBAKE"] == "1"
  max_pages = 20
  summary_field = DiscourseRssOnebox::SUMMARY_FIELD
  video_field = DiscourseRssOnebox::VIDEO_FIELD
  host = ->(url) { URI.parse(url).host.to_s.sub(/\Awww\./, "") rescue "" }

  puts apply ? "APPLY mode: data will be stored and posts rebaked." : "Dry run: no changes are made. Set APPLY=1 to apply."

  embeds =
    TopicEmbed
      .joins(:topic)
      .where(topics: { category_id: category_ids })
      .includes(:post)
      .to_a
      .select(&:post)

  needed = {}
  embeds.each do |embed|
    post = embed.post
    youtube = post.raw.strip.match?(%r{\Ahttps?://(www\.)?youtube\.com/watch}i)
    if youtube
      needed[embed.embed_url] = [embed, :video] if post.custom_fields[video_field].blank?
    elsif post.custom_fields[summary_field].blank? && DiscourseRssOnebox::Renderer.needs_summary?(post.cooked)
      needed[embed.embed_url] = [embed, :summary]
    end
  end
  puts "Topics needing data: #{needed.size} of #{embeds.size}."

  found = {}
  record = lambda do |items, source|
    items.each do |url, data|
      next unless (entry = needed[url]) && !found.key?(url)
      _, kind = entry
      value = kind == :video ? data[:video_description] : data[:summary]
      found[url] = [value, source] if value.present?
    end
  end

  feeds = defined?(DiscourseRssPolling::RssFeed) ? DiscourseRssPolling::RssFeed.all.to_a : []
  feeds.each do |feed|
    feed_host = host.(feed.url)
    remaining = -> { needed.keys.count { |u| !found.key?(u) && host.(u) == feed_host } }
    next if remaining.() == 0

    items = DiscourseRssOnebox::FeedReader.read(feed.url)
    record.(items, "feed")
    seen = items.keys.to_set

    (2..max_pages).each do |page|
      break if remaining.() == 0
      url = DiscourseRssOnebox::FeedReader.paged_url(feed.url, page)
      page_items = url ? DiscourseRssOnebox::FeedReader.read(url) : {}
      break if page_items.empty? || page_items.keys.all? { |k| seen.include?(k) }
      seen.merge(page_items.keys)
      record.(page_items, "feed page #{page}")
    end
  end

  needed.each do |url, (embed, kind)|
    next if found.key?(url) || kind == :video
    text = DiscourseRssOnebox::FeedReader.page_summary(embed.embed_url)
    found[url] = [text, "article page"] if text.present?
  end

  changed = []
  needed.each do |url, (embed, kind)|
    value, source = found[url]
    label = value.present? ? "#{source}: #{value.squish[0, 60]}" : "NO SOURCE FOUND"
    puts "topic #{embed.topic_id} | #{kind} | #{label}"
    next if value.blank?
    if apply
      field = kind == :video ? video_field : summary_field
      embed.post.custom_fields[field] = value
      embed.post.save_custom_fields(true)
      changed << embed.post
    end
  end

  if rebake_all
    embeds.each do |embed|
      fields = embed.post.custom_fields
      changed << embed.post if fields[summary_field].present? || fields[video_field].present?
    end
  end

  changed.uniq(&:id).each(&:rebake!) if apply
  puts "#{apply ? "Stored" : "Would store"}: #{found.size}. Not found: #{needed.size - found.size}.#{rebake_all ? " #{apply ? "Rebaked" : "Would rebake"}: #{changed.uniq(&:id).size}." : ""}"
end

# frozen_string_literal: true

# Converts topics imported before the plugin was installed, repairs topics converted by 0.1.0 or 0.1.1 with a lowercased URL, and restores topics whose body core replaced with feed content before 0.1.3. Runs as a dry run unless APPLY=1 is set. The rewrite is silent: raw and cook_method are written with update_columns, so no revision, bump, or notification is created and topic dates are unchanged. Posts already holding their target URL with Markdown cooking are skipped, so repeated runs are safe.
desc "Convert RSS-imported topics in rss_onebox_categories to a onebox of the article URL (dry run unless APPLY=1)"
task "rss_onebox:convert" => :environment do
  category_ids = SiteSetting.rss_onebox_categories_map
  abort "rss_onebox_categories is empty; select at least one category in the plugin settings." if category_ids.empty?

  apply = ENV["APPLY"] == "1"
  regular = Post.cook_methods[:regular]
  converted = 0
  skipped = 0

  puts apply ? "APPLY mode: posts will be rewritten and rebaked." : "Dry run: no changes are made. Set APPLY=1 to apply."

  # joins(:topic) applies Topic's default scope, so trashed topics and trashed embeds are excluded.
  TopicEmbed
    .joins(:topic)
    .where(topics: { category_id: category_ids })
    .includes(:post, topic: :user)
    .find_each do |embed|
      post = embed.post

      if post.nil?
        skipped += 1
        next
      end

      # embed_url is stored lowercased. For items whose feed content is the URL itself (RSS Polling's YouTube handling), embed_content_cache holds the original-case URL, so it is used when it normalises to embed_url.
      cache = embed.embed_content_cache.to_s.strip
      target =
        if cache.match?(%r{\Ahttps?://\S+\z}) && TopicEmbed.normalize_url(cache) == embed.embed_url
          cache
        else
          embed.embed_url
        end

      # A bare URL that normalises to embed_url is correct, including original-case URLs and trailing slashes.
      if post.cook_method == regular && (post.raw.strip == target || ::DiscourseRssOnebox.onebox_body?(post.raw, embed.embed_url))
        skipped += 1
        next
      end

      puts "topic #{embed.topic_id} | #{embed.topic.user&.username} | #{target}"

      if apply
        post.update_columns(raw: target, cook_method: regular)
        # rebake! cooks the new raw and enqueues post processing with bypass_bump, which fetches the onebox.
        post.rebake!
      end

      converted += 1
    end

  puts "#{apply ? "Converted" : "Would convert"}: #{converted}. Skipped (already correct or no post): #{skipped}."
end

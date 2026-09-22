# frozen_string_literal: true

# Converts topics imported before the plugin was installed. Runs as a dry run unless APPLY=1 is set. The rewrite is silent: raw and cook_method are written with update_columns, so no revision, bump, or notification is created and topic dates are unchanged. Posts already holding the bare URL with Markdown cooking are skipped, so repeated runs are safe.
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

      if post.nil? || (post.raw.strip == embed.embed_url && post.cook_method == regular)
        skipped += 1
        next
      end

      puts "topic #{embed.topic_id} | #{embed.topic.user&.username} | #{embed.embed_url}"

      if apply
        post.update_columns(raw: embed.embed_url, cook_method: regular)
        # rebake! cooks the new raw and enqueues post processing with bypass_bump, which fetches the onebox.
        post.rebake!
      end

      converted += 1
    end

  puts "#{apply ? "Converted" : "Would convert"}: #{converted}. Skipped (already converted or no post): #{skipped}."
end

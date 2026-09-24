# frozen_string_literal: true

module Jobs
  # Reads every enabled RSS Polling feed once and records its published name. A feed that cannot be read keeps its previous name and is marked with a fetch error. When a feed's published name changed and it has no display name, its topic titles are re-rendered.
  class RssOneboxRefreshNames < ::Jobs::Base
    def execute(_args)
      return unless defined?(::DiscourseRssPolling::RssFeed)
      plugin = ::DiscourseRssOnebox::PLUGIN_NAME

      ::DiscourseRssPolling::RssFeed.where(enabled: true).find_each do |feed|
        source = ::DiscourseRssOnebox::FeedReader.read(feed.url)[:source]
        if source.present?
          PluginStore.remove(plugin, "fetch_error:#{feed.id}")
          changed = ::DiscourseRssOnebox.record_published_name(feed.id, source)
          if changed && ::DiscourseRssOnebox.display_name(feed.id).blank?
            Jobs.enqueue(:rss_onebox_rerender_titles, feed_id: feed.id)
          end
        else
          PluginStore.set(plugin, "fetch_error:#{feed.id}", Time.zone.now.to_i)
        end
      end
    ensure
      PluginStore.remove(::DiscourseRssOnebox::PLUGIN_NAME, "refresh_started_at")
    end
  end
end

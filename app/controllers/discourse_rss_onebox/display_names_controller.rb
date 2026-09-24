# frozen_string_literal: true

module ::DiscourseRssOnebox
  class DisplayNamesController < ::Admin::AdminController
    requires_plugin PLUGIN_NAME

    REFRESH_TIMEOUT = 15.minutes

    def index
      render json: { feeds: feeds.map { |feed| serialize(feed) }, refresh_running: refresh_running? }
    end

    def update
      feed = rss_feed_class&.find_by(id: params[:feed_id]) || raise(Discourse::NotFound)
      name = params[:display_name].to_s.squish
      key = "display_name:#{feed.id}"
      name.present? ? PluginStore.set(PLUGIN_NAME, key, name) : PluginStore.remove(PLUGIN_NAME, key)
      Jobs.enqueue(:rss_onebox_rerender_titles, feed_id: feed.id)
      render json: { feed: serialize(feed) }
    end

    def refresh
      unless refresh_running?
        PluginStore.set(PLUGIN_NAME, "refresh_started_at", Time.zone.now.to_i)
        Jobs.enqueue(:rss_onebox_refresh_names)
      end
      render json: { refresh_running: true }
    end

    private

    def rss_feed_class
      defined?(::DiscourseRssPolling::RssFeed) ? ::DiscourseRssPolling::RssFeed : nil
    end

    def feeds
      rss_feed_class ? rss_feed_class.includes(:user).order(:url).to_a : []
    end

    # A refresh counts as running for at most REFRESH_TIMEOUT, so a job that died without clearing its marker does not block the button permanently.
    def refresh_running?
      started = PluginStore.get(PLUGIN_NAME, "refresh_started_at").to_i
      started > 0 && Time.zone.now.to_i - started < REFRESH_TIMEOUT.to_i
    end

    def serialize(feed)
      {
        id: feed.id,
        url: feed.url,
        enabled: feed.enabled,
        author: feed.user&.username || Discourse.system_user.username,
        published_name: ::DiscourseRssOnebox.published_name(feed.id),
        display_name: ::DiscourseRssOnebox.display_name(feed.id),
        fetch_error: PluginStore.get(PLUGIN_NAME, "fetch_error:#{feed.id}").present?,
      }
    end
  end
end

# frozen_string_literal: true

module Jobs
  # Re-renders the titles of every topic imported from one feed, after its display name or published name changed. Renaming is silent.
  class RssOneboxRerenderTitles < ::Jobs::Base
    def execute(args)
      feed_id = args[:feed_id].to_s
      return if feed_id.blank?

      post_ids =
        PostCustomField.where(name: ::DiscourseRssOnebox::FEED_ID_FIELD, value: feed_id).pluck(:post_id)
      Post.where(id: post_ids).includes(:topic).find_each do |post|
        next unless post.topic && ::DiscourseRssOnebox.configured?(post.topic.category_id)
        ::DiscourseRssOnebox.rerender_title!(post)
      end
    end
  end
end

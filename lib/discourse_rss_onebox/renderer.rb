# frozen_string_literal: true

module ::DiscourseRssOnebox
  SUMMARY_FIELD = "rss_onebox_summary"
  VIDEO_FIELD = "rss_onebox_video_description"

  # Adds stored feed data to a post's rendered HTML during core's post processing, after oneboxes are built and before the HTML is saved. The post's raw body is never changed.
  module Renderer
    URL_PATTERN = %r{https?://[^\s<>"]+}

    def self.apply(doc, post)
      return unless post.is_first_post?
      topic = post.topic
      return unless topic && ::DiscourseRssOnebox.configured?(topic.category_id)
      return unless topic.topic_embed

      video = post.custom_fields[VIDEO_FIELD]
      summary = post.custom_fields[SUMMARY_FIELD]
      player = doc.at_css(".lazy-video-container")

      if player
        if SiteSetting.rss_onebox_youtube_descriptions && video.present?
          player.add_next_sibling(video_html(video))
        end
        return
      end

      return unless SiteSetting.rss_onebox_enhanced && summary.present?

      if (box = doc.at_css("aside.onebox article.onebox-body"))
        return if box.css("> p").any? { |p| p.text.strip.present? }
        paragraph = "<p>#{ERB::Util.html_escape(summary)}</p>"
        (h3 = box.at_css("h3")) ? h3.add_next_sibling(paragraph) : box.add_child(paragraph)
      elsif !doc.at_css("aside.onebox")
        doc.add_child(%(<p class="rss-onebox-summary">#{ERB::Util.html_escape(summary)}</p>))
      end
    end

    # The full description: blank lines separate paragraphs, single newlines become line breaks, and URLs become links.
    def self.video_html(text)
      paragraphs =
        text
          .strip
          .split(/\n\s*\n/)
          .map { |block| "<p>#{block.strip.split("\n").map { |line| linkify(line) }.join("<br>")}</p>" }
      %(<div class="rss-onebox-description">#{paragraphs.join}</div>)
    end

    def self.linkify(line)
      out = +""
      last = 0
      line.to_enum(:scan, URL_PATTERN).each do
        m = Regexp.last_match
        out << ERB::Util.html_escape(line[last...m.begin(0)])
        url = ERB::Util.html_escape(m[0])
        out << %(<a href="#{url}" rel="nofollow ugc noopener" target="_blank">#{url}</a>)
        last = m.end(0)
      end
      out << ERB::Util.html_escape(line[last..])
    end

    # True when the rendered first post would benefit from a stored summary: a onebox without a description, or a bare link where the onebox failed.
    def self.needs_summary?(cooked)
      doc = Nokogiri::HTML5.fragment(cooked.to_s)
      return false if doc.at_css(".lazy-video-container")
      box = doc.at_css("aside.onebox article.onebox-body")
      return box.css("> p").none? { |p| p.text.strip.present? } if box
      !doc.at_css("aside.onebox")
    end
  end
end

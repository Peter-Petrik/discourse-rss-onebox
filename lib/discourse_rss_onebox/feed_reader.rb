# frozen_string_literal: true

module ::DiscourseRssOnebox
  # Reads a feed's XML directly, because RSS Polling's parser drops media:description and plain-text summaries. read and parse_feed return { items:, source: }: items is a hash keyed by normalised item URL (the same normalisation as TopicEmbed.embed_url) with :summary and :video_description; source is the feed's own published name.
  module FeedReader
    SUMMARY_MIN_CHARS = 80
    SUMMARY_MAX_CHARS = 300
    MAX_BYTES = 10 * 1024 * 1024

    # Downloads a URL with core's FinalDestination, the same client RSS Polling uses for feeds. FinalDestination also calls the block for redirect responses (with no data and a blank URI) before following the redirect, so those calls are skipped, as RSS Polling's own fetch does. Returns the body, or nil when nothing was received or an error occurred.
    def self.fetch(url)
      body = +""
      fd = FinalDestination.new(url, timeout: SiteSetting.rss_polling_feed_request_timeout)
      fd.get do |response, chunk, uri|
        throw :done if uri.blank? || !response.is_a?(Net::HTTPSuccess) || chunk.nil?
        body << chunk
        throw :done if body.bytesize > MAX_BYTES
      end
      body.empty? ? nil : body
    rescue StandardError
      nil
    end

    def self.read(url)
      xml = fetch(url)
      xml ? parse_feed(xml) : { items: {}, source: nil }
    end

    def self.parse(xml)
      parse_feed(xml)[:items]
    end

    def self.parse_feed(xml)
      doc = Nokogiri.XML(xml)
      doc.remove_namespaces!
      items = {}
      source = clean_source(doc.at_xpath("/rss/channel/title")&.text || doc.at_xpath("/feed/title")&.text)

      doc.xpath("//item").each do |item|
        link = item.at_xpath("./link")&.text.to_s.strip
        next if link.blank?
        summary = summary_from(item.at_xpath("./description")&.text, item.at_xpath("./encoded")&.text)
        items[TopicEmbed.normalize_url(link)] = { summary: summary } if summary.present?
      end

      doc.xpath("//entry").each do |entry|
        link = entry.at_xpath("./link[@rel='alternate']/@href")&.value || entry.at_xpath("./link/@href")&.value
        next if link.blank?
        video = entry.at_xpath("./group/description")&.text.to_s.strip
        items[TopicEmbed.normalize_url(link)] = { video_description: video } if video.present?
      end

      { items: items, source: source }
    rescue StandardError
      { items: {}, source: nil }
    end

    # The feed's published name, with whitespace collapsed and trailing punctuation removed.
    def self.clean_source(name)
      name.to_s.squish.sub(/[\s.,;:!?]+\z/, "").presence
    end

    # The feed's <description> when it holds at least SUMMARY_MIN_CHARS of text; otherwise the opening paragraphs of the full body, accumulated until SUMMARY_MIN_CHARS.
    def self.summary_from(description, body)
      text = text_of(description)
      return truncate(text) if text.length >= SUMMARY_MIN_CHARS

      opening = opening_paragraphs(body)
      opening.present? ? truncate(opening) : (text.presence && truncate(text))
    end

    def self.opening_paragraphs(html)
      return "" if html.blank?
      result = +""
      Nokogiri::HTML5.fragment(html).css("p").each do |p|
        t = plain_text(p)
        next if t.blank?
        result << " " if result.present?
        result << t
        break if result.length >= SUMMARY_MIN_CHARS
      end
      result
    end

    def self.text_of(html)
      html.blank? ? "" : plain_text(Nokogiri::HTML5.fragment(html))
    end

    # Text of an HTML node with each line break (<br>) turned into a " · " separator, so fields that are separated only by line breaks do not run together. Repeated, leading, and trailing separators are removed.
    def self.plain_text(node)
      node = node.dup
      node.css("br").each { |br| br.replace(" · ") }
      node.text.squish.gsub(/(?:\s*·\s*){2,}/, " · ").sub(/\A[\s·]+/, "").sub(/[\s·]+\z/, "")
    end

    def self.truncate(text)
      return text if text.length <= SUMMARY_MAX_CHARS
      cut = text[0, SUMMARY_MAX_CHARS]
      cut = cut[0, cut.rindex(" ")] if cut.rindex(" ").to_i > SUMMARY_MAX_CHARS / 2
      "#{cut.rstrip}…"
    end

    # The feed URL with WordPress's paged query parameter, for reading older items.
    def self.paged_url(url, page)
      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query.to_s).reject { |k, _| k == "paged" } << ["paged", page.to_s]
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::Error
      nil
    end

    # The first paragraph of the article page's main content with at least SUMMARY_MIN_CHARS of text. Used only by the historical rake task, as a last resort.
    def self.page_summary(url)
      html = fetch(url)
      return nil if html.blank?
      doc = Nokogiri::HTML5(html)
      scope = doc.at_css("article") || doc.at_css("main") || doc.at_css("body")
      para = scope&.css("p")&.map { |p| plain_text(p) }&.find { |t| t.length >= SUMMARY_MIN_CHARS }
      para && truncate(para)
    rescue StandardError
      nil
    end

    # Feed data for the poll currently running in this thread, read once per poll on first use.
    # The feed's published name is recorded against its RSS Polling feed ID whenever the feed is read during a poll.
    def self.current_feed
      feed_url = Thread.current[:rss_onebox_feed_url]
      return nil if feed_url.blank?
      Thread.current[:rss_onebox_feed_data] ||=
        read(feed_url).tap do |data|
          ::DiscourseRssOnebox.record_published_name(Thread.current[:rss_onebox_feed_id], data[:source])
        end
    end

    def self.current_item(embed_url)
      current_feed&.dig(:items, embed_url)
    end

    def self.current_source
      current_feed&.dig(:source)
    end
  end
end

# Discourse RSS Polling Onebox

This plugin changes how topics imported by Discourse's bundled [RSS Polling](https://meta.discourse.org/t/rss-polling/156387) plugin are displayed. In the categories it is configured for, each imported topic's first post becomes the bare article URL, which Discourse renders as a onebox: the article title, featured image (`og:image`) and description (`og:description`) taken from the article page itself. The "Show Full Post" button is hidden in those categories. It is intended for forums that use RSS Polling to aggregate members' blogs into a category, where the stock import (the first paragraph of the feed body, with no image) reads poorly.

## Project Status

Early release, in use on a single production forum running Discourse 2026.7 ESR. See [Issues](https://github.com/Peter-Petrik/discourse-rss-onebox/issues) for known problems and planned work.

## Features

- **Onebox Rendering of New Imports**: RSS Polling imports into the configured categories are created with the article URL as the post body and Markdown cooking, so Discourse's standard onebox builds the preview. Imports into other categories are unchanged.
- **Scoped "Show Full Post" Suppression**: The button, which re-scrapes the article page and is redundant once the post is a onebox, is hidden only for topics in the configured categories. Everywhere else, core behaviour applies.
- **Bulk Conversion of Existing Topics**: A rake task converts topics imported before the plugin was installed. It defaults to a dry run, is safe to repeat, and rewrites posts silently: no revision history, no bump, no notifications, and topic dates are unchanged.
- **Feed Summaries (optional)**: When an article's own page provides no description, the preview shows the summary from the feed, or the article's opening paragraph if the feed has none. The summary appears inside the link preview, where the page's own description would be, or below the link when no preview can be built.
- **YouTube Descriptions (optional)**: The full video description from the YouTube feed is shown below the player, with line breaks preserved and links clickable.
- **Title Formats (optional)**: Separate formats for blog and YouTube topics, combining the post's title with fixed text and the blog's or channel's name, for example `Video: %{title}` or `%{source}: %{title}`. Existing topics are renamed silently.
- **Display Names Page**: An admin page listing every RSS Polling feed with its published name and an optional display name to use in titles instead, with a button to refresh published names from the feeds.
- **Protection Against Feed Updates**: Edits to a blog post or changes to a feed's format do not overwrite oneboxed topics.
- **No Theme Component Required**: All behaviour is server-side, apart from a small stylesheet for spacing.

## Configuration

Settings are under **Admin → Installed plugins → RSS Polling Onebox → Settings**.

| Setting | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `rss_onebox_enabled` | boolean | `false` | Enables the plugin. When disabled, imports and "Show Full Post" follow core behaviour. |
| `rss_onebox_categories` | category list | empty | Categories whose RSS-imported topics are rendered as a onebox. With no categories selected, the plugin has no effect. |
| `rss_onebox_enhanced` | boolean | `false` | Shows the feed summary when an article's page provides no description. |
| `rss_onebox_youtube_descriptions` | boolean | `false` | Shows the full YouTube video description below the player. |
| `rss_onebox_blog_title_format` | text | empty | Title format for topics from blog feeds (every feed that is not YouTube). Empty leaves titles unchanged. |
| `rss_onebox_youtube_title_format` | text | empty | Title format for topics from YouTube channel feeds. Empty leaves titles unchanged. |

Display names for `%{source}` are set on the plugin's **Display names** page (**Admin → Installed plugins → RSS Polling Onebox → Display names**, at `/admin/plugins/discourse-rss-onebox/display-names`), not in the settings above.

Summaries and descriptions are stored for every new import regardless of the two display settings. A change to either setting applies to new topics immediately and to existing topics after `rake rss_onebox:enhance REBAKE=1 APPLY=1`.

## Prerequisites

- **Discourse**: Developed and tested on 2026.7.3 (ESR). The plugin relies on the `topic_embed_import_create_args` modifier in core's `TopicEmbed.import` and on the RSS Polling plugin bundled with core since July 2025.
- **RSS Polling**: Enabled, with at least one feed importing into a category.
- **Article metadata**: Onebox quality depends on each source site publishing Open Graph tags. Sites without `og:image` produce a onebox without an image.

## Quick Start

1. Add the plugin to the `hooks: after_code:` section of `containers/app.yml`, alongside the other plugin clones:

   ```yaml
             - git clone https://github.com/Peter-Petrik/discourse-rss-onebox.git
   ```

2. Rebuild the container:

   ```bash
   cd /var/discourse
   ./launcher rebuild app
   ```

3. In **Admin → Installed plugins**, enable **RSS Polling Onebox**, open its **Settings**, and select the categories that RSS Polling imports into.
4. Convert any topics imported before installation (see Converting Existing Topics below).

New imports into the selected categories are converted automatically from this point on.

## Technical Details

### How It Works

RSS Polling imports each feed item through core's `TopicEmbed.import`, which passes its topic-creation arguments through the `topic_embed_import_create_args` modifier. For imports into a configured category, the plugin replaces the post body with the item's URL and sets the cook method to Markdown. Core lowercases the URL it stores for the embed (`TopicEmbed.normalize_url`), which would break case-sensitive URLs such as YouTube video IDs, so the plugin takes the original-case URL from the "imported from" footer that core appends to the body before normalising, and falls back to the stored URL if the two do not match. The Markdown setting is required: imports are otherwise stored as raw HTML unless `embed_support_markdown` is enabled, and raw HTML is never oneboxed.

"Show Full Post" is driven by the `expandable_first_post` attribute of the topic serializer. The plugin omits that attribute for topics in the configured categories and preserves core's condition everywhere else.

### Feed Summaries and YouTube Descriptions

RSS Polling's parser drops `media:description` and plain-text summaries, so the plugin reads the feed's XML itself. It wraps RSS Polling's poll job to learn which feed is being polled, reads that feed once on the first new item of the poll (polls with no new items fetch nothing extra), and stores each new item's summary or video description on the post as a custom field. The summary is the item's `<description>` when it holds at least 80 characters of text, otherwise the opening paragraphs of the item's full body, and is capped at about 300 characters. Line breaks inside a paragraph become a ` · ` separator, so fields separated only by line breaks (for example a log entry's distance, duration, and crew) do not run together.

The stored text is added to the rendered post during core's post processing (the `post_process_cooked` event), after the onebox is built and before the rendered HTML is saved. A summary is added only when the rendered onebox has no description of its own, so sites that publish a description are unaffected. The post's raw body remains the bare URL.

### Title Formats

A format is plain text containing `%{title}` (the post's or video's title as published in the feed) and optionally `%{source}` (the blog's or channel's name: the feed's display name if one is set on the Display names page, otherwise the feed's own published title with trailing punctuation removed). If a format uses `%{source}` and no source name is known, the title is left unchanged. The result is cut to Discourse's `max_topic_title_length`.

The feed's original title, published source name, and RSS Polling feed ID are stored on each topic, and the displayed title is always built from them, so changing a format never produces doubled prefixes. The plugin's wrapper around `TopicEmbed.import` applies the format on creation and on every poll, renaming silently (no revision, bump, or notification) when the result differs, for example after a format change or when the feed's name or an item's title changes. Core therefore always sees matching titles and never creates a title revision.

### Display Names Page

The page lists every RSS Polling feed, in the same table layout as RSS Polling's own feed list, with its author, its published name as last read, and a display name field. A blank display name uses the published name, shown as the field's placeholder. Feeds that are disabled in RSS Polling are dimmed, as on RSS Polling's page, and their display name can still be edited.

Display names and published names are stored per RSS Polling feed ID in core's plugin store, so a display name survives changes to the feed's published name or URL. Saving a display name re-renders the titles of that feed's topics in a background job, silently.

Published names are recorded whenever a feed is read: during polls that import an item, by the enhance task, and by the **Refresh published names** button. The button reads every enabled feed in a background job; the page shows that it is running and updates when it finishes. A feed that cannot be read keeps its previous name and is marked on the page. When a feed's published name changes and it has no display name, its topic titles are re-rendered silently.

### Enhancing Existing Topics

`rss_onebox:enhance` brings existing topics up to date: it stores summaries and video descriptions for topics imported before 0.2.0, and re-renders every topic's title from the title format settings.

For summaries and descriptions, It considers only topics that need data: YouTube topics without a stored description, and topics whose onebox has no description (or failed) without a stored summary. For each, it tries in order: the item in the live feed, older pages of the same feed (`?paged=2`, `?paged=3`, and so on, which WordPress supports; it stops at the first page that fails, is empty, or repeats), and finally the first paragraph of at least 80 characters in the article page's main content. Topics with no source found are reported.

For titles, the topic's feed is the one that contains its item or, for items no longer in any feed, the only configured feed with the same author as the topic; the source name is that feed's display name, else its published name. The task also records each feed's published name and each topic's feed ID, which the Display names page and later re-renders use. Topics whose source name cannot be determined keep an unformatted title and are counted in the summary line. Renaming is silent, as on polls.

The task prints a progress line per feed and per older feed page, a line per topic that needs data, and a line per title it would change. It warns, with a link to the plugin's settings, when either display setting is off, because stored summaries and descriptions are not displayed until the setting is on.

```bash
cd /var/discourse
./launcher enter app
rake rss_onebox:enhance
APPLY=1 rake rss_onebox:enhance
exit
```

`REBAKE=1` additionally rebakes every topic that already has stored data, which applies a change to either display setting.

### Converting Existing Topics

The rake task covers every topic in the configured categories that has an embed record, regardless of which feed imported it. For items whose feed content is the URL itself (RSS Polling's YouTube handling), the task restores the original-case URL from the stored embed content, so it also repairs video topics converted by versions before 0.1.2. Run it inside the container:

```bash
cd /var/discourse
./launcher enter app
rake rss_onebox:convert
APPLY=1 rake rss_onebox:convert
exit
```

The first run is a dry run that lists each topic ID, author and article URL, then reports how many topics would be converted. `APPLY=1` performs the conversion and rebakes each post; the onebox preview is fetched by a background job, so a topic may briefly show a bare link. Posts already converted are skipped, so the task can be re-run at any time; it also restores any topic whose body core replaced with feed content before 0.1.3.

### Known Limitations

- **Feed content updates are ignored**: For topics already imported into a configured category, changes to a feed item's content (for example an edited blog post, or a change to the feed format) no longer rewrite the post. Title, tag, and author changes still apply; because core rewrites the body together with a title or tag change, the plugin restores the onebox body silently afterwards, and that edit remains in the post's revision history. The plugin wraps core's `TopicEmbed.import` to achieve this, so it depends on that method's signature and its content processing, verified against Discourse 2026.7.3.
- **Lowercase URLs from versions before 0.1.2**: Versions 0.1.0 and 0.1.1 wrote the lowercased embed URL into the post body. Re-running `rss_onebox:convert` repairs video topics; for other topics the original-case URL is no longer stored, so their URLs stay lowercase, which resolves correctly on sites with lowercase slugs.
- **Manual title edits**: A topic's title is rebuilt from the feed on every poll while its item is in the feed, so a title edited by hand in Discourse is replaced. Core behaves the same way without the plugin.
- **Source names for older items**: For items no longer in any feed, the source name is found through the topic's author, which works only when that author has exactly one configured feed.
- **Historical coverage**: Older items are recovered only where a source still exists. YouTube channel feeds hold the latest 15 videos and do not page, so older videos may get no description; non-WordPress feeds may not page; the article-page fallback is a heuristic that depends on the page layout.
- **Dependence on RSS Polling internals**: Reading feed data depends on RSS Polling's poll job class and its `feed_url` and `rss_feed_id` arguments, and the Display names page reads RSS Polling's feed table, all verified against Discourse 2026.7.3.
- **Site-wide scope of the modifier**: The modifier applies to every `TopicEmbed.import` call targeting a configured category, including embeds created by other means than RSS Polling. Configured categories are expected to be dedicated to RSS imports.

## Future Enhancements

- **Upstream Extension Points**: Replace the wrappers around core's `TopicEmbed.import` and RSS Polling's poll job with documented hooks, if RSS Polling gains them.

## Support

For bug reports and feature requests, open an issue at [GitHub Issues](https://github.com/Peter-Petrik/discourse-rss-onebox/issues). Include the Discourse version, plugin version, and the output of `rake rss_onebox:convert` if relevant.

## License

Copyright 2026 Peter Petrik. Licensed under the [MIT License](LICENSE).

# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions 0.2.3 and 0.2.4 added features in patch releases; later feature releases increment the minor version.

## [Unreleased]

## [0.2.6] - 2026-09-25

### Fixed
- **Display Names Page on Phones**: On narrow screens, core's admin table positions cells of the controls type absolutely at the top right of each row, which suits a small action button but placed the display-name field and Save button over the feed URL and author. The field now uses the detail cell type, which stays in the normal flow as its own line, and the published name and display name lines carry core's mobile labels, since the column headers are hidden on phones. The field's flex layout moved from the table cell to a wrapper inside it, so the cell also keeps normal table layout on desktop.

## [0.2.5] - 2026-09-24

### Added
- **Enhance Task Summary**: `rss_onebox:enhance` ends with a summary listing the feeds read and any that could not be read, the summaries and descriptions to store and any without a source, rebakes, and the titles to rename grouped by source name with one example rename each. Per-topic lines now appear only with `VERBOSE=1`, so a routine run no longer prints a line for every topic.

### Changed
- **Title Format Defaults**: Both title format settings default to `%{title}` instead of an empty value. The result is the same (titles are unchanged), but the setting field now shows the placeholder syntax. An empty value continues to leave titles unchanged.
- **Enabled Feeds Only**: The enhance task reads only feeds that are enabled in RSS Polling, matching the Refresh published names button. Disabled feeds are still used to match older topics to a feed by author.

### Fixed
- **Forward Compatibility with `TopicEmbed.import`**: Newer Discourse versions add a `truncate:` keyword argument to `TopicEmbed.import`, which the import wrapper did not accept; after upgrading, every RSS Polling import would have failed with an unknown-keyword error. The wrapper now passes through keyword arguments it does not use, and its content fingerprint follows core's own truncation helpers on both the old and new versions.

## [0.2.4] - 2026-09-24

### Added
- **Display Names Page**: A Display names tab on the plugin's admin page lists every RSS Polling feed with its author, its published name, and an editable display name used for `%{source}` in title formats. Display names are stored per RSS Polling feed ID, so they survive changes to a feed's published name or URL. Saving a display name re-renders that feed's topic titles silently in a background job. Feeds disabled in RSS Polling are dimmed, as on RSS Polling's own feed list.
- **Refresh Published Names**: A button on the Display names tab reads every enabled feed in a background job and records its published name. Feeds that cannot be read keep their previous name and are marked on the page. When a feed without a display name changes its published name, its topic titles are re-rendered silently.

### Changed
- **Source Name Resolution**: `%{source}` now resolves to the feed's display name, falling back to its published name. Each topic records its RSS Polling feed ID, captured during polls and by the enhance task, so titles can be re-rendered per feed.

## [0.2.3] - 2026-09-24

### Added
- **Title Formats**: Two settings, one for blog feeds and one for YouTube feeds, format topic titles with the placeholders `%{title}` and `%{source}` (the feed's published name). Formats are applied on creation and on every poll, and a changed result renames the topic silently, without a revision, bump, or notification. Each topic stores its original feed title and source name, so changing a format never produces doubled prefixes. The enhance task re-renders the titles of existing topics.
- **Settings-Off Warnings**: The enhance task warns, with a link to the plugin's settings, when either display setting is off, because stored summaries and descriptions are not displayed until the setting is on.

## [0.2.2] - 2026-09-24

### Fixed
- **Run-Together Summary Fields**: Text extraction dropped line breaks (`<br>`) without inserting a space, so fields separated only by line breaks ran together, for example "(24.845)DURATA". Line breaks are now converted to a ` · ` separator in every extraction path: the feed description, the body paragraphs, and the article-page fallback.

## [0.2.1] - 2026-09-24

### Added
- **Enhance Task Progress Output**: The enhance task prints a progress line per feed, per older feed page, and before checking article pages, instead of running silently until its results.

### Fixed
- **Redirected Feeds and Article Pages**: Core's `FinalDestination` invokes the download block for a redirect response before following the redirect. The plugin's fetch treated that first call as a failure, so every URL that redirects returned nothing, including WordPress feed URLs without a trailing slash and article URLs as stored by core. As a result, the enhance task found no blog sources at all. Redirect calls are now skipped, as RSS Polling's own fetch does.

## [0.2.0] - 2026-09-24

### Added
- **Feed Summaries**: With the `rss_onebox_enhanced` setting on, a topic whose article page provides no description shows a summary from the feed inside the onebox, where the page's own description would appear, or below the link when the onebox fails. The summary is the item's `<description>` when it holds at least 80 characters of text, otherwise the opening paragraphs of the item's full body, capped at about 300 characters.
- **YouTube Descriptions**: With the `rss_onebox_youtube_descriptions` setting on, the full video description from the channel feed appears below the player, with line breaks preserved and links clickable.
- **Feed Data Capture**: RSS Polling's parser drops `media:description` and plain-text summaries, so the plugin reads each feed's XML itself during polls that import new items and stores the summary or description on the post, whether or not the display settings are on.
- **Enhance Task**: `rss_onebox:enhance` stores summaries and descriptions for topics imported earlier, trying the live feed, older feed pages (WordPress's `paged` parameter), and the article page's first substantial paragraph, then rebakes the affected topics.

## [0.1.3] - 2026-09-24

### Fixed
- **Feed Updates Overwriting Oneboxes**: When a feed item's content changed, for example after an edit to the source post or a change in the feed's format, core's `TopicEmbed.import` revised the existing post with the feed content and replaced the onebox. The plugin now wraps `TopicEmbed.import` and records the content fingerprint core is about to compute, so core no longer revises the body. Title, tag, and author changes still apply; if core rewrites the body together with them, the plugin restores the onebox silently.
- **Convert Task URL Matching**: `rss_onebox:convert` treated correct posts as needing conversion when their URL differed from the stored URL only by case or a trailing slash, and would have replaced the original URL with the lowercased one. A bare URL that normalises to the stored URL now counts as converted.

## [0.1.2] - 2026-09-23

### Fixed
- **Case-Sensitive Article URLs**: Core lowercases the URL it stores for an embed, and the plugin copied that stored URL into the post body, which broke case-sensitive URLs such as YouTube video IDs and left the player showing "This video is unavailable". New imports now use the original-case URL from core's "imported from" footer, and `rss_onebox:convert` repairs affected video topics from the stored embed content.

## [0.1.1] - 2026-09-22

### Added
- **README**: Documentation of the plugin's purpose, configuration, installation, mechanics, and known limitations.

### Changed
- **Admin Display Name and Settings Category**: The plugin is listed as "RSS Polling Onebox" instead of "Rss onebox", and its settings moved to a dedicated settings category, so the plugin's Settings button opens a page listing them.

## [0.1.0] - 2026-09-22

### Added
- **Onebox Rendering of RSS Imports**: In the configured categories, RSS Polling imports are created with the article URL as the post body and Markdown cooking, so Discourse's standard onebox builds the preview from the article page instead of the feed's truncated first paragraph.
- **Scoped "Show Full Post" Suppression**: The "Show Full Post" button, which re-scrapes the article page and is redundant for oneboxed posts, is hidden for topics in the configured categories.
- **Convert Task**: `rss_onebox:convert` converts topics imported before installation. It defaults to a dry run, is safe to repeat, and rewrites posts silently.
- **Settings**: `rss_onebox_enabled` and `rss_onebox_categories`.

[Unreleased]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.6...HEAD
[0.2.6]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Peter-Petrik/discourse-rss-onebox/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Peter-Petrik/discourse-rss-onebox/releases/tag/v0.1.0

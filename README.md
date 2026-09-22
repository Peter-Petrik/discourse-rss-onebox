# Discourse RSS Polling Onebox

This plugin changes how topics imported by Discourse's bundled [RSS Polling](https://meta.discourse.org/t/rss-polling/156387) plugin are displayed. In the categories it is configured for, each imported topic's first post becomes the bare article URL, which Discourse renders as a onebox: the article title, featured image (`og:image`) and description (`og:description`) taken from the article page itself. The "Show Full Post" button is hidden in those categories. It is intended for forums that use RSS Polling to aggregate members' blogs into a category, where the stock import (the first paragraph of the feed body, with no image) reads poorly.

## Project Status

Early release, in use on a single production forum running Discourse 2026.7 ESR. See [Issues](https://github.com/Peter-Petrik/discourse-rss-onebox/issues) for known problems and planned work.

## Features

- **Onebox Rendering of New Imports**: RSS Polling imports into the configured categories are created with the article URL as the post body and Markdown cooking, so Discourse's standard onebox builds the preview. Imports into other categories are unchanged.
- **Scoped "Show Full Post" Suppression**: The button, which re-scrapes the article page and is redundant once the post is a onebox, is hidden only for topics in the configured categories. Everywhere else, core behaviour applies.
- **Bulk Conversion of Existing Topics**: A rake task converts topics imported before the plugin was installed. It defaults to a dry run, is safe to repeat, and rewrites posts silently: no revision history, no bump, no notifications, and topic dates are unchanged.
- **No Theme Component Required**: All behaviour is server-side.

## Configuration

Settings are under **Admin → Installed plugins → RSS Polling Onebox → Settings**.

| Setting | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `rss_onebox_enabled` | boolean | `false` | Enables the plugin. When disabled, imports and "Show Full Post" follow core behaviour. |
| `rss_onebox_categories` | category list | empty | Categories whose RSS-imported topics are rendered as a onebox. With no categories selected, the plugin has no effect. |

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

RSS Polling imports each feed item through core's `TopicEmbed.import`, which passes its topic-creation arguments through the `topic_embed_import_create_args` modifier. For imports into a configured category, the plugin replaces the post body with the item's URL and sets the cook method to Markdown. The Markdown setting is required: imports are otherwise stored as raw HTML unless `embed_support_markdown` is enabled, and raw HTML is never oneboxed.

"Show Full Post" is driven by the `expandable_first_post` attribute of the topic serializer. The plugin omits that attribute for topics in the configured categories and preserves core's condition everywhere else.

### Converting Existing Topics

The rake task covers every topic in the configured categories that has an embed record, regardless of which feed imported it. Run it inside the container:

```bash
cd /var/discourse
./launcher enter app
rake rss_onebox:convert
APPLY=1 rake rss_onebox:convert
exit
```

The first run is a dry run that lists each topic ID, author and article URL, then reports how many topics would be converted. `APPLY=1` performs the conversion and rebakes each post; the onebox preview is fetched by a background job, so a topic may briefly show a bare link. Posts already converted are skipped, so the task can be re-run at any time.

### Known Limitations

- **Edited source posts revert**: When a feed item's content, title or tags change after import, core's `TopicEmbed.import` revises the existing post with the feed content through a path the modifier does not cover. The topic then shows the feed body instead of the onebox. Re-running `rss_onebox:convert` restores the onebox.
- **Site-wide scope of the modifier**: The modifier applies to every `TopicEmbed.import` call targeting a configured category, including embeds created by other means than RSS Polling. Configured categories are expected to be dedicated to RSS imports.

## Future Enhancements

- **Automatic Handling of Edited Posts**: Re-apply the onebox body when core revises an embedded post, removing the need to re-run the rake task.

## Support

For bug reports and feature requests, open an issue at [GitHub Issues](https://github.com/Peter-Petrik/discourse-rss-onebox/issues). Include the Discourse version, plugin version, and the output of `rake rss_onebox:convert` if relevant.

## License

Copyright 2026 Peter Petrik. Licensed under the [MIT License](LICENSE).

import DBreadcrumbsItem from "discourse/ui-kit/d-breadcrumbs-item";
import { i18n } from "discourse-i18n";
import RssOneboxDisplayNames from "discourse/plugins/discourse-rss-onebox/discourse/components/rss-onebox-display-names";

export default <template>
  <DBreadcrumbsItem
    @path="/admin/plugins/discourse-rss-onebox/display-names"
    @label={{i18n "admin.rss_onebox.display_names.title"}}
  />
  <RssOneboxDisplayNames @model={{@model}} />
</template>

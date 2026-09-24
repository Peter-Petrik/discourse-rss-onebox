import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-rss-onebox";

export default {
  name: "rss-onebox-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "admin.rss_onebox.display_names.title",
          route: "adminPlugins.show.discourse-rss-onebox-display-names",
          description: "admin.rss_onebox.display_names.nav_description",
        },
      ]);
    });
  },
};

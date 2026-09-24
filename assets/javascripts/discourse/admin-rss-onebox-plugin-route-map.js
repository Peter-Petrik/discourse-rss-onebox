export default {
  resource: "admin.adminPlugins.show",

  path: "/plugins",

  map() {
    this.route("discourse-rss-onebox-display-names", { path: "display-names" });
  },
};

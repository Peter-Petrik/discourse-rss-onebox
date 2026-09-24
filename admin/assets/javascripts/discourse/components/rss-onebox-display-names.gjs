import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";

const BASE_URL = "/admin/plugins/rss_onebox/display_names";
const POLL_INTERVAL_MS = 3000;

class DisplayNameRow extends Component {
  @tracked value = this.args.feed.display_name || "";
  @tracked saving = false;
  @tracked saved = false;

  get changed() {
    return this.value.trim() !== (this.args.feed.display_name || "");
  }

  @action
  updateValue(event) {
    this.value = event.target.value;
    this.saved = false;
  }

  @action
  async save() {
    this.saving = true;
    try {
      const result = await ajax(`${BASE_URL}/${this.args.feed.id}`, {
        type: "PUT",
        data: { display_name: this.value.trim() },
      });
      this.args.onSaved(result.feed);
      this.value = result.feed.display_name || "";
      this.saved = true;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <tr
      class="d-table__row rss-onebox-display-name
        {{unless @feed.enabled 'is-disabled'}}"
    >
      <td class="d-table__cell --overview">
        <div class="rss-onebox-display-name__url">{{@feed.url}}</div>
        <div class="rss-onebox-display-name__meta">
          {{i18n "admin.rss_onebox.display_names.author"}}
          {{@feed.author}}
          {{#unless @feed.enabled}}
            ·
            {{i18n "admin.rss_onebox.display_names.disabled"}}
          {{/unless}}
        </div>
      </td>
      <td class="d-table__cell --detail rss-onebox-display-name__published">
        {{#if @feed.published_name}}
          {{@feed.published_name}}
        {{else}}
          <span class="rss-onebox-display-name__not-read">{{i18n
              "admin.rss_onebox.display_names.not_read_yet"
            }}</span>
        {{/if}}
        {{#if @feed.fetch_error}}
          <div class="rss-onebox-display-name__error">{{i18n
              "admin.rss_onebox.display_names.fetch_error"
            }}</div>
        {{/if}}
      </td>
      <td class="d-table__cell --controls rss-onebox-display-name__edit">
        <input
          type="text"
          value={{this.value}}
          placeholder={{@feed.published_name}}
          aria-label={{i18n "admin.rss_onebox.display_names.display_name"}}
          {{on "input" this.updateValue}}
        />
        <DButton
          @action={{this.save}}
          @label="admin.rss_onebox.display_names.save"
          @isLoading={{this.saving}}
          @disabled={{this.saving}}
          class="btn-default btn-small"
        />
        {{#if this.saved}}
          <span class="rss-onebox-display-name__saved">{{i18n
              "admin.rss_onebox.display_names.saved"
            }}</span>
        {{/if}}
      </td>
    </tr>
  </template>
}

export default class RssOneboxDisplayNames extends Component {
  @tracked feeds = this.args.model.feeds;
  @tracked refreshRunning = this.args.model.refresh_running;
  pollTimer = null;

  constructor() {
    super(...arguments);
    if (this.refreshRunning) {
      this.schedulePoll();
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    clearTimeout(this.pollTimer);
  }

  schedulePoll() {
    clearTimeout(this.pollTimer);
    this.pollTimer = setTimeout(() => this.poll(), POLL_INTERVAL_MS);
  }

  async poll() {
    try {
      const result = await ajax(`${BASE_URL}.json`);
      this.feeds = result.feeds;
      this.refreshRunning = result.refresh_running;
      if (this.refreshRunning) {
        this.schedulePoll();
      }
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async refresh() {
    try {
      await ajax(`${BASE_URL}/refresh`, { type: "POST" });
      this.refreshRunning = true;
      this.schedulePoll();
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  feedSaved(updated) {
    this.feeds = this.feeds.map((feed) =>
      feed.id === updated.id ? updated : feed
    );
  }

  <template>
    <section class="admin-detail rss-onebox-display-names">
      <DPageSubheader
        @titleLabel={{i18n "admin.rss_onebox.display_names.title"}}
        @descriptionLabel={{i18n "admin.rss_onebox.display_names.description"}}
      >
        <:actions as |actions|>
          <actions.Primary
            @action={{this.refresh}}
            @icon="arrows-rotate"
            @label={{if
              this.refreshRunning
              "admin.rss_onebox.display_names.refreshing"
              "admin.rss_onebox.display_names.refresh"
            }}
            @isLoading={{this.refreshRunning}}
            @disabled={{this.refreshRunning}}
          />
        </:actions>
      </DPageSubheader>

      {{#if this.feeds.length}}
        <table class="d-table rss-onebox-display-names__table">
          <thead class="d-table__header">
            <tr class="d-table__header-row">
              <th class="d-table__header-cell">{{i18n
                  "admin.rss_onebox.display_names.feed"
                }}</th>
              <th class="d-table__header-cell">{{i18n
                  "admin.rss_onebox.display_names.published_name"
                }}</th>
              <th class="d-table__header-cell">{{i18n
                  "admin.rss_onebox.display_names.display_name"
                }}</th>
            </tr>
          </thead>
          <tbody class="d-table__body">
            {{#each this.feeds key="id" as |feed|}}
              <DisplayNameRow @feed={{feed}} @onSaved={{this.feedSaved}} />
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <p>{{i18n "admin.rss_onebox.display_names.empty"}}</p>
      {{/if}}
    </section>
  </template>
}

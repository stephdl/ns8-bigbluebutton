<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("analytics.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.listLearningDashboards">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.list-learning-dashboards')"
          :description="error.listLearningDashboards"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <!-- What the list shows depends on this policy. -->
    <cv-row v-if="!loading.listLearningDashboards">
      <cv-column>
        <NsInlineNotification
          :kind="enabled ? 'info' : 'warning'"
          :title="
            enabled ? $t('analytics.policy') : $t('analytics.policy_disabled')
          "
          :description="
            enabled
              ? maxAgeDays === 0
                ? $t('analytics.retention_unlimited')
                : $t('analytics.retention_days', { days: maxAgeDays })
              : $t('analytics.policy_disabled_description')
          "
          :showCloseButton="false"
          :actionLabel="$t('analytics.go_to_settings')"
          @action="goToAppPage(instanceName, 'settings')"
        />
      </cv-column>
    </cv-row>
    <!-- Outside the tile, so refreshing stays reachable while the skeleton shows. -->
    <cv-row class="toolbar">
      <cv-column>
        <NsButton
          kind="secondary"
          :icon="Renew20"
          :disabled="loading.listLearningDashboards"
          @click="listLearningDashboards"
          >{{ $t("common.refresh") }}</NsButton
        >
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <div v-if="!loading.listLearningDashboards">
            <NsEmptyState
              v-if="!reports.length"
              :title="$t('analytics.no_reports')"
            >
              <template #description>
                {{
                  enabled
                    ? $t("analytics.no_reports_description")
                    : $t("analytics.no_reports_disabled_description")
                }}
              </template>
            </NsEmptyState>
            <NsDataTable
              v-else
              :allRows="reports"
              :columns="columns"
              :rawColumns="rawColumns"
              :overflow-menu="true"
              :isSearchable="true"
              :searchPlaceholder="$t('analytics.search')"
              :noSearchResultsLabel="core.$t('common.no_search_results')"
              :noSearchResultsDescription="
                core.$t('common.no_search_results_description')
              "
              :filterRowsCallback="filterReports"
              :itemsPerPageLabel="core.$t('pagination.items_per_page')"
              :rangeOfTotalItemsLabel="
                core.$t('pagination.range_of_total_items')
              "
              :ofTotalPagesLabel="core.$t('pagination.of_total_pages')"
              :backwardText="core.$t('pagination.previous_page')"
              :forwardText="core.$t('pagination.next_page')"
              :pageNumberLabel="core.$t('pagination.page_number')"
              @updatePage="tablePage = $event"
            >
              <template slot="data">
                <cv-data-table-row
                  v-for="report in tablePage"
                  :key="report.meeting_id"
                >
                  <cv-data-table-cell class="break-word">{{
                    report.name
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    formatTimestamp(report.created_on)
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    report.ended_on
                      ? formatTimestamp(report.ended_on)
                      : $t("analytics.not_ended")
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    report.participants
                  }}</cv-data-table-cell>
                  <cv-data-table-cell class="table-overflow-menu-cell">
                    <cv-overflow-menu flip-menu class="table-overflow-menu">
                      <!-- Only the menu item carries the token. -->
                      <cv-overflow-menu-item @click="openReport(report)">
                        <NsMenuItem
                          :icon="Launch20"
                          :label="$t('analytics.open_report')"
                        />
                      </cv-overflow-menu-item>
                      <NsMenuDivider />
                      <cv-overflow-menu-item
                        danger
                        @click="showDeleteReportModal(report)"
                      >
                        <NsMenuItem
                          :icon="TrashCan20"
                          :label="$t('analytics.delete')"
                        />
                      </cv-overflow-menu-item>
                    </cv-overflow-menu>
                  </cv-data-table-cell>
                </cv-data-table-row>
              </template>
            </NsDataTable>
          </div>
          <cv-skeleton-text
            v-else
            :paragraph="true"
            :line-count="5"
          ></cv-skeleton-text>
        </cv-tile>
      </cv-column>
    </cv-row>
    <DeleteAnalyticsReportModal
      :visible="isShownDeleteReportModal"
      :report="reportToDelete"
      @deleted="onReportDeleted"
      @hide="isShownDeleteReportModal = false"
    />
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
// Not in IconService.
import RenewIcon from "@carbon/icons-vue/es/renew/20";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";
import DeleteAnalyticsReportModal from "@/components/DeleteAnalyticsReportModal.vue";

export default {
  name: "LearningAnalytics",
  components: { DeleteAnalyticsReportModal },
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("analytics.title");
  },
  data() {
    return {
      q: {
        page: "learning-analytics",
      },
      urlCheckInterval: null,
      enabled: true,
      maxAgeDays: 1,
      reports: [],
      tablePage: [],
      reportToDelete: null,
      isShownDeleteReportModal: false,
      loading: {
        listLearningDashboards: true,
      },
      error: {
        listLearningDashboards: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    Renew20() {
      return RenewIcon;
    },
    columns() {
      return [
        this.$t("analytics.meeting"),
        this.$t("analytics.started"),
        this.$t("analytics.ended"),
        this.$t("analytics.participants"),
      ];
    },
    rawColumns() {
      // No entry for the overflow menu: NsDataTable adds that column itself.
      return ["name", "created_on", "ended_on", "participants"];
    },
  },
  created() {
    this.listLearningDashboards();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    // Only on what is displayed: the default would match the URL, token included.
    filterReports(search) {
      if (!search) {
        return this.reports;
      }
      const needle = search.toLowerCase();
      return this.reports.filter((report) =>
        [
          report.name,
          this.formatTimestamp(report.created_on),
          report.ended_on ? this.formatTimestamp(report.ended_on) : "",
        ]
          .join(" ")
          .toLowerCase()
          .includes(needle)
      );
    },
    formatTimestamp(milliseconds) {
      return new Date(milliseconds).toLocaleString();
    },
    openReport(report) {
      window.open(report.url, "_blank", "noopener");
    },
    showDeleteReportModal(report) {
      this.reportToDelete = report;
      this.isShownDeleteReportModal = true;
    },
    onReportDeleted(deleted) {
      // The disk state is already known: refetching would only flash the skeleton.
      // On the token too: a meeting can hold more than one report directory, and
      // only the one that was deleted must leave the table.
      this.reports = this.reports.filter(
        (report) =>
          report.meeting_id !== deleted.meeting_id ||
          report.token !== deleted.token
      );
    },
    async listLearningDashboards() {
      this.loading.listLearningDashboards = true;
      this.error.listLearningDashboards = "";
      const taskAction = "list-learning-dashboards";
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.listLearningDashboardsAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.listLearningDashboardsCompleted
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.listLearningDashboards = this.getErrorMessage(err);
        this.loading.listLearningDashboards = false;
        return;
      }
    },
    listLearningDashboardsAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.listLearningDashboards = this.$t("error.generic_error");
      this.loading.listLearningDashboards = false;
    },
    listLearningDashboardsCompleted(taskContext, taskResult) {
      const output = taskResult.output;
      this.enabled = output.enabled;
      this.maxAgeDays = output.max_age_days;
      this.reports = output.reports;
      this.loading.listLearningDashboards = false;
    },
  },
};
</script>

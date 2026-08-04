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
    <!-- The list only makes sense against the policy that governs it. -->
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
            <cv-structured-list v-else>
              <template slot="headings">
                <cv-structured-list-heading>{{
                  $t("analytics.meeting")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("analytics.started")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("analytics.ended")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("analytics.participants")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading></cv-structured-list-heading>
              </template>
              <template slot="items">
                <cv-structured-list-item
                  v-for="report in reports"
                  :key="report.meeting_id"
                >
                  <cv-structured-list-data class="break-word">{{
                    report.name
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>{{
                    formatTimestamp(report.created_on)
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>{{
                    report.ended_on
                      ? formatTimestamp(report.ended_on)
                      : $t("analytics.not_ended")
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>{{
                    report.participants
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>
                    <!-- The link carries the access token, so it is never shown. -->
                    <NsButton
                      kind="ghost"
                      size="small"
                      :icon="Launch20"
                      @click="openReport(report)"
                      >{{ $t("analytics.open_report") }}</NsButton
                    >
                  </cv-structured-list-data>
                </cv-structured-list-item>
              </template>
            </cv-structured-list>
          </div>
          <cv-skeleton-text
            v-else
            :paragraph="true"
            :line-count="5"
          ></cv-skeleton-text>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
// IconService does not expose this one.
import LaunchIcon from "@carbon/icons-vue/es/launch/20";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

export default {
  name: "LearningAnalytics",
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
    Launch20() {
      return LaunchIcon;
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
    formatTimestamp(milliseconds) {
      return new Date(milliseconds).toLocaleString();
    },
    openReport(report) {
      window.open(report.url, "_blank", "noopener");
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

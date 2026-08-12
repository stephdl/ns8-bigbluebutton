<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <NsModal
    size="default"
    kind="danger"
    :visible="visible"
    :isLoading="loading.deleteLearningDashboard"
    :primary-button-disabled="loading.deleteLearningDashboard"
    @modal-hidden="onModalHidden"
    @primary-click="deleteLearningDashboard"
  >
    <template slot="title">
      {{ $t("analytics.delete_title") }}
    </template>
    <template slot="content">
      <p>
        {{ $t("analytics.delete_description", { name: reportName }) }}
      </p>
      <NsInlineNotification
        v-if="error.deleteLearningDashboard"
        kind="error"
        :title="$t('action.delete-learning-dashboard')"
        :description="error.deleteLearningDashboard"
        :showCloseButton="false"
      />
    </template>
    <template slot="secondary-button">{{ core.$t("common.cancel") }}</template>
    <template slot="primary-button">{{
      $t("analytics.delete_confirm")
    }}</template>
  </NsModal>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import { UtilService, TaskService, IconService } from "@nethserver/ns8-ui-lib";

export default {
  name: "DeleteAnalyticsReportModal",
  mixins: [UtilService, TaskService, IconService],
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    report: {
      // Null while no row is selected, so the modal can stay mounted.
      type: Object,
      default: null,
    },
  },
  data() {
    return {
      loading: { deleteLearningDashboard: false },
      error: { deleteLearningDashboard: "" },
    };
  },
  computed: {
    ...mapState(["instanceName", "core"]),
    reportName() {
      return this.report ? this.report.name : "";
    },
  },
  methods: {
    async deleteLearningDashboard() {
      if (!this.report) {
        return;
      }
      this.error.deleteLearningDashboard = "";
      this.loading.deleteLearningDashboard = true;
      const taskAction = "delete-learning-dashboard";
      // Captured now: the selected row may have changed by the time the task ends.
      const deleted = {
        meeting_id: this.report.meeting_id,
        token: this.report.token,
      };
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.deleteLearningDashboardAborted
      );
      this.core.$root.$once(`${taskAction}-completed-${eventId}`, () =>
        this.deleteLearningDashboardCompleted(deleted)
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: deleted,
          extra: {
            title: this.$t("action." + taskAction),
            description: this.$t("analytics.deleting", {
              name: this.reportName,
            }),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.deleteLearningDashboard = this.getErrorMessage(err);
        this.loading.deleteLearningDashboard = false;
        return;
      }
    },
    deleteLearningDashboardAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.deleteLearningDashboard = this.$t("error.generic_error");
      this.loading.deleteLearningDashboard = false;
    },
    deleteLearningDashboardCompleted(deleted) {
      this.loading.deleteLearningDashboard = false;
      this.$emit("deleted", deleted);
      this.$emit("hide");
    },
    onModalHidden() {
      this.clearErrors();
      this.$emit("hide");
    },
  },
};
</script>

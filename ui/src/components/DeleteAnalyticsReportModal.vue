<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <!-- The start date is what must be typed: it is the only field that tells two
       sessions of the same room apart. -->
  <NsDangerDeleteModal
    :isShown="visible"
    :name="startedLabel"
    :title="$t('analytics.delete_title')"
    :warning="core.$t('common.please_read_carefully')"
    :typeToConfirm="
      $t('common.type_start_date_to_confirm', { date: startedLabel })
    "
    :cancelLabel="core.$t('common.cancel')"
    :deleteLabel="core.$t('common.understood_delete')"
    :isErrorShown="!!error.deleteLearningDashboard"
    :errorTitle="$t('action.delete-learning-dashboard')"
    :errorDescription="error.deleteLearningDashboard"
    :loading="loading.deleteLearningDashboard"
    @hide="onModalHidden"
    @confirmDelete="deleteLearningDashboard"
  >
    <template slot="description">
      <p>{{ $t("analytics.delete_description") }}</p>
      <dl v-if="report" class="details">
        <dt>{{ $t("analytics.meeting") }}</dt>
        <dd>{{ reportName }}</dd>
        <dt>{{ $t("analytics.started") }}</dt>
        <dd>{{ startedLabel }}</dd>
        <dt>{{ $t("analytics.ended") }}</dt>
        <dd>{{ endedLabel }}</dd>
      </dl>
    </template>
  </NsDangerDeleteModal>
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
    startedLabel() {
      return this.report ? this.formatTimestamp(this.report.created_on) : "";
    },
    endedLabel() {
      if (!this.report) {
        return "";
      }
      return this.report.ended_on
        ? this.formatTimestamp(this.report.ended_on)
        : this.$t("analytics.not_ended");
    },
  },
  methods: {
    // Same formatting as the table, so the two can be compared at a glance.
    formatTimestamp(milliseconds) {
      return milliseconds ? new Date(milliseconds).toLocaleString() : "—";
    },
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
      // False when dismissed mid-task: the row still goes, but the modal on screen
      // now belongs to another row and must not be closed.
      const stillMine = this.loading.deleteLearningDashboard;
      this.loading.deleteLearningDashboard = false;
      this.$emit("deleted", deleted);
      if (stillMine) {
        this.$emit("hide");
      }
    },
    onModalHidden() {
      // Left true by a dismissal, it disables the primary button for good.
      this.loading.deleteLearningDashboard = false;
      this.clearErrors();
      this.$emit("hide");
    },
  },
};
</script>
<style scoped lang="scss">
@import "../styles/carbon-utils";

.details {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: $spacing-02 $spacing-05;
  margin-top: $spacing-05;

  dt {
    color: $text-02;
  }
}
</style>

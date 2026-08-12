<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <NsModal
    size="default"
    kind="danger"
    :visible="visible"
    :isLoading="loading.deleteRecording"
    :primary-button-disabled="loading.deleteRecording"
    @modal-hidden="onModalHidden"
    @primary-click="deleteRecording"
  >
    <template slot="title">
      {{ $t("recordings.delete_title") }}
    </template>
    <template slot="content">
      <p>
        {{ $t("recordings.delete_description", { name: recordingName }) }}
      </p>
      <!-- The times, so a wrong row is caught before the deletion and not after. -->
      <dl v-if="recording" class="times">
        <dt>{{ $t("recordings.started") }}</dt>
        <dd>{{ startedLabel }}</dd>
        <dt>{{ $t("recordings.ended") }}</dt>
        <dd>{{ endedLabel }}</dd>
      </dl>
      <NsInlineNotification
        v-if="error.deleteRecording"
        kind="error"
        :title="$t('action.delete-recording')"
        :description="error.deleteRecording"
        :showCloseButton="false"
      />
    </template>
    <template slot="secondary-button">{{ core.$t("common.cancel") }}</template>
    <template slot="primary-button">{{
      $t("recordings.delete_confirm")
    }}</template>
  </NsModal>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import { UtilService, TaskService, IconService } from "@nethserver/ns8-ui-lib";

export default {
  name: "DeleteRecordingModal",
  mixins: [UtilService, TaskService, IconService],
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    recording: {
      // Null while no row is selected, so the modal can stay mounted.
      type: Object,
      default: null,
    },
  },
  data() {
    return {
      loading: { deleteRecording: false },
      error: { deleteRecording: "" },
    };
  },
  computed: {
    ...mapState(["instanceName", "core"]),
    recordingName() {
      return this.recording ? this.recording.name : "";
    },
    startedLabel() {
      return this.recording
        ? this.formatTimestamp(this.recording.start_time)
        : "";
    },
    endedLabel() {
      if (!this.recording) {
        return "";
      }
      return this.recording.end_time
        ? this.formatTimestamp(this.recording.end_time)
        : this.$t("recordings.not_ended");
    },
  },
  methods: {
    // Same formatting as the table, so the two can be compared at a glance.
    formatTimestamp(milliseconds) {
      return milliseconds ? new Date(milliseconds).toLocaleString() : "—";
    },
    async deleteRecording() {
      if (!this.recording) {
        return;
      }
      this.error.deleteRecording = "";
      this.loading.deleteRecording = true;
      const taskAction = "delete-recording";
      const meetingId = this.recording.meeting_id;
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.deleteRecordingAborted
      );
      this.core.$root.$once(`${taskAction}-completed-${eventId}`, () =>
        this.deleteRecordingCompleted(meetingId)
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            meeting_id: meetingId,
          },
          extra: {
            title: this.$t("action." + taskAction),
            description: this.$t("recordings.deleting", {
              name: this.recordingName,
            }),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.deleteRecording = this.getErrorMessage(err);
        this.loading.deleteRecording = false;
        return;
      }
    },
    deleteRecordingAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.deleteRecording = this.$t("error.generic_error");
      this.loading.deleteRecording = false;
    },
    deleteRecordingCompleted(meetingId) {
      // False when dismissed mid-task: the row still goes, but the modal on screen
      // now belongs to another row and must not be closed.
      const stillMine = this.loading.deleteRecording;
      this.loading.deleteRecording = false;
      this.$emit("deleted", meetingId);
      if (stillMine) {
        this.$emit("hide");
      }
    },
    onModalHidden() {
      // Left true by a dismissal, it disables the primary button for good.
      this.loading.deleteRecording = false;
      this.clearErrors();
      this.$emit("hide");
    },
  },
};
</script>
<style scoped lang="scss">
@import "../styles/carbon-utils";

.times {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: $spacing-02 $spacing-05;
  margin-top: $spacing-05;

  dt {
    color: $text-02;
  }
}
</style>

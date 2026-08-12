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
  },
  methods: {
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
      this.loading.deleteRecording = false;
      this.$emit("deleted", meetingId);
      this.$emit("hide");
    },
    onModalHidden() {
      this.clearErrors();
      this.$emit("hide");
    },
  },
};
</script>

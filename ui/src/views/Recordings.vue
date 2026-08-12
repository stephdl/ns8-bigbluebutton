<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("recordings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.listRecordings">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.list-recordings')"
          :description="error.listRecordings"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <!-- What the list shows depends on this policy. -->
    <cv-row v-if="!loading.listRecordings">
      <cv-column>
        <NsInlineNotification
          :kind="enabled ? 'info' : 'warning'"
          :title="
            enabled ? $t('recordings.policy') : $t('recordings.policy_disabled')
          "
          :description="
            enabled
              ? maxAgeDays === 0
                ? $t('recordings.retention_unlimited')
                : $t('recordings.retention_days', { days: maxAgeDays })
              : $t('recordings.policy_disabled_description')
          "
          :showCloseButton="false"
          :actionLabel="$t('recordings.go_to_settings')"
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
          :disabled="loading.listRecordings"
          @click="listRecordings"
          >{{ $t("common.refresh") }}</NsButton
        >
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <div v-if="!loading.listRecordings">
            <NsEmptyState
              v-if="!recordings.length"
              :title="$t('recordings.no_recordings')"
            >
              <template #description>
                {{
                  enabled
                    ? $t("recordings.no_recordings_description")
                    : $t("recordings.no_recordings_disabled_description")
                }}
              </template>
            </NsEmptyState>
            <NsDataTable
              v-else
              :allRows="recordings"
              :columns="columns"
              :rawColumns="rawColumns"
              :overflow-menu="true"
              :isSearchable="true"
              :searchPlaceholder="$t('recordings.search')"
              :noSearchResultsLabel="core.$t('common.no_search_results')"
              :noSearchResultsDescription="
                core.$t('common.no_search_results_description')
              "
              :filterRowsCallback="filterRecordings"
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
                  v-for="recording in tablePage"
                  :key="recording.meeting_id"
                >
                  <cv-data-table-cell class="break-word">{{
                    recording.name
                  }}</cv-data-table-cell>
                  <cv-data-table-cell class="break-word">
                    <!-- Only the room owner, never a participant. -->
                    <span v-if="recording.owner_name || recording.owner_email">
                      {{ recording.owner_name }}
                      <template v-if="recording.owner_email">
                        <br />
                        <span class="owner-email">{{
                          recording.owner_email
                        }}</span>
                      </template>
                    </span>
                    <span v-else>{{ $t("recordings.no_owner") }}</span>
                  </cv-data-table-cell>
                  <cv-data-table-cell>{{
                    formatTimestamp(recording.start_time)
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    recording.end_time
                      ? formatTimestamp(recording.end_time)
                      : $t("recordings.not_ended")
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    (recording.duration / 1000) | secondsFormat
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    recording.size | byteFormat
                  }}</cv-data-table-cell>
                  <cv-data-table-cell class="table-overflow-menu-cell">
                    <cv-overflow-menu flip-menu class="table-overflow-menu">
                      <cv-overflow-menu-item @click="openRecording(recording)">
                        <NsMenuItem
                          :icon="Launch20"
                          :label="$t('recordings.play')"
                        />
                      </cv-overflow-menu-item>
                      <NsMenuDivider />
                      <cv-overflow-menu-item
                        danger
                        @click="showDeleteRecordingModal(recording)"
                      >
                        <NsMenuItem
                          :icon="TrashCan20"
                          :label="$t('recordings.delete')"
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
    <DeleteRecordingModal
      :visible="isShownDeleteRecordingModal"
      :recording="recordingToDelete"
      @deleted="onRecordingDeleted"
      @hide="isShownDeleteRecordingModal = false"
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
import DeleteRecordingModal from "@/components/DeleteRecordingModal.vue";

export default {
  name: "Recordings",
  components: { DeleteRecordingModal },
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("recordings.title");
  },
  data() {
    return {
      q: {
        page: "recordings",
      },
      urlCheckInterval: null,
      enabled: true,
      maxAgeDays: 0,
      recordings: [],
      tablePage: [],
      recordingToDelete: null,
      isShownDeleteRecordingModal: false,
      loading: {
        listRecordings: true,
      },
      error: {
        listRecordings: "",
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
        this.$t("recordings.room"),
        this.$t("recordings.owner"),
        this.$t("recordings.started"),
        this.$t("recordings.ended"),
        this.$t("recordings.duration"),
        this.$t("recordings.size"),
      ];
    },
    rawColumns() {
      // duration and size sort on the raw numbers, not on the formatted cells.
      // No entry for the overflow menu: NsDataTable adds that column itself.
      return [
        "name",
        "owner_name",
        "start_time",
        "end_time",
        "duration",
        "size",
      ];
    },
  },
  created() {
    this.listRecordings();
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
    // Only on what is displayed: the default would match the playback URL too.
    filterRecordings(search) {
      if (!search) {
        return this.recordings;
      }
      const needle = search.toLowerCase();
      return this.recordings.filter((recording) =>
        [
          recording.name,
          recording.owner_name,
          recording.owner_email,
          this.formatTimestamp(recording.start_time),
          recording.end_time ? this.formatTimestamp(recording.end_time) : "",
        ]
          .join(" ")
          .toLowerCase()
          .includes(needle)
      );
    },
    formatTimestamp(milliseconds) {
      // 0 means metadata.xml carried no such time; a 1970 date would read as data.
      if (!milliseconds) {
        return "—";
      }
      return new Date(milliseconds).toLocaleString();
    },
    openRecording(recording) {
      window.open(recording.url, "_blank", "noopener");
    },
    showDeleteRecordingModal(recording) {
      this.recordingToDelete = recording;
      this.isShownDeleteRecordingModal = true;
    },
    onRecordingDeleted(meetingId) {
      // The disk state is already known: refetching would only flash the skeleton.
      this.recordings = this.recordings.filter(
        (recording) => recording.meeting_id !== meetingId
      );
    },
    async listRecordings() {
      this.loading.listRecordings = true;
      this.error.listRecordings = "";
      const taskAction = "list-recordings";
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.listRecordingsAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.listRecordingsCompleted
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
        this.error.listRecordings = this.getErrorMessage(err);
        this.loading.listRecordings = false;
        return;
      }
    },
    listRecordingsAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.listRecordings = this.$t("error.generic_error");
      this.loading.listRecordings = false;
    },
    listRecordingsCompleted(taskContext, taskResult) {
      const output = taskResult.output;
      this.enabled = output.enabled;
      this.maxAgeDays = output.max_age_days;
      this.recordings = output.recordings;
      this.loading.listRecordings = false;
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";

.owner-email {
  color: $text-02;
}
</style>

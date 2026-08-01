<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <NsTextInput
              :label="$t('settings.bigbluebutton_fqdn')"
              placeholder="bbb.example.org"
              v-model.trim="host"
              class="mg-bottom"
              :invalid-message="$t(error.host)"
              :disabled="stillLoading"
              tooltipAlignment="start"
              tooltipDirection="right"
              ref="host"
            >
              <template #tooltip>
                {{ $t("settings.bigbluebutton_fqdn_tooltip") }}
              </template>
            </NsTextInput>
            <NsToggle
              value="letsEncrypt"
              :label="core.$t('apps_lets_encrypt.request_https_certificate')"
              v-model="isLetsEncryptEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                <div class="mg-bottom-sm">
                  {{ core.$t("apps_lets_encrypt.lets_encrypt_tips") }}
                </div>
                <div class="mg-bottom-sm">
                  <cv-link @click="goToCertificates">
                    {{ core.$t("apps_lets_encrypt.go_to_tls_certificates") }}
                  </cv-link>
                </div>
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <cv-row
              v-if="isLetsEncryptCurrentlyEnabled && !isLetsEncryptEnabled"
            >
              <cv-column>
                <NsInlineNotification
                  kind="warning"
                  :title="
                    core.$t('apps_lets_encrypt.lets_encrypt_disabled_warning')
                  "
                  :description="
                    core.$t(
                      'apps_lets_encrypt.lets_encrypt_disabled_warning_description',
                      {
                        node: status.node_ui_name
                          ? status.node_ui_name
                          : status.node,
                      }
                    )
                  "
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>

            <NsInlineNotification
              v-if="!certificateMatchesHost"
              kind="warning"
              :title="$t('settings.certificate_mismatch_title')"
              :description="$t('settings.certificate_mismatch_description')"
              :showCloseButton="false"
              class="mg-bottom"
            />

            <!-- network -->
            <h4 class="mg-bottom">{{ $t("settings.network") }}</h4>
            <NsTextInput
              :label="$t('settings.public_address')"
              placeholder="203.0.113.10"
              v-model.trim="publicAddress"
              class="mg-bottom"
              :invalid-message="$t(error.public_address)"
              :disabled="stillLoading"
              tooltipAlignment="start"
              tooltipDirection="right"
              ref="public_address"
            >
              <template #tooltip>
                {{ $t("settings.public_address_tooltip") }}
              </template>
            </NsTextInput>
            <NsTextInput
              :label="$t('settings.private_address')"
              placeholder="192.168.1.10"
              v-model.trim="privateAddress"
              class="mg-bottom"
              :invalid-message="$t(error.private_address)"
              :disabled="stillLoading"
              tooltipAlignment="start"
              tooltipDirection="right"
              ref="private_address"
            >
              <template #tooltip>
                {{ $t("settings.private_address_tooltip") }}
              </template>
            </NsTextInput>
            <!-- The firewall rule on this node is created by the module, but a
                 router in front of it is out of our reach: show the range. -->
            <NsInlineNotification
              v-if="mediasoupPortRange"
              kind="info"
              :title="$t('settings.udp_ports_title')"
              :description="
                $t('settings.udp_ports_description', {
                  range: mediasoupPortRange,
                })
              "
              :showCloseButton="false"
              class="mg-bottom"
            />

            <!-- accounts -->
            <h4 class="mg-bottom">{{ $t("settings.accounts") }}</h4>
            <NsComboBox
              v-model="registrationMethod"
              :options="registrationMethodOptions"
              :label="$t('settings.registration_method')"
              :title="$t('settings.registration_method')"
              :disabled="stillLoading"
              :acceptUserInput="false"
              class="mg-bottom"
              ref="registration_method"
            >
              <template #tooltip>
                {{ $t("settings.registration_method_tooltip") }}
              </template>
            </NsComboBox>
            <NsTextInput
              v-if="registrationMethod !== 'invite'"
              :label="$t('settings.allowed_domains')"
              placeholder="example.org,example.com"
              v-model.trim="allowedDomains"
              class="mg-bottom"
              :disabled="stillLoading"
              ref="allowed_domains"
            >
              <template #tooltip>
                {{ $t("settings.allowed_domains_tooltip") }}
              </template>
            </NsTextInput>

            <!-- recording -->
            <h4 class="mg-bottom">{{ $t("settings.recording") }}</h4>
            <NsToggle
              value="enableRecording"
              :label="$t('settings.enable_recording')"
              v-model="isRecordingEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                {{ $t("settings.enable_recording_tooltip") }}
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <template v-if="isRecordingEnabled">
              <NsToggle
                value="removeOldRecording"
                :label="$t('settings.remove_old_recording')"
                v-model="isRemoveOldRecordingEnabled"
                :disabled="stillLoading"
                class="mg-bottom"
              >
                <template #tooltip>
                  {{ $t("settings.remove_old_recording_tooltip") }}
                </template>
                <template slot="text-left">{{
                  $t("settings.disabled")
                }}</template>
                <template slot="text-right">{{
                  $t("settings.enabled")
                }}</template>
              </NsToggle>
              <NsTextInput
                v-if="isRemoveOldRecordingEnabled"
                type="number"
                min="1"
                :label="$t('settings.recording_max_age_days')"
                v-model.trim="recordingMaxAgeDays"
                class="mg-bottom"
                :invalid-message="$t(error.recording_max_age_days)"
                :disabled="stillLoading"
                ref="recording_max_age_days"
              />
            </template>

            <!-- advanced options -->
            <cv-accordion ref="accordion" class="maxwidth mg-bottom">
              <cv-accordion-item :open="toggleAccordion[0]">
                <template slot="title">{{ $t("settings.advanced") }}</template>
                <template slot="content">
                  <h4 class="mg-bottom">{{ $t("settings.media") }}</h4>
                  <NsComboBox
                    v-model="soundsLanguage"
                    :options="soundsLanguageOptions"
                    :label="$t('settings.sounds_language')"
                    :title="$t('settings.sounds_language')"
                    :disabled="stillLoading"
                    :acceptUserInput="false"
                    tooltipAlignment="start"
                    tooltipDirection="right"
                    class="mg-bottom"
                    ref="sounds_language"
                  >
                    <template #tooltip>
                      {{ $t("settings.sounds_language_tooltip") }}
                    </template>
                  </NsComboBox>
                  <NsToggle
                    value="disableSoundMuted"
                    :label="$t('settings.disable_sound_muted')"
                    v-model="isSoundMutedDisabled"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                  <NsToggle
                    value="disableSoundAlone"
                    :label="$t('settings.disable_sound_alone')"
                    v-model="isSoundAloneDisabled"
                    :disabled="stillLoading"
                    class="mg-bottom"
                  >
                    <template slot="text-left">{{
                      $t("settings.disabled")
                    }}</template>
                    <template slot="text-right">{{
                      $t("settings.enabled")
                    }}</template>
                  </NsToggle>
                  <NsTextInput
                    :label="$t('settings.stun_server')"
                    placeholder="stun:stun.example.org:3478"
                    v-model.trim="stunServer"
                    class="mg-bottom"
                    :invalid-message="$t(error.stun_server)"
                    :disabled="stillLoading"
                    tooltipAlignment="start"
                    tooltipDirection="right"
                    ref="stun_server"
                  >
                    <template #tooltip>
                      {{ $t("settings.stun_server_tooltip") }}
                    </template>
                  </NsTextInput>
                  <NsTextInput
                    :label="$t('settings.turn_ext_server')"
                    placeholder="turns:turn.example.org:443?transport=tcp"
                    v-model.trim="turnExtServer"
                    class="mg-bottom"
                    :invalid-message="$t(error.turn_ext_server)"
                    :disabled="stillLoading"
                    tooltipAlignment="start"
                    tooltipDirection="right"
                    ref="turn_ext_server"
                  >
                    <template #tooltip>
                      {{ $t("settings.turn_ext_server_tooltip") }}
                    </template>
                  </NsTextInput>

                  <h4 class="mg-bottom">{{ $t("settings.welcome") }}</h4>
                  <NsTextInput
                    :label="$t('settings.welcome_message')"
                    v-model.trim="welcomeMessage"
                    class="mg-bottom"
                    :disabled="stillLoading"
                    tooltipAlignment="start"
                    tooltipDirection="right"
                    ref="welcome_message"
                  >
                    <template #tooltip>
                      {{ $t("settings.welcome_message_tooltip") }}
                    </template>
                  </NsTextInput>
                  <NsTextInput
                    :label="$t('settings.welcome_footer')"
                    v-model.trim="welcomeFooter"
                    class="mg-bottom"
                    :disabled="stillLoading"
                    ref="welcome_footer"
                  />
                </template>
              </cv-accordion-item>
            </cv-accordion>
            <cv-row v-if="error.configureModule">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.configure-module')"
                  :description="error.configureModule"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <cv-row v-if="error.getStatus">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.get-status')"
                  :description="error.getStatus"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <cv-row v-if="validationErrorDetails.length">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="
                    core.$t('apps_lets_encrypt.cannot_obtain_certificate')
                  "
                  :showCloseButton="false"
                >
                  <template #description>
                    <div class="flex flex-col gap-2">
                      <div
                        v-for="(detail, index) in validationErrorDetails"
                        :key="index"
                      >
                        {{ detail }}
                      </div>
                    </div>
                  </template>
                </NsInlineNotification>
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="stillLoading"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <h4 class="mg-bottom">{{ $t("settings.create_admin") }}</h4>
          <div class="mg-bottom subtle">
            {{ $t("settings.create_admin_description") }}
          </div>
          <cv-form @submit.prevent="createAdmin">
            <NsTextInput
              :label="$t('settings.admin_name')"
              v-model.trim="admin.name"
              class="mg-bottom"
              :invalid-message="$t(error.admin_name)"
              :disabled="loading.createAdmin"
              ref="admin_name"
            />
            <NsTextInput
              :label="$t('settings.admin_email')"
              v-model.trim="admin.email"
              class="mg-bottom"
              :invalid-message="$t(error.admin_email)"
              :disabled="loading.createAdmin"
              ref="admin_email"
            />
            <NsPasswordInput
              :label="$t('settings.admin_password')"
              v-model="admin.password"
              class="mg-bottom"
              :invalid-message="$t(error.admin_password)"
              :disabled="loading.createAdmin"
              :newPasswordLabel="$t('settings.admin_password')"
              :passwordHideLabel="core.$t('password.hide_password')"
              :passwordShowLabel="core.$t('password.show_password')"
              ref="admin_password"
            />
            <NsInlineNotification
              v-if="adminCreated"
              kind="success"
              :title="$t('settings.create_admin')"
              :description="
                $t('settings.admin_created', { email: adminCreated })
              "
              :showCloseButton="false"
              class="mg-bottom"
            />
            <NsInlineNotification
              v-if="error.createAdmin"
              kind="error"
              :title="$t('settings.create_admin')"
              :description="error.createAdmin"
              :showCloseButton="false"
              class="mg-bottom"
            />
            <NsButton
              kind="secondary"
              :icon="User20"
              :loading="loading.createAdmin"
              :disabled="loading.createAdmin"
              >{{ $t("settings.create_admin_button") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

// Sound packages the FreeSWITCH entrypoint knows how to install. Keep in sync
// with the enum in imageroot/actions/configure-module/validate-input.json.
const SOUNDS_LANGUAGES = [
  "en-ca-june",
  "en-us-allison",
  "en-us-callie",
  "de-de-daedalus3",
  "es-ar-mario",
  "fr-ca-june",
  "pt-br-karina",
  "ru-RU-elena",
  "ru-RU-kirill",
  "ru-RU-vika",
  "sv-se-jakob",
  "zh-cn-sinmei",
  "zh-hk-sinmei",
];

export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      status: {},
      validationErrorDetails: [],
      urlCheckInterval: null,
      toggleAccordion: [false],
      host: "",
      isLetsEncryptEnabled: false,
      isLetsEncryptCurrentlyEnabled: false,
      publicAddress: "",
      privateAddress: "",
      mediasoupPortRange: "",
      certificateMatchesHost: true,
      admin: { name: "", email: "", password: "" },
      adminCreated: "",
      stunServer: "",
      turnExtServer: "",
      registrationMethod: "open",
      allowedDomains: "",
      isRecordingEnabled: false,
      isRemoveOldRecordingEnabled: false,
      recordingMaxAgeDays: "14",
      soundsLanguage: "en-us-callie",
      isSoundMutedDisabled: false,
      isSoundAloneDisabled: false,
      welcomeMessage: "",
      welcomeFooter: "",
      loading: {
        getConfiguration: false,
        configureModule: false,
        getStatus: false,
        createAdmin: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        getStatus: "",
        host: "",
        lets_encrypt: "",
        public_address: "",
        private_address: "",
        stun_server: "",
        turn_ext_server: "",
        recording_max_age_days: "",
        createAdmin: "",
        admin_name: "",
        admin_email: "",
        admin_password: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    stillLoading() {
      return (
        this.loading.getConfiguration ||
        this.loading.configureModule ||
        this.loading.getStatus
      );
    },
    registrationMethodOptions() {
      return ["open", "invite", "approval"].map((value) => ({
        name: value,
        label: this.$t("settings.registration_" + value),
        value,
      }));
    },
    soundsLanguageOptions() {
      return SOUNDS_LANGUAGES.map((code) => ({
        name: code,
        label: code,
        value: code,
      }));
    },
  },
  created() {
    this.getConfiguration();
    this.getStatus();
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
    goToCertificates() {
      this.core.$router.push("/settings/tls-certificates");
    },
    async getStatus() {
      this.loading.getStatus = true;
      this.error.getStatus = "";
      const taskAction = "get-status";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getStatusAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getStatusCompleted
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
        this.error.getStatus = this.getErrorMessage(err);
        this.loading.getStatus = false;
        return;
      }
    },
    getStatusAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getStatus = this.$t("error.generic_error");
      this.loading.getStatus = false;
    },
    getStatusCompleted(taskContext, taskResult) {
      this.status = taskResult.output;
      this.loading.getStatus = false;
    },
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
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
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.isLetsEncryptCurrentlyEnabled = config.lets_encrypt;
      this.publicAddress = config.public_address;
      this.privateAddress = config.private_address;
      this.mediasoupPortRange = config.mediasoup_port_range;
      this.certificateMatchesHost = config.certificate_matches_host;
      this.stunServer = config.stun_server;
      this.turnExtServer = config.turn_ext_server;
      this.registrationMethod = config.registration_method;
      this.allowedDomains = config.allowed_domains;
      this.isRecordingEnabled = config.enable_recording;
      this.isRemoveOldRecordingEnabled = config.remove_old_recording;
      this.recordingMaxAgeDays = String(config.recording_max_age_days);
      this.soundsLanguage = config.sounds_language;
      this.isSoundMutedDisabled = config.disable_sound_muted;
      this.isSoundAloneDisabled = config.disable_sound_alone;
      this.welcomeMessage = config.welcome_message;
      this.welcomeFooter = config.welcome_footer;

      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      this.validationErrorDetails = [];

      let isValidationOk = true;
      const fail = (field, message) => {
        this.error[field] = message;
        if (isValidationOk) {
          this.focusElement(field);
        }
        isValidationOk = false;
      };

      if (!this.host) {
        fail("host", "common.required");
      }
      // mediasoup cannot announce an address it was never given: without it
      // clients end up with no reachable candidate at all.
      if (!this.publicAddress) {
        fail("public_address", "common.required");
      }
      if (this.isRecordingEnabled && this.isRemoveOldRecordingEnabled) {
        const days = Number(this.recordingMaxAgeDays);
        if (!Number.isInteger(days) || days < 1) {
          fail(
            "recording_max_age_days",
            "settings.recording_max_age_days_invalid"
          );
        }
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;
      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        if (validationError.details) {
          this.validationErrorDetails = validationError.details
            .split("\n")
            .filter((detail) => detail.trim() !== "");
        } else {
          this.error[param] = this.$t("settings." + validationError.error);
          if (!focusAlreadySet) {
            this.focusElement(param);
            focusAlreadySet = true;
          }
        }
      }
    },
    async configureModule() {
      if (!this.validateConfigureModule()) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            host: this.host,
            lets_encrypt: this.isLetsEncryptEnabled,
            public_address: this.publicAddress,
            private_address: this.privateAddress,
            stun_server: this.stunServer,
            turn_ext_server: this.turnExtServer,
            registration_method: this.registrationMethod,
            allowed_domains: this.allowedDomains,
            enable_recording: this.isRecordingEnabled,
            remove_old_recording: this.isRemoveOldRecordingEnabled,
            recording_max_age_days: Number(this.recordingMaxAgeDays),
            sounds_language: this.soundsLanguage,
            disable_sound_muted: this.isSoundMutedDisabled,
            disable_sound_alone: this.isSoundAloneDisabled,
            welcome_message: this.welcomeMessage,
            welcome_footer: this.welcomeFooter,
          },
          extra: {
            title: this.$t("settings.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("settings.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    validateCreateAdmin() {
      this.clearErrors(this);
      let ok = true;
      const fail = (field, message) => {
        this.error[field] = message;
        if (ok) this.focusElement(field);
        ok = false;
      };
      if (!this.admin.name) fail("admin_name", "common.required");
      if (!this.admin.email) fail("admin_email", "common.required");
      if (!this.admin.password) fail("admin_password", "common.required");
      else if (this.admin.password.length < 8)
        fail("admin_password", "settings.password_too_short");
      return ok;
    },
    async createAdmin() {
      if (!this.validateCreateAdmin()) return;
      this.adminCreated = "";
      this.loading.createAdmin = true;
      const taskAction = "create-admin";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.createAdminAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.createAdminValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.createAdminCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            name: this.admin.name,
            email: this.admin.email,
            password: this.admin.password,
          },
          extra: {
            title: this.$t("settings.create_admin"),
            eventId,
          },
        })
      );
      if (res[0]) {
        this.error.createAdmin = this.getErrorMessage(res[0]);
        this.loading.createAdmin = false;
      }
    },
    createAdminAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.createAdmin = this.$t("error.generic_error");
      this.loading.createAdmin = false;
    },
    createAdminValidationFailed(validationErrors) {
      this.loading.createAdmin = false;
      for (const e of validationErrors) {
        this.error.createAdmin = this.$t("settings." + e.error);
      }
    },
    createAdminCompleted(taskContext, taskResult) {
      this.loading.createAdmin = false;
      this.adminCreated = taskResult.output.email;
      // Never leave the password sitting in the page after it has been used.
      this.admin = { name: "", email: "", password: "" };
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;
      this.getConfiguration();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";
.mg-bottom {
  margin-bottom: $spacing-06;
}

.subtle {
  color: $text-02;
  margin-bottom: $spacing-05;
}

.maxwidth {
  max-width: 38rem;
}
</style>

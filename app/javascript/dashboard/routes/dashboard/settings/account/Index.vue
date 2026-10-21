<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import WorkspaceCover from 'next/workspace/WorkspaceCover.vue';
import WorkspaceAvatar from 'next/workspace/WorkspaceAvatar.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import WorkspaceIdentity from './components/WorkspaceIdentity.vue';

const { t, locale: i18nLocale } = useI18n();
const store = useStore();
const { uiSettings } = useUISettings();
const { enabledLanguages } = useConfig();
const { accountId, currentAccount } = useAccount();

const uiFlags = useMapGetter('accounts/getUIFlags');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');
const userAccounts = useMapGetter('getUserAccounts');
const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');
const labels = useMapGetter('labels/getLabels');

const form = reactive({
  name: '',
  locale: 'en',
  domain: '',
  supportEmail: '',
});
const features = ref({});
const activeSection = ref('general');

const v$ = useVuelidate({ name: { required }, locale: { required } }, form);

const isUpdating = computed(() => uiFlags.value.isUpdating);
const showAudioTranscriptionConfig = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.CAPTAIN)
);
const featureInboundEmailEnabled = computed(
  () => !!features.value?.inbound_emails
);
const featureCustomReplyDomainEnabled = computed(
  () => featureInboundEmailEnabled.value && !!features.value.custom_reply_domain
);
const featureCustomReplyEmailEnabled = computed(
  () => featureInboundEmailEnabled.value && !!features.value.custom_reply_email
);
const languagesSortedByCode = computed(() =>
  [...enabledLanguages].sort((l1, l2) =>
    l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
  )
);

// The switcher's entry carries the vertical name and the role of this user.
const membership = computed(
  () => userAccounts.value.find(item => item.id === accountId.value) || {}
);
const workspace = computed(() => ({
  name: currentAccount.value.name,
  cover_theme: currentAccount.value.settings?.cover_theme,
  cover_url: currentAccount.value.cover_url,
  logo_url: currentAccount.value.logo_url,
}));
const createdAt = computed(() =>
  currentAccount.value.created_at
    ? new Date(currentAccount.value.created_at).toLocaleDateString(
        i18nLocale.value.replace('_', '-'),
        { day: '2-digit', month: 'short', year: 'numeric' }
      )
    : ''
);

const stats = computed(() => [
  {
    key: 'agents',
    icon: 'i-lucide-users',
    tone: 'bg-n-teal-3 text-n-teal-11',
    label: t('ACCOUNT_PAGE.STATS.AGENTS'),
    value: agents.value.length,
  },
  {
    key: 'inboxes',
    icon: 'i-lucide-inbox',
    tone: 'bg-n-iris-3 text-n-iris-11',
    label: t('ACCOUNT_PAGE.STATS.INBOXES'),
    value: inboxes.value.length,
  },
  {
    key: 'teams',
    icon: 'i-lucide-users-round',
    tone: 'bg-n-amber-3 text-n-amber-11',
    label: t('ACCOUNT_PAGE.STATS.TEAMS'),
    value: teams.value.length,
  },
  {
    key: 'labels',
    icon: 'i-lucide-tags',
    tone: 'bg-n-ruby-3 text-n-ruby-11',
    label: t('ACCOUNT_PAGE.STATS.LABELS'),
    value: labels.value.length,
  },
]);

const sections = computed(() =>
  [
    {
      id: 'general',
      icon: 'i-lucide-settings-2',
      label: t('ACCOUNT_PAGE.NAV.GENERAL'),
    },
    {
      id: 'identity',
      icon: 'i-lucide-palette',
      label: t('ACCOUNT_PAGE.NAV.IDENTITY'),
    },
    showAudioTranscriptionConfig.value && {
      id: 'ai',
      icon: 'i-lucide-audio-lines',
      label: t('ACCOUNT_PAGE.NAV.AI'),
    },
    {
      id: 'integration',
      icon: 'i-lucide-code-xml',
      label: t('ACCOUNT_PAGE.NAV.INTEGRATION'),
    },
    isOnChatwootCloud.value && {
      id: 'danger',
      icon: 'i-lucide-triangle-alert',
      label: t('ACCOUNT_PAGE.NAV.DANGER'),
    },
  ].filter(Boolean)
);

const goToSection = id => {
  activeSection.value = id;
  document
    .getElementById(`account-section-${id}`)
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

const applyLocale = accountLocale => {
  const effectiveLocale = uiSettings.value?.locale || accountLocale;
  if (effectiveLocale) i18nLocale.value = effectiveLocale;
};

const initializeAccount = () => {
  const {
    name,
    locale,
    domain,
    support_email: supportEmail,
  } = currentAccount.value;
  applyLocale(locale);
  Object.assign(form, { name, locale, domain, supportEmail });
  features.value = currentAccount.value.features;
};

// On a page reload this view renders before App.vue has fetched the
// account, so the form fills in once the account arrives.
watch(
  () => currentAccount.value.id,
  id => {
    if (id) initializeAccount();
  },
  { immediate: true }
);

const updateAccount = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) {
    useAlert(t('GENERAL_SETTINGS.FORM.ERROR'));
    return;
  }
  try {
    await store.dispatch('accounts/update', {
      locale: form.locale,
      name: form.name,
      domain: form.domain,
      support_email: form.supportEmail,
    });
    applyLocale(form.locale);
    currentAccount.value.locale = form.locale;
    useAlert(t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.UPDATE.ERROR'));
  }
};

const copyAccountId = async () => {
  await copyTextToClipboard(String(accountId.value));
  useAlert(t('ACCOUNT_PAGE.ID_COPIED'));
};

// The sidebar loads inboxes, teams and labels; agents only some pages do.
onMounted(() => store.dispatch('agents/get'));

const SECTION_CARD =
  'scroll-mt-4 rounded-2xl border border-n-weak bg-n-solid-1 px-6 shadow-sm';
// The shared SectionLayout brings its own spacing and divider; inside a card
// the card provides both.
const SECTION_RESET = '!border-t-0 !pt-6 !pb-6';
</script>

<template>
  <div
    class="flex flex-col w-full max-w-4xl gap-5 pb-12 ltr:mr-auto rtl:ml-auto"
  >
    <header class="flex flex-wrap items-center justify-between gap-4">
      <div class="flex items-center min-w-0 gap-3">
        <span
          class="grid flex-shrink-0 shadow-md size-11 rounded-xl place-content-center bg-brand-gradient"
        >
          <Icon icon="i-lucide-building-2" class="size-5 text-[#06131C]" />
        </span>
        <div class="min-w-0">
          <h1 class="text-xl font-bold tracking-tight text-n-slate-12">
            {{ t('GENERAL_SETTINGS.TITLE') }}
          </h1>
          <p class="text-xs text-n-slate-11">
            {{
              createdAt
                ? t('ACCOUNT_PAGE.SUBTITLE_WITH_DATE', {
                    id: accountId,
                    date: createdAt,
                  })
                : t('ACCOUNT_PAGE.SUBTITLE', { id: accountId })
            }}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <NextButton
          faded
          slate
          sm
          icon="i-lucide-copy"
          :label="t('ACCOUNT_PAGE.COPY_ID')"
          @click="copyAccountId"
        />
        <NextButton
          sm
          icon="i-lucide-check"
          type="submit"
          form="account-general-form"
          :is-loading="isUpdating"
          :disabled="!currentAccount.id"
          :label="t('ACCOUNT_PAGE.SAVE')"
        />
      </div>
    </header>

    <woot-loading-state v-if="!currentAccount.id" />
    <template v-else>
      <div
        class="relative overflow-hidden border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
      >
        <WorkspaceCover :account="workspace" class="h-36" />
        <div class="flex flex-wrap items-end gap-4 px-6 pb-5">
          <WorkspaceAvatar
            :account="workspace"
            size="lg"
            class="-mt-8 shadow-md ring-4 ring-n-solid-1"
          />
          <div class="flex-1 min-w-0">
            <p
              class="text-lg font-semibold leading-6 break-words text-n-slate-12"
            >
              {{ currentAccount.name }}
            </p>
            <div class="flex flex-wrap items-center gap-1.5 mt-1.5">
              <span
                class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
              >
                <Icon icon="i-lucide-briefcase" class="size-3.5" />
                {{
                  membership.vertical_name ||
                  t('WORKSPACE_SETTINGS.VERTICAL.NONE')
                }}
              </span>
              <span
                class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
              >
                <Icon icon="i-lucide-languages" class="size-3.5" />
                {{ currentAccount.locale }}
              </span>
            </div>
          </div>
          <NextButton
            faded
            slate
            sm
            icon="i-lucide-palette"
            :label="t('ACCOUNT_PAGE.EDIT_IDENTITY')"
            @click="goToSection('identity')"
          />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <div
          v-for="stat in stats"
          :key="stat.key"
          class="flex items-center gap-3 px-4 py-3.5 border shadow-sm rounded-xl border-n-weak bg-n-solid-1"
        >
          <span
            class="grid flex-shrink-0 rounded-lg size-9 place-content-center"
            :class="stat.tone"
          >
            <Icon :icon="stat.icon" class="size-[1.125rem]" />
          </span>
          <div class="min-w-0">
            <p
              class="text-xxs font-semibold tracking-wider uppercase truncate text-n-slate-11"
            >
              {{ stat.label }}
            </p>
            <p class="text-lg font-bold leading-6 text-n-slate-12">
              {{ stat.value }}
            </p>
          </div>
        </div>
      </div>

      <nav
        class="sticky top-0 z-10 flex gap-1 p-1.5 overflow-x-auto border shadow-sm rounded-2xl border-n-weak bg-n-solid-1/90 backdrop-blur"
        :aria-label="t('ACCOUNT_PAGE.NAV.LABEL')"
      >
        <button
          v-for="section in sections"
          :key="section.id"
          type="button"
          class="inline-flex items-center flex-shrink-0 gap-1.5 px-3 h-8 rounded-xl text-sm font-medium transition-colors"
          :class="
            activeSection === section.id
              ? 'bg-brand-gradient-soft text-n-slate-12'
              : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
          "
          :aria-current="activeSection === section.id ? 'true' : undefined"
          @click="goToSection(section.id)"
        >
          <Icon :icon="section.icon" class="size-4" />
          {{ section.label }}
        </button>
      </nav>

      <section id="account-section-general" :class="SECTION_CARD" class="py-6">
        <header class="flex items-start gap-3 mb-5">
          <span
            class="grid flex-shrink-0 rounded-lg size-9 place-content-center bg-n-alpha-2 text-n-slate-11"
          >
            <Icon icon="i-lucide-settings-2" class="size-[1.125rem]" />
          </span>
          <div>
            <h2 class="text-heading-2 text-n-slate-12">
              {{ t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE') }}
            </h2>
            <p class="mt-1 text-body-main text-n-slate-11">
              {{ t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE') }}
            </p>
          </div>
        </header>
        <form
          id="account-general-form"
          class="grid gap-4 md:grid-cols-2"
          @submit.prevent="updateAccount"
        >
          <WithLabel
            name="account-name"
            :has-error="v$.name.$error"
            :label="t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="form.name"
              type="text"
              class="w-full"
              :placeholder="t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            name="site-language"
            :has-error="v$.locale.$error"
            :label="t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="form.locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            name="custom-domain"
            :label="t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="form.domain"
              type="text"
              class="w-full"
              :placeholder="t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}
              {{
                featureCustomReplyDomainEnabled &&
                t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            name="support-email"
            :label="t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="form.supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
        </form>
      </section>

      <section id="account-section-identity" :class="SECTION_CARD">
        <WorkspaceIdentity :class="SECTION_RESET" />
      </section>

      <section
        v-if="showAudioTranscriptionConfig"
        id="account-section-ai"
        :class="SECTION_CARD"
      >
        <AudioTranscription :class="SECTION_RESET" />
      </section>

      <section id="account-section-integration" :class="SECTION_CARD">
        <AccountId :class="SECTION_RESET" />
      </section>

      <section
        v-if="isOnChatwootCloud"
        id="account-section-danger"
        :class="SECTION_CARD"
        class="!border-n-ruby-6"
      >
        <AccountDelete :class="SECTION_RESET" />
      </section>

      <BuildInfo />
    </template>
  </div>
</template>

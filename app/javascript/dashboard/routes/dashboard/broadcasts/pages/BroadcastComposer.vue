<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { DirectUpload } from 'activestorage';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import BroadcastsAPI from 'dashboard/api/broadcasts';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import BroadcastProgressModal from '../components/BroadcastProgressModal.vue';

const props = defineProps({
  broadcastId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const labels = useMapGetter('labels/getLabels');
const funnels = useMapGetter('funnels/getFunnels');
const uiFlags = useMapGetter('broadcasts/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');
const contacts = useMapGetter('contacts/getContacts');
const contactsMeta = useMapGetter('contacts/getMeta');
const inboxes = useMapGetter('inboxes/getInboxes');

// A fresh, empty WAHA message block.
const emptyMessageBlock = () => ({
  text: '',
  attachment: null,
  attachment_name: '',
  caption: '',
});

const THROTTLE_DEFAULTS = {
  batch_min: 3,
  batch_max: 8,
  delay_min: 20,
  delay_max: 60,
  daily_cap: 500,
};

const broadcast = ref(null);

// Local editable form state — synced from the loaded broadcast.
const form = reactive({
  mode: 'waha',
  inbox_id: null,
  message: {
    messages: [
      { text: '', attachment: null, attachment_name: '', caption: '' },
    ],
    template: { name: '', language: 'pt_BR', namespace: '' },
  },
  audience: {
    contact_label_ids: [],
    conversation_label_ids: [],
    funnel_stage_ids: [],
    contact_ids: [],
    phone_numbers: [],
  },
  throttle: { ...THROTTLE_DEFAULTS },
  scheduled_at: '',
});

const audienceCount = ref(null);
const isPreviewing = ref(false);

// Media upload (WAHA mode) — tracks which message block is currently uploading.
const uploadingBlock = ref(null);

// Approved Meta templates (official mode), loaded per inbox.
const templates = ref([]);
const selectedTemplateKey = ref('');

// Manual contact selection + list import (audience builder).
const contactSearch = ref('');
const importText = ref('');

// Audience accordion: only one section open at a time, all closed initially.
const openSection = ref('');
// Lazy-load contacts the first time the Contacts section is opened.
const contactsLoaded = ref(false);

// --- Contacts picker (paged, alphabetical, infinite scroll) ---
// We accumulate pages into a local list so the picker keeps prior pages while
// scrolling. The store's `contacts/get` replaces and `contacts/search` requires
// a non-empty query, so the component owns the accumulated list and order.
const SORT_ATTR = 'name';
const CONTACTS_PER_PAGE = 15;
const SCROLL_THRESHOLD = 80;

const loadedContacts = ref([]);
const contactsPage = ref(1);
const isLoadingContacts = ref(false);
const hasMoreContacts = ref(true);

// Remembered labels for selected contacts so chips render across search pages.
const contactLabelMap = reactive({});

// Append a freshly fetched store page into the accumulator, de-duped by id.
const appendContactsPage = page => {
  const seen = new Set(loadedContacts.value.map(contact => contact.id));
  page.forEach(contact => {
    if (!seen.has(contact.id)) {
      seen.add(contact.id);
      loadedContacts.value.push(contact);
    }
  });
};

// Fetch the next page for the current query, honoring append vs reset.
const fetchContactsPage = async ({ reset = false } = {}) => {
  if (isLoadingContacts.value) return;
  if (!reset && !hasMoreContacts.value) return;
  isLoadingContacts.value = true;
  const page = reset ? 1 : contactsPage.value + 1;
  const query = contactSearch.value.trim();
  try {
    if (query) {
      await store.dispatch('contacts/search', {
        search: query,
        page,
        sortAttr: SORT_ATTR,
        append: page > 1,
      });
      // `search` meta carries an explicit has_more flag.
      hasMoreContacts.value = Boolean(contactsMeta.value?.hasMore);
    } else {
      // Blank query: the search endpoint rejects it, so page the index.
      await store.dispatch('contacts/get', { page, sortAttr: SORT_ATTR });
      // The index returns no has_more; a full page implies more may follow.
      hasMoreContacts.value =
        (contacts.value || []).length >= CONTACTS_PER_PAGE;
    }
    if (reset) loadedContacts.value = [];
    appendContactsPage(contacts.value || []);
    contactsPage.value = page;
  } finally {
    isLoadingContacts.value = false;
  }
};

// Reset to page 1 for the active query and load fresh.
const resetContactsPicker = () => {
  contactsPage.value = 1;
  hasMoreContacts.value = true;
  loadedContacts.value = [];
  fetchContactsPage({ reset: true });
};

// Infinite scroll: load the next page when nearing the bottom of the list.
const onContactsScroll = event => {
  const el = event.target;
  const nearBottom =
    el.scrollTop + el.clientHeight >= el.scrollHeight - SCROLL_THRESHOLD;
  if (nearBottom && hasMoreContacts.value && !isLoadingContacts.value) {
    fetchContactsPage();
  }
};

const toggleSection = key => {
  openSection.value = openSection.value === key ? '' : key;
  if (openSection.value === 'contacts' && !contactsLoaded.value) {
    contactsLoaded.value = true;
    resetContactsPicker();
  }
};

const status = computed(() => broadcast.value?.status || 'draft');

const statusTone = computed(
  () =>
    ({
      running: 'text-n-teal-11 bg-n-teal-3',
      scheduled: 'text-n-teal-11 bg-n-teal-3',
      draft: 'text-n-amber-11 bg-n-amber-3',
      completed: 'text-n-slate-11 bg-n-alpha-2',
      paused: 'text-n-ruby-11 bg-n-ruby-3',
    })[status.value] || 'text-n-slate-11 bg-n-alpha-2'
);

// Inboxes that can send in the current mode.
const availableInboxes = computed(() => {
  const list = inboxes.value || [];
  if (form.mode === 'official') {
    return list.filter(
      inbox =>
        inbox.channel_type === 'Channel::Whatsapp' &&
        inbox.provider === 'whatsapp_cloud'
    );
  }
  return list.filter(
    inbox =>
      inbox.channel_type === 'Channel::Api' ||
      (inbox.channel_type === 'Channel::Whatsapp' &&
        inbox.provider !== 'whatsapp_cloud')
  );
});

const inboxChannelHint = inbox =>
  inbox.channel_type === 'Channel::Api'
    ? t('BROADCAST.MODE.WAHA.BADGE')
    : t('BROADCAST.MODE.OFFICIAL.BADGE');

// At least one message part must carry content (WAHA) or a template (official).
const hasMessage = computed(() => {
  if (form.mode === 'official') return Boolean(form.message.template.name);
  return form.message.messages.some(block =>
    Boolean(block.text?.trim() || block.caption?.trim() || block.attachment)
  );
});

const canLaunch = computed(
  () =>
    ['draft', 'paused'].includes(status.value) &&
    Number(audienceCount.value) > 0 &&
    Boolean(form.inbox_id) &&
    hasMessage.value
);

const launchHint = computed(() => {
  if (!form.inbox_id) return t('BROADCAST.COMPOSER.LAUNCH_NEEDS_INBOX');
  if (!(Number(audienceCount.value) > 0))
    return t('BROADCAST.COMPOSER.LAUNCH_NEEDS_AUDIENCE');
  if (!hasMessage.value) return t('BROADCAST.COMPOSER.LAUNCH_NEEDS_MESSAGE');
  return '';
});

const isRunning = computed(() => status.value === 'running');

// Live dispatch progress popup — auto-opens after launch, reopenable later.
const isProgressOpen = ref(false);

// While running, refresh the inline right-rail stats so numbers aren't stale.
const STATS_REFRESH_INTERVAL = 5000;
let statsTimer = null;

const stopStatsRefresh = () => {
  if (statsTimer) {
    clearInterval(statsTimer);
    statsTimer = null;
  }
};

const refreshStats = async () => {
  try {
    const data = await store.dispatch('broadcasts/show', props.broadcastId);
    broadcast.value = data;
  } catch (error) {
    // Silent: a transient refresh failure shouldn't disrupt the composer.
  }
};

const startStatsRefresh = () => {
  stopStatsRefresh();
  statsTimer = setInterval(() => {
    if (status.value === 'running') refreshStats();
    else stopStatsRefresh();
  }, STATS_REFRESH_INTERVAL);
};

// Convert an ISO timestamp to the value a datetime-local input expects.
const toLocalInput = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60000).toISOString().slice(0, 16);
};

const hydrate = record => {
  broadcast.value = record;
  form.mode = record.mode || 'waha';
  form.inbox_id = record.inbox_id || null;
  const msg = record.message || {};
  // Hydrate the message sequence: prefer the new `messages` array; fall back to
  // a single block built from the legacy flat shape so old drafts still edit.
  if (Array.isArray(msg.messages) && msg.messages.length) {
    form.message.messages = msg.messages.map(part => ({
      text: part.text || '',
      attachment: part.attachment || null,
      attachment_name: part.attachment_name || '',
      caption: part.caption || '',
    }));
  } else {
    form.message.messages = [
      {
        text: msg.text || '',
        attachment: msg.attachment || null,
        attachment_name: msg.attachment_name || '',
        caption: msg.caption || '',
      },
    ];
  }
  form.message.template = {
    name: msg.template?.name || '',
    language: msg.template?.language || 'pt_BR',
    namespace: msg.template?.namespace || '',
  };
  const aud = record.audience || {};
  form.audience.contact_label_ids = aud.contact_label_ids || [];
  form.audience.conversation_label_ids = aud.conversation_label_ids || [];
  form.audience.funnel_stage_ids = aud.funnel_stage_ids || [];
  form.audience.contact_ids = aud.contact_ids || [];
  form.audience.phone_numbers = aud.phone_numbers || [];
  form.throttle = { ...THROTTLE_DEFAULTS, ...(record.throttle || {}) };
  form.scheduled_at = toLocalInput(record.scheduled_at);
  selectedTemplateKey.value = form.message.template.name
    ? `${form.message.template.name}::${form.message.template.language}`
    : '';
  importText.value = form.audience.phone_numbers.join('\n');
};

const toggleId = (list, id) => {
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

// --- WAHA message sequence (list of message blocks) ---
const addMessageBlock = () => {
  form.message.messages.push(emptyMessageBlock());
};

const removeMessageBlock = index => {
  form.message.messages.splice(index, 1);
  if (!form.message.messages.length) {
    form.message.messages.push(emptyMessageBlock());
  }
};

// --- WAHA media upload (reuses the account-scoped chatflow uploader) ---
const uploadMedia = (event, index) => {
  const file = event.target.files?.[0];
  if (!file) return;
  uploadingBlock.value = index;
  const upload = new DirectUpload(
    file,
    `/api/v1/accounts/${accountId.value}/chatflow_direct_uploads`,
    {
      directUploadWillCreateBlobWithXHR: xhr => {
        xhr.setRequestHeader(
          'api_access_token',
          currentUser.value.access_token
        );
      },
    }
  );
  upload.create((error, blob) => {
    uploadingBlock.value = null;
    if (error) {
      useAlert(t('BROADCAST.MESSAGE.MEDIA_UPLOAD_ERROR'));
      return;
    }
    const block = form.message.messages[index];
    if (!block) return;
    block.attachment = blob.signed_id;
    block.attachment_name = blob.filename;
  });
};

const clearMedia = index => {
  const block = form.message.messages[index];
  if (!block) return;
  block.attachment = null;
  block.attachment_name = '';
};

// --- Official template picker ---
const templateKey = template => `${template.name}::${template.language}`;

const loadTemplates = async () => {
  const inboxId = form.inbox_id;
  if (form.mode !== 'official' || !inboxId) {
    templates.value = [];
    return;
  }
  try {
    const { data } = await BroadcastsAPI.templates(inboxId);
    templates.value = data.templates || [];
  } catch (error) {
    templates.value = [];
    useAlert(error?.message || t('BROADCAST.MESSAGE.TEMPLATE_LOAD_ERROR'));
  }
};

onMounted(async () => {
  store.dispatch('labels/get');
  store.dispatch('funnels/get');
  store.dispatch('inboxes/get');
  try {
    const data = await store.dispatch('broadcasts/show', props.broadcastId);
    hydrate(data);
    await loadTemplates();
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.LOAD_ERROR'));
  }
});

const onTemplateSelect = () => {
  const template = templates.value.find(
    tpl => templateKey(tpl) === selectedTemplateKey.value
  );
  if (!template) return;
  form.message.template = {
    name: template.name,
    language: template.language,
    namespace: template.namespace || '',
  };
};

// Best-effort body preview from the template's components.
const templatePreview = computed(() => {
  const template = templates.value.find(
    tpl => templateKey(tpl) === selectedTemplateKey.value
  );
  const body = (template?.components || []).find(c => c.type === 'BODY');
  return body?.text || '';
});

// --- Manual contact selection (paged, alphabetical) ---
// The accumulated, name-ascending list rendered in the picker.
const contactResults = computed(() => loadedContacts.value);

// Contacts loaded so far in the picker (grows as the user scrolls).
const contactsTotal = computed(() => loadedContacts.value.length);

// True only for the very first page load / search; later pages show an inline
// "carregando…" row instead of replacing the whole list.
const isFetchingContacts = computed(
  () => isLoadingContacts.value && loadedContacts.value.length === 0
);

const rememberContact = contact => {
  contactLabelMap[contact.id] =
    contact.name || contact.phone_number || `#${contact.id}`;
};

const toggleContact = contact => {
  rememberContact(contact);
  toggleId(form.audience.contact_ids, contact.id);
};

// Removable chips, labelled from the remembered map.
const selectedContactChips = computed(() =>
  form.audience.contact_ids.map(id => ({
    id,
    label: contactLabelMap[id] || `#${id}`,
  }))
);

// Debounced search: reset to page 1 (non-append) and start over.
let searchTimer = null;
const onContactSearch = () => {
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = setTimeout(resetContactsPicker, 300);
};

// --- List import (paste / CSV / TXT) ---
const parsePhoneNumbers = raw => {
  const seen = new Set();
  return (raw || '')
    .split(/[\n,;]/)
    .map(entry => entry.trim().replace(/[^\d+]/g, ''))
    .map(entry => entry.replace(/(?!^)\+/g, ''))
    .filter(entry => {
      if (!entry || entry === '+') return false;
      if (seen.has(entry)) return false;
      seen.add(entry);
      return true;
    });
};

const applyImport = () => {
  form.audience.phone_numbers = parsePhoneNumbers(importText.value);
};

const importFromFile = event => {
  const file = event.target.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    importText.value = importText.value
      ? `${importText.value}\n${reader.result}`
      : String(reader.result);
    applyImport();
  };
  reader.readAsText(file);
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
};

const clearImport = () => {
  importText.value = '';
  form.audience.phone_numbers = [];
};

// A block contributes to the campaign if it has text, a caption, or media.
const isBlockFilled = block =>
  Boolean(block.text?.trim() || block.caption?.trim() || block.attachment);

const buildPayload = () => {
  const message =
    form.mode === 'waha'
      ? {
          messages: form.message.messages.filter(isBlockFilled).map(block => ({
            text: block.text,
            attachment: block.attachment,
            attachment_name: block.attachment_name,
            caption: block.caption,
          })),
        }
      : { template: { ...form.message.template } };
  return {
    id: props.broadcastId,
    mode: form.mode,
    inbox_id: form.inbox_id,
    message,
    audience: { ...form.audience },
    throttle: { ...form.throttle },
    scheduled_at: form.scheduled_at
      ? new Date(form.scheduled_at).toISOString()
      : null,
  };
};

const refreshAudience = async () => {
  isPreviewing.value = true;
  try {
    const { data } = await BroadcastsAPI.audiencePreview(props.broadcastId);
    audienceCount.value = data.count;
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.PREVIEW_ERROR'));
  } finally {
    isPreviewing.value = false;
  }
};

const save = async () => {
  try {
    const data = await store.dispatch('broadcasts/update', buildPayload());
    hydrate(data);
    useAlert(t('BROADCAST.COMPOSER.SAVED'));
    await refreshAudience();
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.SAVE_ERROR'));
  }
};

const launch = async () => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('BROADCAST.COMPOSER.LAUNCH_CONFIRM', { count: audienceCount.value })
    )
  )
    return;
  try {
    const data = await store.dispatch('broadcasts/launch', props.broadcastId);
    hydrate(data);
    useAlert(t('BROADCAST.COMPOSER.LAUNCHED'));
    // Surface the live dispatch progress popup right after launch.
    isProgressOpen.value = true;
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.LAUNCH_ERROR'));
  }
};

const pause = async () => {
  try {
    const data = await store.dispatch('broadcasts/pause', props.broadcastId);
    hydrate(data);
    useAlert(t('BROADCAST.COMPOSER.PAUSED'));
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.COMPOSER.PAUSE_ERROR'));
  }
};

const goBack = () => {
  router.push(accountScopedRoute('broadcasts_index'));
};

watch(
  () => form.mode,
  () => {
    audienceCount.value = null;
    // Drop the selected inbox when it no longer fits the active mode.
    if (
      form.inbox_id &&
      !availableInboxes.value.some(inbox => inbox.id === form.inbox_id)
    ) {
      form.inbox_id = null;
    }
    loadTemplates();
  }
);

watch(
  () => form.inbox_id,
  () => {
    loadTemplates();
  }
);

// Run the inline stats refresh only while the campaign is actively running.
watch(status, value => {
  if (value === 'running') startStatsRefresh();
  else stopStatsRefresh();
});

onBeforeUnmount(stopStatsRefresh);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-5 border-b border-n-weak shrink-0"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-arrow-left"
          @click="goBack"
        />
        <div class="flex flex-col gap-0.5 min-w-0">
          <h1 class="text-lg font-semibold text-n-slate-12 m-0 truncate">
            {{ broadcast?.name || t('BROADCAST.COMPOSER.TITLE') }}
          </h1>
          <span
            class="self-start px-2 py-0.5 rounded-full text-[11px] font-medium capitalize"
            :class="statusTone"
          >
            {{ t(`BROADCAST.STATUS.${status.toUpperCase()}`) }}
          </span>
        </div>
      </div>
    </header>

    <div
      class="flex-1 grid grid-cols-1 xl:grid-cols-[1fr_360px] overflow-hidden"
    >
      <!-- Left: config form -->
      <div class="overflow-auto px-8 py-6 flex flex-col gap-8">
        <!-- Mode -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.MODE_TITLE') }}
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <button
              v-for="m in ['waha', 'official']"
              :key="m"
              type="button"
              class="flex items-start gap-3 p-4 rounded-xl border text-left cursor-pointer transition-all"
              :class="
                form.mode === m
                  ? 'border-n-teal-8 bg-n-teal-3/50 ring-1 ring-n-teal-7/40'
                  : 'border-n-weak hover:border-n-slate-6'
              "
              @click="form.mode = m"
            >
              <span
                class="flex items-center justify-center size-9 rounded-lg shrink-0"
                :class="
                  form.mode === m
                    ? 'bg-n-teal-9 text-white'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                <Icon
                  :icon="
                    m === 'waha'
                      ? 'i-lucide-message-circle'
                      : 'i-lucide-badge-check'
                  "
                  class="size-4"
                />
              </span>
              <span class="flex flex-col gap-0.5 min-w-0">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t(`BROADCAST.MODE.${m.toUpperCase()}.LABEL`) }}
                </span>
                <span class="text-xs text-n-slate-11 leading-snug">
                  {{ t(`BROADCAST.MODE.${m.toUpperCase()}.HINT`) }}
                </span>
              </span>
            </button>
          </div>
        </section>

        <!-- Inbox -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.INBOX_TITLE') }}
          </h2>
          <select
            v-model="form.inbox_id"
            class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
          >
            <option :value="null" disabled>
              {{ t('BROADCAST.COMPOSER.INBOX_SELECT') }}
            </option>
            <option
              v-for="inbox in availableInboxes"
              :key="inbox.id"
              :value="inbox.id"
            >
              {{ `${inbox.name} · ${inboxChannelHint(inbox)}` }}
            </option>
          </select>
          <p
            v-if="!availableInboxes.length"
            class="text-[11px] text-n-amber-11 m-0"
          >
            {{ t('BROADCAST.COMPOSER.INBOX_EMPTY') }}
          </p>
        </section>

        <!-- Message -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.MESSAGE_TITLE') }}
          </h2>

          <template v-if="form.mode === 'waha'">
            <p class="text-[11px] text-n-slate-10 m-0 -mt-1">
              {{ t('BROADCAST.MESSAGE.SEQUENCE_HINT') }}
            </p>

            <!-- Message sequence: one bordered card per part, sent in order -->
            <div
              v-for="(block, index) in form.message.messages"
              :key="`msg-${index}`"
              class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-1"
            >
              <div class="flex items-center gap-2">
                <span
                  class="inline-flex items-center justify-center size-6 rounded-md bg-n-teal-3 text-[11px] font-semibold text-n-teal-11 tabular-nums shrink-0"
                >
                  {{ index + 1 }}
                </span>
                <span class="flex-1 text-xs font-medium text-n-slate-11">
                  {{ t('BROADCAST.MESSAGE.PART_LABEL', { index: index + 1 }) }}
                </span>
                <Button
                  v-if="form.message.messages.length > 1"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  icon="i-lucide-trash-2"
                  @click="removeMessageBlock(index)"
                />
              </div>

              <!-- With media: caption only (filename row + remove) -->
              <div
                v-if="block.attachment"
                class="flex flex-col rounded-xl border border-n-weak bg-n-alpha-1 overflow-hidden"
              >
                <div
                  class="flex items-center gap-2 px-3 py-2.5 border-b border-n-weak"
                >
                  <Icon
                    icon="i-lucide-paperclip"
                    class="size-4 text-n-teal-11 shrink-0"
                  />
                  <span class="flex-1 text-xs text-n-slate-12 truncate">
                    {{ block.attachment_name }}
                  </span>
                  <Button
                    variant="ghost"
                    color="ruby"
                    size="sm"
                    icon="i-lucide-x"
                    @click="clearMedia(index)"
                  />
                </div>
                <div class="flex flex-col gap-1.5 p-3">
                  <span class="text-[11px] font-medium text-n-slate-10">
                    {{ t('BROADCAST.MESSAGE.CAPTION') }}
                  </span>
                  <textarea
                    v-model="block.caption"
                    rows="2"
                    :placeholder="t('BROADCAST.MESSAGE.CAPTION_PLACEHOLDER')"
                    class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 resize-y"
                  />
                </div>
              </div>

              <!-- Without media: text + attach button -->
              <template v-else>
                <textarea
                  v-model="block.text"
                  rows="4"
                  :placeholder="t('BROADCAST.MESSAGE.TEXT_PLACEHOLDER')"
                  class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 resize-y"
                />
                <label
                  class="inline-flex self-start items-center gap-2 px-3 h-9 rounded-lg border border-dashed border-n-weak text-xs text-n-slate-11 cursor-pointer hover:border-n-teal-7 hover:text-n-teal-11 transition-colors"
                >
                  <Icon
                    :icon="
                      uploadingBlock === index
                        ? 'i-lucide-loader-circle'
                        : 'i-lucide-paperclip'
                    "
                    class="size-4"
                    :class="uploadingBlock === index ? 'animate-spin' : ''"
                  />
                  <span>
                    {{
                      uploadingBlock === index
                        ? t('BROADCAST.MESSAGE.MEDIA_UPLOADING')
                        : t('BROADCAST.MESSAGE.MEDIA_ATTACH')
                    }}
                  </span>
                  <input
                    type="file"
                    class="hidden"
                    accept="image/*,video/*,application/pdf,audio/*"
                    @change="uploadMedia($event, index)"
                  />
                </label>
              </template>
            </div>

            <button
              type="button"
              class="inline-flex self-start items-center gap-2 px-3 h-9 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 cursor-pointer hover:border-n-teal-7 hover:text-n-teal-11 transition-colors"
              @click="addMessageBlock"
            >
              <Icon icon="i-lucide-plus" class="size-4" />
              <span>{{ t('BROADCAST.MESSAGE.ADD_MESSAGE') }}</span>
            </button>
          </template>

          <template v-else>
            <label v-if="templates.length" class="flex flex-col gap-1.5">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('BROADCAST.MESSAGE.TEMPLATE') }}
              </span>
              <select
                v-model="selectedTemplateKey"
                class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 cursor-pointer"
                @change="onTemplateSelect"
              >
                <option value="" disabled>
                  {{ t('BROADCAST.MESSAGE.TEMPLATE_SELECT') }}
                </option>
                <option
                  v-for="tpl in templates"
                  :key="`${tpl.name}::${tpl.language}`"
                  :value="`${tpl.name}::${tpl.language}`"
                >
                  {{ tpl.name }} ({{ tpl.language }})
                </option>
              </select>
            </label>

            <div
              v-if="templatePreview"
              class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
            >
              <span class="text-[11px] font-medium text-n-slate-10">
                {{ t('BROADCAST.MESSAGE.TEMPLATE_PREVIEW') }}
              </span>
              <p class="text-xs text-n-slate-12 m-0 whitespace-pre-line">
                {{ templatePreview }}
              </p>
            </div>

            <p v-if="!templates.length" class="text-[11px] text-n-slate-10 m-0">
              {{
                form.inbox_id
                  ? t('BROADCAST.MESSAGE.TEMPLATE_EMPTY')
                  : t('BROADCAST.MESSAGE.TEMPLATE_NO_INBOX')
              }}
            </p>
          </template>
        </section>

        <!-- Audience -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.AUDIENCE_TITLE') }}
          </h2>

          <div
            class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 divide-y divide-n-weak overflow-hidden"
          >
            <!-- Contact labels -->
            <div class="flex flex-col">
              <button
                type="button"
                class="flex items-center gap-2.5 px-4 py-3 cursor-pointer transition-colors hover:bg-n-alpha-1"
                @click="toggleSection('contactLabels')"
              >
                <Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 text-n-slate-11 transition-transform"
                  :class="openSection === 'contactLabels' ? 'rotate-180' : ''"
                />
                <span
                  class="flex-1 text-left text-sm font-medium text-n-slate-12"
                >
                  {{ t('BROADCAST.AUDIENCE.CONTACT_LABELS') }}
                </span>
                <span
                  v-if="form.audience.contact_label_ids.length"
                  class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-teal-3 text-[11px] font-semibold text-n-teal-11 tabular-nums"
                >
                  {{ form.audience.contact_label_ids.length }}
                </span>
              </button>
              <div v-if="openSection === 'contactLabels'" class="px-4 pb-4">
                <div v-if="labels.length" class="flex flex-wrap gap-2">
                  <button
                    v-for="label in labels"
                    :key="`cl-${label.id}`"
                    type="button"
                    class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium cursor-pointer transition-colors"
                    :class="
                      form.audience.contact_label_ids.includes(label.id)
                        ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                        : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
                    "
                    @click="toggleId(form.audience.contact_label_ids, label.id)"
                  >
                    <span
                      class="size-2 rounded-sm"
                      :style="{ backgroundColor: label.color }"
                    />
                    {{ label.title }}
                  </button>
                </div>
                <p v-else class="text-[11px] text-n-slate-10 m-0">
                  {{ t('BROADCAST.AUDIENCE.NO_LABELS') }}
                </p>
              </div>
            </div>

            <!-- Conversation labels -->
            <div class="flex flex-col">
              <button
                type="button"
                class="flex items-center gap-2.5 px-4 py-3 cursor-pointer transition-colors hover:bg-n-alpha-1"
                @click="toggleSection('conversationLabels')"
              >
                <Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 text-n-slate-11 transition-transform"
                  :class="
                    openSection === 'conversationLabels' ? 'rotate-180' : ''
                  "
                />
                <span
                  class="flex-1 text-left text-sm font-medium text-n-slate-12"
                >
                  {{ t('BROADCAST.AUDIENCE.CONVERSATION_LABELS') }}
                </span>
                <span
                  v-if="form.audience.conversation_label_ids.length"
                  class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-teal-3 text-[11px] font-semibold text-n-teal-11 tabular-nums"
                >
                  {{ form.audience.conversation_label_ids.length }}
                </span>
              </button>
              <div
                v-if="openSection === 'conversationLabels'"
                class="px-4 pb-4"
              >
                <div v-if="labels.length" class="flex flex-wrap gap-2">
                  <button
                    v-for="label in labels"
                    :key="`vl-${label.id}`"
                    type="button"
                    class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium cursor-pointer transition-colors"
                    :class="
                      form.audience.conversation_label_ids.includes(label.id)
                        ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                        : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
                    "
                    @click="
                      toggleId(form.audience.conversation_label_ids, label.id)
                    "
                  >
                    <span
                      class="size-2 rounded-sm"
                      :style="{ backgroundColor: label.color }"
                    />
                    {{ label.title }}
                  </button>
                </div>
                <p v-else class="text-[11px] text-n-slate-10 m-0">
                  {{ t('BROADCAST.AUDIENCE.NO_LABELS') }}
                </p>
              </div>
            </div>

            <!-- Kanban -->
            <div class="flex flex-col">
              <button
                type="button"
                class="flex items-center gap-2.5 px-4 py-3 cursor-pointer transition-colors hover:bg-n-alpha-1"
                @click="toggleSection('kanban')"
              >
                <Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 text-n-slate-11 transition-transform"
                  :class="openSection === 'kanban' ? 'rotate-180' : ''"
                />
                <span
                  class="flex-1 text-left text-sm font-medium text-n-slate-12"
                >
                  {{ t('BROADCAST.AUDIENCE.FUNNEL_STAGES') }}
                </span>
                <span
                  v-if="form.audience.funnel_stage_ids.length"
                  class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-teal-3 text-[11px] font-semibold text-n-teal-11 tabular-nums"
                >
                  {{ form.audience.funnel_stage_ids.length }}
                </span>
              </button>
              <div
                v-if="openSection === 'kanban'"
                class="flex flex-col gap-3 px-4 pb-4"
              >
                <div
                  v-for="funnel in funnels"
                  :key="funnel.id"
                  class="flex flex-col gap-2"
                >
                  <span
                    class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
                  >
                    {{ funnel.name }}
                  </span>
                  <div class="flex flex-wrap gap-2">
                    <button
                      v-for="stage in funnel.stages || []"
                      :key="`st-${funnel.id}-${stage.id}`"
                      type="button"
                      class="inline-flex items-center px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-colors"
                      :class="
                        form.audience.funnel_stage_ids.includes(stage.id)
                          ? 'bg-n-teal-9 text-white'
                          : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
                      "
                      @click="
                        toggleId(form.audience.funnel_stage_ids, stage.id)
                      "
                    >
                      {{ stage.name }}
                    </button>
                  </div>
                </div>
                <p
                  v-if="!funnels.length"
                  class="text-[11px] text-n-slate-10 m-0"
                >
                  {{ t('BROADCAST.AUDIENCE.NO_FUNNELS') }}
                </p>
              </div>
            </div>

            <!-- Contacts -->
            <div class="flex flex-col">
              <button
                type="button"
                class="flex items-center gap-2.5 px-4 py-3 cursor-pointer transition-colors hover:bg-n-alpha-1"
                @click="toggleSection('contacts')"
              >
                <Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 text-n-slate-11 transition-transform"
                  :class="openSection === 'contacts' ? 'rotate-180' : ''"
                />
                <span
                  class="flex-1 text-left text-sm font-medium text-n-slate-12"
                >
                  {{ t('BROADCAST.AUDIENCE.CONTACTS') }}
                </span>
                <span
                  v-if="form.audience.contact_ids.length"
                  class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-teal-3 text-[11px] font-semibold text-n-teal-11 tabular-nums"
                >
                  {{ form.audience.contact_ids.length }}
                </span>
              </button>
              <div
                v-if="openSection === 'contacts'"
                class="flex flex-col gap-2 px-4 pb-4"
              >
                <input
                  v-model="contactSearch"
                  type="text"
                  :placeholder="t('BROADCAST.AUDIENCE.CONTACTS_SEARCH')"
                  class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
                  @input="onContactSearch"
                />
                <p class="text-[11px] text-n-slate-10 m-0">
                  {{
                    t('BROADCAST.AUDIENCE.CONTACTS_LOADED', {
                      count: contactsTotal,
                    })
                  }}
                </p>
                <div
                  v-if="selectedContactChips.length"
                  class="flex flex-wrap gap-2"
                >
                  <span
                    v-for="chip in selectedContactChips"
                    :key="`sel-${chip.id}`"
                    class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border border-n-teal-8 bg-n-teal-3 text-xs font-medium text-n-teal-12"
                  >
                    {{ chip.label }}
                    <button
                      type="button"
                      class="cursor-pointer text-n-teal-11 hover:text-n-teal-12"
                      @click="toggleId(form.audience.contact_ids, chip.id)"
                    >
                      <Icon icon="i-lucide-x" class="size-3" />
                    </button>
                  </span>
                </div>
                <div
                  v-if="isFetchingContacts"
                  class="flex items-center gap-2 py-4 text-[11px] text-n-slate-10"
                >
                  <Icon
                    icon="i-lucide-loader-circle"
                    class="size-4 animate-spin"
                  />
                  <span>{{ t('BROADCAST.AUDIENCE.CONTACTS_LOADING') }}</span>
                </div>
                <div
                  v-else-if="contactResults.length"
                  class="flex flex-col max-h-56 overflow-auto rounded-xl bg-n-alpha-1 border border-n-weak divide-y divide-n-weak"
                  @scroll="onContactsScroll"
                >
                  <label
                    v-for="contact in contactResults"
                    :key="`ct-${contact.id}`"
                    class="flex items-center gap-2.5 px-3 py-2 cursor-pointer hover:bg-n-alpha-2 transition-colors"
                  >
                    <input
                      type="checkbox"
                      class="accent-n-teal-9 cursor-pointer"
                      :checked="form.audience.contact_ids.includes(contact.id)"
                      @change="toggleContact(contact)"
                    />
                    <Avatar
                      :name="contact.name || contact.phone_number || '#'"
                      :src="contact.thumbnail"
                      :size="28"
                      rounded-full
                    />
                    <span class="flex flex-col min-w-0">
                      <span class="text-sm text-n-slate-12 truncate">
                        {{ contact.name || contact.phone_number }}
                      </span>
                      <span
                        v-if="contact.phone_number && contact.name"
                        class="text-[11px] text-n-slate-10 truncate"
                      >
                        {{ contact.phone_number }}
                      </span>
                    </span>
                  </label>
                  <div
                    v-if="isLoadingContacts"
                    class="flex items-center gap-2 px-3 py-2.5 text-[11px] text-n-slate-10"
                  >
                    <Icon
                      icon="i-lucide-loader-circle"
                      class="size-4 animate-spin"
                    />
                    <span>{{ t('BROADCAST.AUDIENCE.CONTACTS_LOADING') }}</span>
                  </div>
                </div>
                <p v-else class="text-[11px] text-n-slate-10 m-0">
                  {{ t('BROADCAST.AUDIENCE.CONTACTS_EMPTY') }}
                </p>
              </div>
            </div>

            <!-- Import list -->
            <div class="flex flex-col">
              <button
                type="button"
                class="flex items-center gap-2.5 px-4 py-3 cursor-pointer transition-colors hover:bg-n-alpha-1"
                @click="toggleSection('import')"
              >
                <Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 text-n-slate-11 transition-transform"
                  :class="openSection === 'import' ? 'rotate-180' : ''"
                />
                <span
                  class="flex-1 text-left text-sm font-medium text-n-slate-12"
                >
                  {{ t('BROADCAST.AUDIENCE.IMPORT') }}
                </span>
                <span
                  v-if="form.audience.phone_numbers.length"
                  class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-teal-3 text-[11px] font-semibold text-n-teal-11 tabular-nums"
                >
                  {{ form.audience.phone_numbers.length }}
                </span>
              </button>
              <div
                v-if="openSection === 'import'"
                class="flex flex-col gap-2 px-4 pb-4"
              >
                <textarea
                  v-model="importText"
                  rows="4"
                  :placeholder="t('BROADCAST.AUDIENCE.IMPORT_PLACEHOLDER')"
                  class="px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 resize-y"
                  @input="applyImport"
                />
                <div class="flex items-center gap-3 flex-wrap">
                  <label
                    class="inline-flex items-center gap-2 px-3 h-9 rounded-lg border border-dashed border-n-weak text-xs text-n-slate-11 cursor-pointer hover:border-n-teal-7 hover:text-n-teal-11 transition-colors"
                  >
                    <Icon icon="i-lucide-file-up" class="size-4" />
                    <span>{{ t('BROADCAST.AUDIENCE.IMPORT_FILE') }}</span>
                    <input
                      type="file"
                      class="hidden"
                      accept=".csv,.txt"
                      @change="importFromFile"
                    />
                  </label>
                  <span
                    v-if="form.audience.phone_numbers.length"
                    class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-n-teal-3 text-xs font-medium text-n-teal-12"
                  >
                    {{
                      t('BROADCAST.AUDIENCE.IMPORT_COUNT', {
                        count: form.audience.phone_numbers.length,
                      })
                    }}
                  </span>
                  <button
                    v-if="form.audience.phone_numbers.length"
                    type="button"
                    class="text-xs text-n-ruby-11 cursor-pointer hover:underline"
                    @click="clearImport"
                  >
                    {{ t('BROADCAST.AUDIENCE.IMPORT_CLEAR') }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- Throttle -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.THROTTLE_TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11 m-0">
            {{ t('BROADCAST.THROTTLE.HINT') }}
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <label
              v-for="field in [
                'batch_min',
                'batch_max',
                'delay_min',
                'delay_max',
                'daily_cap',
              ]"
              :key="field"
              class="flex flex-col gap-1.5"
            >
              <span class="text-xs font-medium text-n-slate-11">
                {{ t(`BROADCAST.THROTTLE.${field.toUpperCase()}`) }}
              </span>
              <input
                v-model.number="form.throttle[field]"
                type="number"
                min="0"
                class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
              />
            </label>
          </div>
        </section>

        <!-- Schedule -->
        <section class="flex flex-col gap-3">
          <h2 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('BROADCAST.COMPOSER.SCHEDULE_TITLE') }}
          </h2>
          <label class="flex flex-col gap-1.5 max-w-xs">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('BROADCAST.SCHEDULE.AT') }}
            </span>
            <input
              v-model="form.scheduled_at"
              type="datetime-local"
              class="h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
            />
            <p class="text-[11px] text-n-slate-10 m-0">
              {{ t('BROADCAST.SCHEDULE.HINT') }}
            </p>
          </label>
        </section>
      </div>

      <!-- Right rail: audience + send controls -->
      <aside
        class="flex flex-col gap-4 px-6 py-6 border-t xl:border-t-0 xl:border-l border-n-weak bg-n-solid-1 overflow-auto"
      >
        <div
          class="flex flex-col gap-2 p-4 rounded-2xl bg-n-alpha-1 border border-n-weak"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('BROADCAST.COMPOSER.AUDIENCE_PREVIEW') }}
          </span>
          <div class="flex items-baseline gap-2">
            <span class="text-3xl font-semibold text-n-slate-12 tabular-nums">
              {{ audienceCount === null ? '—' : audienceCount }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t('BROADCAST.COMPOSER.CONTACTS') }}
            </span>
          </div>
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-refresh-cw"
            :label="t('BROADCAST.COMPOSER.REFRESH_AUDIENCE')"
            :is-loading="isPreviewing"
            @click="refreshAudience"
          />
        </div>

        <div v-if="broadcast" class="grid grid-cols-3 gap-2 text-center">
          <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-alpha-1">
            <span class="text-lg font-semibold text-n-slate-12 tabular-nums">
              {{ broadcast.recipients_count || 0 }}
            </span>
            <span class="text-[11px] text-n-slate-11">
              {{ t('BROADCAST.COMPOSER.STAT_TOTAL') }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-teal-3">
            <span class="text-lg font-semibold text-n-teal-11 tabular-nums">
              {{ broadcast.sent_count || 0 }}
            </span>
            <span class="text-[11px] text-n-teal-11">
              {{ t('BROADCAST.COMPOSER.STAT_SENT') }}
            </span>
          </div>
          <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-ruby-3">
            <span class="text-lg font-semibold text-n-ruby-11 tabular-nums">
              {{ broadcast.failed_count || 0 }}
            </span>
            <span class="text-[11px] text-n-ruby-11">
              {{ t('BROADCAST.COMPOSER.STAT_FAILED') }}
            </span>
          </div>
        </div>

        <div class="flex flex-col gap-2 mt-auto">
          <Button
            v-if="['running', 'paused'].includes(status)"
            class="w-full"
            variant="outline"
            color="teal"
            icon="i-lucide-activity"
            :label="t('BROADCAST.PROGRESS.OPEN')"
            @click="isProgressOpen = true"
          />
          <Button
            class="w-full"
            variant="outline"
            color="slate"
            icon="i-lucide-save"
            :label="t('BROADCAST.COMPOSER.SAVE')"
            :is-loading="uiFlags.isUpdating"
            @click="save"
          />
          <Button
            v-if="!isRunning"
            class="w-full"
            icon="i-lucide-send"
            :label="t('BROADCAST.COMPOSER.LAUNCH')"
            :disabled="!canLaunch"
            @click="launch"
          />
          <p
            v-if="!isRunning && launchHint"
            class="text-[11px] text-n-amber-11 text-center m-0"
          >
            {{ launchHint }}
          </p>
          <Button
            v-else
            class="w-full"
            color="ruby"
            icon="i-lucide-pause"
            :label="t('BROADCAST.COMPOSER.PAUSE')"
            @click="pause"
          />
        </div>
      </aside>
    </div>

    <BroadcastProgressModal
      :broadcast-id="Number(props.broadcastId)"
      :open="isProgressOpen"
      @close="isProgressOpen = false"
    />
  </div>
</template>

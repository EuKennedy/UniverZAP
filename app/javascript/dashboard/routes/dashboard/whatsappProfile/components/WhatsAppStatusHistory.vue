<script setup>
/**
 * O que foi escrito, o que está agendado e o que saiu em cada número.
 *
 * Cada linha mostra o resultado por conexão, porque publicar em três números
 * pode dar certo em dois e falhar no terceiro, e o operador precisa saber qual
 * reenviar. Enquanto algum status está saindo, a lista se atualiza sozinha.
 */
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';
import { apiErrorMessage } from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusPreview from './StatusPreview.vue';

const props = defineProps({
  // Muda quando o compositor grava algo, para a lista buscar de novo.
  refreshKey: { type: Number, default: 0 },
});

const emit = defineEmits(['edit']);

const { t } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.HISTORY.${key}`);

const POLL_MS = 5000;
const FILTERS = ['all', 'scheduled', 'draft', 'sent'];

const posts = ref([]);
const page = ref(1);
const hasMore = ref(false);
const isLoading = ref(false);
const loadError = ref('');
const busyId = ref(null);
const filter = ref('all');
const pendingPublish = ref(null);
const publishDialogRef = ref(null);
let pollTimer = null;

const STATUS_STYLE = {
  draft: 'bg-n-alpha-2 text-n-slate-11',
  scheduled: 'bg-n-blue-3 text-n-blue-11',
  publishing: 'bg-n-amber-3 text-n-amber-11',
  published: 'bg-n-teal-3 text-n-teal-11',
  partially_published: 'bg-n-amber-3 text-n-amber-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};

const DELIVERY_STYLE = {
  pending: 'i-lucide-loader-circle animate-spin text-n-amber-11',
  sent: 'i-lucide-circle-check text-n-teal-11',
  failed: 'i-lucide-circle-x text-n-ruby-11',
};

const SENT_STATUSES = [
  'publishing',
  'published',
  'partially_published',
  'failed',
];

const visiblePosts = computed(() => {
  if (filter.value === 'all') return posts.value;
  if (filter.value === 'sent') {
    return posts.value.filter(post => SENT_STATUSES.includes(post.status));
  }
  return posts.value.filter(post => post.status === filter.value);
});

const isEditable = post => ['draft', 'scheduled'].includes(post.status);
const hasFailures = post =>
  post.deliveries.some(delivery => delivery.status === 'failed');
const formatDate = value =>
  value
    ? new Date(value).toLocaleString([], {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';

const when = post => {
  if (post.status === 'scheduled')
    return t('WHATSAPP_PROFILE.HISTORY.SCHEDULED_FOR', {
      date: formatDate(post.scheduled_at),
    });
  if (post.published_at) return formatDate(post.published_at);
  return formatDate(post.created_at);
};

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

const fetchPosts = async ({ append = false } = {}) => {
  isLoading.value = !append && !posts.value.length;
  loadError.value = '';
  try {
    const { data } = await WhatsAppStatusAPI.list(append ? page.value + 1 : 1);
    if (append) page.value += 1;
    else page.value = 1;
    posts.value = append ? [...posts.value, ...data.payload] : data.payload;
    hasMore.value = data.meta?.has_more || false;
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
  } finally {
    isLoading.value = false;
  }
  stopPolling();
  if (posts.value.some(post => post.status === 'publishing')) {
    pollTimer = setTimeout(() => fetchPosts(), POLL_MS);
  }
};

const run = async (post, action, successKey) => {
  busyId.value = post.id;
  try {
    await action();
    useAlert(label(successKey));
    await fetchPosts();
  } catch (error) {
    useAlert(apiErrorMessage(error, t('WHATSAPP_PROFILE.ERRORS.GENERIC')));
  } finally {
    busyId.value = null;
  }
};

// Publicar daqui também é irreversível, então pergunta antes, como o
// compositor faz.
const askPublishNow = post => {
  pendingPublish.value = post;
  publishDialogRef.value?.open();
};

const publishNow = async () => {
  const post = pendingPublish.value;
  await run(post, () => WhatsAppStatusAPI.publishNow(post.id), 'PUBLISHING');
  publishDialogRef.value?.close();
  pendingPublish.value = null;
};
const retry = post =>
  run(post, () => WhatsAppStatusAPI.retry(post.id), 'RETRYING');
const remove = post =>
  run(
    post,
    () => WhatsAppStatusAPI.remove(post.id),
    post.status === 'scheduled' ? 'CANCELED' : 'DELETED'
  );

watch(
  () => props.refreshKey,
  () => fetchPosts()
);
onMounted(fetchPosts);
onBeforeUnmount(stopPolling);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-6 rounded-xl border border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap gap-3 justify-between items-center">
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-base font-medium text-n-slate-12">
          {{ label('TITLE') }}
        </h2>
        <p class="m-0 text-[13px] text-n-slate-11">
          {{ label('DESCRIPTION') }}
        </p>
      </div>
      <div class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1">
        <button
          v-for="option in FILTERS"
          :key="option"
          type="button"
          class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
          :class="
            filter === option
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :data-testid="`filter-${option}`"
          @click="filter = option"
        >
          {{ label(`FILTER.${option.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <Spinner :size="20" />
    </div>
    <p v-else-if="loadError" class="m-0 text-[13px] text-n-ruby-11">
      {{ loadError }}
    </p>
    <p
      v-else-if="!visiblePosts.length"
      class="py-6 m-0 text-[13px] text-center text-n-slate-11"
      data-testid="history-empty"
    >
      {{ label('EMPTY') }}
    </p>

    <ul
      v-else
      class="flex flex-col gap-0 p-0 m-0 list-none divide-y divide-n-weak"
    >
      <li
        v-for="post in visiblePosts"
        :key="post.id"
        class="flex gap-4 items-start py-4"
        data-testid="history-item"
      >
        <StatusPreview
          compact
          :kind="post.kind"
          :body="post.body || ''"
          :background-color="post.background_color || ''"
          :font="post.font"
          :media-url="post.media?.url || ''"
        />
        <div class="flex flex-col flex-1 gap-2 min-w-0">
          <div class="flex flex-wrap gap-2 items-center">
            <span
              class="px-2 py-0.5 text-[11px] font-medium rounded-md"
              :class="STATUS_STYLE[post.status]"
              data-testid="history-status"
            >
              {{ label(`STATUS.${post.status.toUpperCase()}`) }}
            </span>
            <span class="text-[12px] text-n-slate-11">{{ when(post) }}</span>
          </div>
          <p class="m-0 text-[13px] text-n-slate-12 line-clamp-2 break-words">
            {{ post.body || label(`NO_TEXT.${post.kind.toUpperCase()}`) }}
          </p>
          <ul
            v-if="post.deliveries.length"
            class="flex flex-col gap-1 p-0 m-0 list-none"
          >
            <li
              v-for="delivery in post.deliveries"
              :key="delivery.id"
              class="flex gap-1.5 items-start text-[12px] text-n-slate-11"
              data-testid="history-delivery"
            >
              <span
                class="mt-0.5 size-3.5 shrink-0"
                :class="DELIVERY_STYLE[delivery.status]"
              />
              <span class="font-medium text-n-slate-12">{{
                delivery.inbox_name
              }}</span>
              <span
                v-if="delivery.error_message"
                class="text-n-ruby-11 break-words"
              >
                {{ delivery.error_message }}
              </span>
            </li>
          </ul>
        </div>
        <div class="flex flex-wrap gap-1 justify-end shrink-0">
          <Button
            v-if="hasFailures(post) && post.status !== 'publishing'"
            size="xs"
            slate
            faded
            icon="i-lucide-rotate-cw"
            :label="label('RETRY')"
            :is-loading="busyId === post.id"
            data-testid="history-retry"
            @click="retry(post)"
          />
          <template v-if="isEditable(post)">
            <Button
              size="xs"
              slate
              faded
              icon="i-lucide-pencil"
              :label="label('EDIT')"
              @click="emit('edit', post)"
            />
            <Button
              size="xs"
              slate
              faded
              icon="i-lucide-send"
              :label="label('PUBLISH_NOW')"
              :is-loading="busyId === post.id"
              data-testid="history-publish"
              @click="askPublishNow(post)"
            />
            <Button
              size="xs"
              ghost
              ruby
              icon="i-lucide-trash-2"
              :label="
                post.status === 'scheduled' ? label('CANCEL') : label('DELETE')
              "
              data-testid="history-remove"
              @click="remove(post)"
            />
          </template>
        </div>
      </li>
    </ul>

    <Button
      v-if="hasMore"
      ghost
      slate
      size="sm"
      class="self-center"
      :label="label('LOAD_MORE')"
      @click="fetchPosts({ append: true })"
    />

    <Dialog
      ref="publishDialogRef"
      type="alert"
      width="md"
      :title="t('WHATSAPP_PROFILE.STATUS.CONFIRM.TITLE')"
      :description="t('WHATSAPP_PROFILE.STATUS.CONFIRM.DESCRIPTION')"
      :confirm-button-label="t('WHATSAPP_PROFILE.STATUS.CONFIRM.CONFIRM')"
      :cancel-button-label="t('WHATSAPP_PROFILE.STATUS.CONFIRM.CANCEL')"
      :is-loading="busyId === pendingPublish?.id"
      @confirm="publishNow"
    >
      <div v-if="pendingPublish" class="flex gap-4 items-start">
        <StatusPreview
          class="!w-32"
          :kind="pendingPublish.kind"
          :body="pendingPublish.body || ''"
          :background-color="pendingPublish.background_color || ''"
          :font="pendingPublish.font"
          :media-url="pendingPublish.media?.url || ''"
        />
        <p class="m-0 text-[13px] text-n-slate-11">
          {{ label('PUBLISH_TARGETS') }}
        </p>
      </div>
    </Dialog>
  </section>
</template>

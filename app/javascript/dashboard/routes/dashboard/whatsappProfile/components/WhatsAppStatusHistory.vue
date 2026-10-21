<script setup>
/**
 * O que foi escrito, o que está agendado e o que saiu em cada número.
 *
 * Cada linha mostra o resultado por conexão, porque publicar em três números
 * pode dar certo em dois e falhar no terceiro, e o operador precisa saber qual
 * reenviar. Busca e filtros rodam no servidor, para valer sobre o histórico
 * inteiro e não só a página aberta. Enquanto algum status está saindo, a lista
 * se atualiza sozinha.
 */
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

import { useAlert } from 'dashboard/composables';
import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';
import { apiErrorMessage, dateLocale } from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusAgenda from './StatusAgenda.vue';
import StatusPreview from './StatusPreview.vue';

const props = defineProps({
  // Muda quando o compositor grava algo, para a lista buscar de novo.
  refreshKey: { type: Number, default: 0 },
  inboxes: { type: Array, default: () => [] },
});

const emit = defineEmits(['edit', 'create', 'changed']);

const { t, locale } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.HISTORY.${key}`);

const POLL_MS = 5000;
const PER_PAGE = 10;
const STATUS_FILTERS = ['', 'scheduled', 'draft', 'sent', 'failed'];
const KIND_FILTERS = ['', 'text', 'image', 'video'];
const VIEWS = [
  { value: 'list', icon: 'i-lucide-list' },
  { value: 'agenda', icon: 'i-lucide-calendar-days' },
];

const posts = ref([]);
const meta = ref({ total_count: 0, total_pages: 1, current_page: 1 });
const page = ref(1);
const isLoading = ref(false);
const loadError = ref('');
const busyId = ref(null);
const pendingPublish = ref(null);
const publishDialogRef = ref(null);
const search = ref('');
const statusFilter = ref('');
const kindFilter = ref('');
const inboxFilter = ref('');
const view = ref('list');
const agendaKey = ref(0);
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

const statusOptions = computed(() =>
  STATUS_FILTERS.map(value => ({
    value,
    label: label(`FILTER.${(value || 'all').toUpperCase()}`),
  }))
);
const kindOptions = computed(() =>
  KIND_FILTERS.map(value => ({
    value,
    label: value
      ? t(`WHATSAPP_PROFILE.STATUS.KIND.${value.toUpperCase()}`)
      : label('FILTER.ALL_KINDS'),
  }))
);
const inboxOptions = computed(() => [
  { value: '', label: label('FILTER.ALL_CONNECTIONS') },
  ...props.inboxes.map(inbox => ({ value: inbox.id, label: inbox.name })),
]);

const hasFilters = computed(
  () =>
    Boolean(search.value.trim()) ||
    Boolean(statusFilter.value) ||
    Boolean(kindFilter.value) ||
    Boolean(inboxFilter.value)
);

const pageNumbers = computed(() => {
  const total = meta.value.total_pages || 1;
  const current = page.value;
  let start = Math.max(1, current - 2);
  const end = Math.min(total, start + 4);
  start = Math.max(1, end - 4);
  return Array.from({ length: end - start + 1 }, (_, index) => start + index);
});

const rangeLabel = computed(() => {
  const total = meta.value.total_count || 0;
  if (!total) return '';
  const first = (page.value - 1) * PER_PAGE + 1;
  const last = Math.min(page.value * PER_PAGE, total);
  return t('WHATSAPP_PROFILE.HISTORY.RANGE', { first, last, total });
});

const isEditable = post => ['draft', 'scheduled'].includes(post.status);
const hasFailures = post =>
  post.deliveries.some(delivery => delivery.status === 'failed');
const formatDate = value =>
  value
    ? new Date(value).toLocaleString(dateLocale(locale), {
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

const fetchPosts = async () => {
  isLoading.value = !posts.value.length;
  loadError.value = '';
  try {
    const { data } = await WhatsAppStatusAPI.list({
      page: page.value,
      per: PER_PAGE,
      q: search.value.trim() || undefined,
      status: statusFilter.value || undefined,
      kind: kindFilter.value || undefined,
      inboxId: inboxFilter.value || undefined,
    });
    posts.value = data.payload || [];
    meta.value = { ...meta.value, ...(data.meta || {}) };
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
    pollTimer = setTimeout(() => {
      fetchPosts();
      emit('changed');
    }, POLL_MS);
  }
};

const goToPage = next => {
  page.value = next;
  fetchPosts();
};

const refilter = () => {
  page.value = 1;
  fetchPosts();
};

const debouncedSearch = useDebounceFn(refilter, 300);

const clearFilters = () => {
  search.value = '';
  statusFilter.value = '';
  kindFilter.value = '';
  inboxFilter.value = '';
  refilter();
};

const run = async (post, action, successKey) => {
  busyId.value = post.id;
  try {
    const result = await action();
    useAlert(label(successKey));
    await fetchPosts();
    agendaKey.value += 1;
    emit('changed');
    return result;
  } catch (error) {
    useAlert(apiErrorMessage(error, t('WHATSAPP_PROFILE.ERRORS.GENERIC')));
    return null;
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

// Duplicar abre a cópia direto no compositor: quem duplica quer mudar algo
// (a data, a conexão, uma palavra) antes de mandar de novo.
const duplicate = async post => {
  const result = await run(
    post,
    () => WhatsAppStatusAPI.duplicate(post.id),
    'DUPLICATED'
  );
  if (result?.data) emit('edit', result.data);
};

watch(
  () => props.refreshKey,
  () => {
    fetchPosts();
    agendaKey.value += 1;
  }
);
watch(search, debouncedSearch);
watch([statusFilter, kindFilter, inboxFilter], refilter);
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
          v-for="option in VIEWS"
          :key="option.value"
          type="button"
          class="flex gap-1.5 items-center px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
          :class="
            view === option.value
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :data-testid="`view-${option.value}`"
          @click="view = option.value"
        >
          <span class="size-3.5" :class="option.icon" />
          {{ label(`VIEW.${option.value.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <template v-if="view === 'agenda'">
      <StatusAgenda
        :refresh-key="agendaKey"
        :inbox-id="inboxFilter ? Number(inboxFilter) : null"
        @edit="post => emit('edit', post)"
      />
    </template>

    <template v-else>
      <div
        class="flex flex-wrap gap-2 items-center p-2.5 rounded-xl border border-n-weak bg-n-alpha-1"
        data-testid="history-toolbar"
      >
        <label class="block relative flex-1 m-0 min-w-40 max-w-72">
          <span
            class="absolute left-2.5 top-1/2 z-10 -translate-y-1/2 pointer-events-none i-lucide-search size-4 text-n-slate-10"
          />
          <input
            v-model="search"
            type="search"
            class="!mb-0 !pl-8 !pr-2.5 w-full !h-9 text-sm rounded-lg border-0 outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
            :placeholder="label('SEARCH')"
            :aria-label="label('SEARCH')"
            data-testid="history-search"
          />
        </label>
        <Select
          v-model="statusFilter"
          :options="statusOptions"
          :aria-label="label('FILTER_STATUS')"
          data-testid="filter-status"
        />
        <Select
          v-model="kindFilter"
          :options="kindOptions"
          :aria-label="label('FILTER_KIND')"
          data-testid="filter-kind"
        />
        <Select
          v-if="inboxes.length > 1"
          v-model="inboxFilter"
          :options="inboxOptions"
          :aria-label="label('FILTER_CONNECTION')"
          data-testid="filter-connection"
        />
        <Button
          v-if="hasFilters"
          ghost
          slate
          size="xs"
          icon="i-lucide-x"
          :label="label('CLEAR_FILTERS')"
          data-testid="clear-filters"
          @click="clearFilters"
        />
        <span class="ms-auto text-[12px] text-n-slate-11">
          {{
            t(
              'WHATSAPP_PROFILE.HISTORY.COUNT',
              { count: meta.total_count || 0 },
              meta.total_count || 0
            )
          }}
        </span>
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner :size="20" />
      </div>
      <p v-else-if="loadError" class="m-0 text-[13px] text-n-ruby-11">
        {{ loadError }}
      </p>

      <!-- Vazio de verdade e vazio por filtro pedem ações diferentes: um
        convida a escrever o primeiro status, o outro a limpar a busca. -->
      <div
        v-else-if="!posts.length"
        class="flex flex-col gap-3 items-center px-6 py-10 text-center"
        data-testid="history-empty"
      >
        <span
          class="flex justify-center items-center rounded-2xl size-14 bg-brand-gradient-soft text-n-slate-12"
        >
          <span
            class="size-6"
            :class="hasFilters ? 'i-lucide-search-x' : 'i-lucide-sparkles'"
          />
        </span>
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{ hasFilters ? label('EMPTY_FILTERED') : label('EMPTY_TITLE') }}
        </p>
        <p class="m-0 max-w-sm text-[13px] text-n-slate-11">
          {{ hasFilters ? label('EMPTY_FILTERED_HINT') : label('EMPTY') }}
        </p>
        <Button
          v-if="hasFilters"
          slate
          faded
          size="sm"
          :label="label('CLEAR_FILTERS')"
          @click="clearFilters"
        />
        <Button
          v-else
          size="sm"
          icon="i-lucide-plus"
          :label="label('CREATE_FIRST')"
          data-testid="create-first"
          @click="emit('create')"
        />
      </div>

      <ul
        v-else
        class="flex flex-col gap-0 p-0 m-0 list-none divide-y divide-n-weak"
      >
        <li
          v-for="post in posts"
          :key="post.id"
          class="flex flex-wrap gap-4 items-start py-4 sm:flex-nowrap"
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
              <span
                v-if="post.recurrence && post.recurrence !== 'none'"
                class="flex gap-1 items-center px-2 py-0.5 text-[11px] font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
                data-testid="history-recurrence"
              >
                <span class="i-lucide-repeat size-3" />
                {{
                  t(
                    `WHATSAPP_PROFILE.STATUS.RECURRENCE.${post.recurrence.toUpperCase()}`
                  )
                }}
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
          <div class="flex flex-wrap gap-1 justify-end shrink-0 sm:max-w-64">
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
            </template>
            <Button
              size="xs"
              slate
              faded
              icon="i-lucide-copy"
              :label="label('DUPLICATE')"
              data-testid="history-duplicate"
              @click="duplicate(post)"
            />
            <Button
              v-if="isEditable(post)"
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
          </div>
        </li>
      </ul>

      <div
        v-if="meta.total_pages > 1"
        class="flex flex-wrap gap-3 justify-between items-center pt-3 border-t border-n-weak"
        data-testid="pagination"
      >
        <span class="text-[12px] text-n-slate-11">{{ rangeLabel }}</span>
        <div class="flex gap-1">
          <Button
            slate
            faded
            size="xs"
            icon="i-lucide-chevron-left"
            :disabled="page <= 1"
            :aria-label="label('PREVIOUS')"
            @click="goToPage(page - 1)"
          />
          <button
            v-for="number in pageNumbers"
            :key="number"
            type="button"
            class="px-2.5 h-6 text-[12px] font-medium rounded-md"
            :class="
              number === page
                ? 'bg-brand-gradient text-[#06131C]'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            :data-testid="`page-${number}`"
            @click="goToPage(number)"
          >
            {{ number }}
          </button>
          <Button
            slate
            faded
            size="xs"
            icon="i-lucide-chevron-right"
            :disabled="page >= meta.total_pages"
            :aria-label="label('NEXT')"
            @click="goToPage(page + 1)"
          />
        </div>
      </div>
    </template>

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

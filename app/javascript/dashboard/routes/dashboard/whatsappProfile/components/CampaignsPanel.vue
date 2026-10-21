<script setup>
/**
 * Campanhas de status organizadas em pastas. A barra lateral escolhe a pasta;
 * a área principal lista as campanhas daquela pasta ou abre o editor de uma
 * delas no lugar da lista, sem trocar de página.
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';

import CampaignsAPI from 'dashboard/api/whatsappStatusCampaigns';
import { backgroundClass, CAMPAIGN_STATUS_STYLE, dateLocale } from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignEditor from './CampaignEditor.vue';
import CampaignFolders from './CampaignFolders.vue';

const props = defineProps({
  inboxes: { type: Array, required: true },
  accountName: { type: String, default: '' },
});

const emit = defineEmits(['changed']);

const { t, locale } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.CAMPAIGNS.${key}`);

const STATUSES = ['', 'active', 'draft', 'paused', 'finished'];

const folderId = ref('');
const folders = ref([]);
const foldersKey = ref(0);
const campaigns = ref([]);
const isLoading = ref(false);
const search = ref('');
const statusFilter = ref('');
// null = lista; 'new' = campanha nova; número = editando.
const editing = ref(null);

const statusOptions = computed(() =>
  STATUSES.map(value => ({
    value,
    label: value
      ? t(`WHATSAPP_PROFILE.CAMPAIGNS.STATUS.${value.toUpperCase()}`)
      : label('ALL_STATUSES'),
  }))
);
const currentFolderName = computed(() => {
  if (folderId.value === '') return t('WHATSAPP_PROFILE.CAMPAIGNS.FOLDERS.ALL');
  if (folderId.value === 'none')
    return t('WHATSAPP_PROFILE.CAMPAIGNS.FOLDERS.UNFILED');
  return folders.value.find(folder => folder.id === folderId.value)?.name || '';
});

const connectionNames = campaign =>
  props.inboxes
    .filter(inbox => campaign.inbox_ids.includes(inbox.id))
    .map(inbox => inbox.name)
    .join(', ');

const formatNext = value =>
  new Date(value).toLocaleString(dateLocale(locale), {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const fetchCampaigns = async () => {
  isLoading.value = !campaigns.value.length;
  try {
    const { data } = await CampaignsAPI.list({
      folderId: folderId.value,
      status: statusFilter.value,
      q: search.value.trim(),
    });
    campaigns.value = data.payload || [];
  } catch {
    campaigns.value = [];
  } finally {
    isLoading.value = false;
  }
};

const debouncedFetch = useDebounceFn(fetchCampaigns, 300);

const onSaved = () => {
  foldersKey.value += 1;
  fetchCampaigns();
  emit('changed');
};

const closeEditor = () => {
  editing.value = null;
  fetchCampaigns();
};

watch([folderId, statusFilter], fetchCampaigns);
watch(search, debouncedFetch);
onMounted(fetchCampaigns);
</script>

<template>
  <div
    class="grid gap-6 items-start lg:grid-cols-[14rem_minmax(0,1fr)]"
    data-testid="campaigns-panel"
  >
    <aside
      class="p-3 rounded-xl border border-n-weak bg-n-solid-1 lg:sticky lg:top-4"
    >
      <CampaignFolders
        v-model="folderId"
        :refresh-key="foldersKey"
        @loaded="list => (folders = list)"
        @update:model-value="editing = null"
      />
    </aside>

    <CampaignEditor
      v-if="editing !== null"
      :campaign-id="editing === 'new' ? null : editing"
      :folders="folders"
      :default-folder-id="folderId"
      :inboxes="inboxes"
      :account-name="accountName"
      @close="closeEditor"
      @saved="onSaved"
    />

    <section
      v-else
      class="flex flex-col gap-4 p-5 rounded-xl border border-n-weak bg-n-solid-1"
    >
      <div class="flex flex-wrap gap-3 justify-between items-center">
        <div class="flex flex-col gap-0.5">
          <h2 class="m-0 text-base font-medium text-n-slate-12">
            {{ currentFolderName }}
          </h2>
          <p class="m-0 text-[13px] text-n-slate-11">
            {{ label('DESCRIPTION') }}
          </p>
        </div>
        <Button
          icon="i-lucide-plus"
          :label="label('NEW')"
          data-testid="campaign-new"
          @click="editing = 'new'"
        />
      </div>

      <div
        class="flex flex-wrap gap-2 items-center p-2.5 rounded-xl border border-n-weak bg-n-alpha-1"
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
            data-testid="campaign-search"
          />
        </label>
        <Select
          v-model="statusFilter"
          :options="statusOptions"
          data-testid="campaign-status-filter"
        />
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner :size="20" />
      </div>

      <div
        v-else-if="!campaigns.length"
        class="flex flex-col gap-3 items-center px-6 py-12 text-center"
        data-testid="campaigns-empty"
      >
        <span
          class="flex justify-center items-center rounded-2xl size-14 bg-brand-gradient-soft text-n-slate-12"
        >
          <span class="i-lucide-megaphone size-6" />
        </span>
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{ label('EMPTY_TITLE') }}
        </p>
        <p class="m-0 max-w-sm text-[13px] text-n-slate-11">
          {{ label('EMPTY') }}
        </p>
        <Button
          size="sm"
          icon="i-lucide-plus"
          :label="label('NEW')"
          @click="editing = 'new'"
        />
      </div>

      <div
        v-else
        class="grid gap-3 grid-cols-[repeat(auto-fill,minmax(16rem,1fr))]"
      >
        <button
          v-for="campaign in campaigns"
          :key="campaign.id"
          type="button"
          class="flex overflow-hidden flex-col text-start rounded-xl border transition-colors border-n-weak hover:border-n-slate-7 bg-n-solid-2"
          data-testid="campaign-card"
          @click="editing = campaign.id"
        >
          <span class="h-1.5" :class="backgroundClass(campaign.color)" />
          <span class="flex flex-col gap-2 p-4">
            <span class="flex gap-2 items-start">
              <span
                class="flex-1 text-sm font-semibold text-n-slate-12 line-clamp-2"
              >
                {{ campaign.name }}
              </span>
              <span
                class="px-2 py-0.5 text-[11px] font-medium rounded-md shrink-0"
                :class="CAMPAIGN_STATUS_STYLE[campaign.status]"
              >
                {{
                  t(
                    `WHATSAPP_PROFILE.CAMPAIGNS.STATUS.${campaign.status.toUpperCase()}`
                  )
                }}
              </span>
            </span>
            <span
              v-if="campaign.description"
              class="text-[12px] text-n-slate-11 line-clamp-2"
            >
              {{ campaign.description }}
            </span>
            <span
              class="flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-n-slate-11"
            >
              <span class="flex gap-1 items-center">
                <span class="i-lucide-list-ordered size-3" />
                {{
                  t(
                    'WHATSAPP_PROFILE.CAMPAIGNS.CARD.STEPS',
                    { count: campaign.steps_count },
                    campaign.steps_count
                  )
                }}
              </span>
              <span
                v-if="campaign.reposts_count"
                class="flex gap-1 items-center"
              >
                <span class="i-lucide-repeat-2 size-3" />
                {{
                  t('WHATSAPP_PROFILE.CAMPAIGNS.CARD.REPOSTS', {
                    count: campaign.reposts_count,
                  })
                }}
              </span>
              <span v-if="campaign.cycle_days" class="flex gap-1 items-center">
                <span class="i-lucide-refresh-cw size-3" />
                {{
                  t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.CYCLE_EVERY', {
                    days: campaign.cycle_days,
                  })
                }}
              </span>
              <span
                v-if="campaign.folder_name && folderId === ''"
                class="flex gap-1 items-center"
              >
                <span class="i-lucide-folder size-3" />
                {{ campaign.folder_name }}
              </span>
            </span>
            <span
              class="pt-2 text-[11px] border-t border-n-weak text-n-slate-10"
            >
              <template v-if="campaign.next_post_at">
                {{
                  t('WHATSAPP_PROFILE.CAMPAIGNS.CARD.NEXT', {
                    date: formatNext(campaign.next_post_at),
                  })
                }}
              </template>
              <template v-else>{{ label('CARD.NOTHING_SCHEDULED') }}</template>
              <template v-if="connectionNames(campaign)">
                · {{ connectionNames(campaign) }}
              </template>
            </span>
          </span>
        </button>
      </div>
    </section>
  </div>
</template>

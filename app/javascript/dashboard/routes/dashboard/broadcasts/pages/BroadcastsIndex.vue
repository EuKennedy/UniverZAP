<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const broadcasts = useMapGetter('broadcasts/getBroadcasts');
const uiFlags = useMapGetter('broadcasts/getUIFlags');

const isCreating = ref(false);
const newName = ref('');

const sortedBroadcasts = computed(() =>
  [...broadcasts.value].sort((a, b) => b.id - a.id)
);

const statusTone = status =>
  ({
    running: 'text-n-teal-11 bg-n-teal-3',
    scheduled: 'text-n-teal-11 bg-n-teal-3',
    draft: 'text-n-amber-11 bg-n-amber-3',
    completed: 'text-n-slate-11 bg-n-alpha-2',
    paused: 'text-n-ruby-11 bg-n-ruby-3',
  })[status] || 'text-n-slate-11 bg-n-alpha-2';

const modeTone = mode =>
  mode === 'official'
    ? 'text-n-slate-11 bg-n-alpha-2'
    : 'text-n-teal-11 bg-n-teal-3';

onMounted(() => {
  store.dispatch('broadcasts/get');
});

const openComposer = broadcast => {
  router.push(
    accountScopedRoute('broadcasts_show', { broadcastId: broadcast.id })
  );
};

const startCreate = () => {
  isCreating.value = true;
  newName.value = '';
};

const cancelCreate = () => {
  isCreating.value = false;
  newName.value = '';
};

const submitCreate = async () => {
  const name = newName.value.trim();
  if (!name) return;
  try {
    const created = await store.dispatch('broadcasts/create', {
      name,
      mode: 'waha',
    });
    cancelCreate();
    openComposer(created);
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.LIST.CREATE_ERROR'));
  }
};

const removeBroadcast = async (broadcast, event) => {
  event.stopPropagation();
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('BROADCAST.LIST.DELETE_CONFIRM', { name: broadcast.name })
    )
  )
    return;
  try {
    await store.dispatch('broadcasts/delete', broadcast.id);
    useAlert(t('BROADCAST.LIST.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('BROADCAST.LIST.DELETE_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-6 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12 m-0">
          {{ t('BROADCAST.LIST.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 m-0 max-w-2xl">
          {{ t('BROADCAST.LIST.SUBTITLE') }}
        </p>
      </div>
      <Button
        icon="i-lucide-plus"
        :label="t('BROADCAST.LIST.NEW')"
        @click="startCreate"
      />
    </header>

    <div class="flex-1 px-8 py-6">
      <form
        v-if="isCreating"
        class="flex items-center gap-2 mb-6 max-w-xl"
        @submit.prevent="submitCreate"
      >
        <input
          v-model="newName"
          v-focus
          type="text"
          :placeholder="t('BROADCAST.LIST.NAME_PLACEHOLDER')"
          class="flex-1 h-10 px-3 rounded-lg bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
        />
        <Button
          type="submit"
          :label="t('BROADCAST.LIST.CREATE')"
          :is-loading="uiFlags.isCreating"
        />
        <Button
          variant="ghost"
          color="slate"
          :label="t('BROADCAST.LIST.CANCEL')"
          @click="cancelCreate"
        />
      </form>

      <div
        v-if="!sortedBroadcasts.length && !uiFlags.isFetching"
        class="flex flex-col items-center justify-center gap-3 py-24 text-center"
      >
        <span
          class="flex items-center justify-center size-14 rounded-2xl bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-megaphone" class="size-7" />
        </span>
        <h3 class="text-base font-medium text-n-slate-12 m-0">
          {{ t('BROADCAST.LIST.EMPTY_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 m-0 max-w-md">
          {{ t('BROADCAST.LIST.EMPTY_BODY') }}
        </p>
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <button
          v-for="broadcast in sortedBroadcasts"
          :key="broadcast.id"
          type="button"
          class="group flex flex-col gap-3 p-5 text-left rounded-2xl bg-n-solid-1 border border-n-weak hover:border-n-teal-7 hover:shadow-lg transition-all cursor-pointer"
          @click="openComposer(broadcast)"
        >
          <div class="flex items-start justify-between gap-2">
            <span
              class="flex items-center justify-center size-10 rounded-xl bg-n-teal-3 text-n-teal-11 shrink-0"
            >
              <Icon icon="i-lucide-megaphone" class="size-5" />
            </span>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] font-medium capitalize"
              :class="statusTone(broadcast.status)"
            >
              {{ t(`BROADCAST.STATUS.${broadcast.status.toUpperCase()}`) }}
            </span>
          </div>
          <div class="flex flex-col gap-1 min-w-0">
            <h3 class="text-sm font-semibold text-n-slate-12 m-0 truncate">
              {{ broadcast.name }}
            </h3>
            <div class="flex items-center gap-2">
              <span
                class="px-2 py-0.5 rounded-full text-[11px] font-medium"
                :class="modeTone(broadcast.mode)"
              >
                {{ t(`BROADCAST.MODE.${broadcast.mode.toUpperCase()}.BADGE`) }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  t('BROADCAST.LIST.PROGRESS', {
                    sent: broadcast.sent_count || 0,
                    total: broadcast.recipients_count || 0,
                  })
                }}
              </span>
            </div>
          </div>
          <div class="flex items-center justify-end mt-1">
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="removeBroadcast(broadcast, $event)"
            />
          </div>
        </button>
      </div>
    </div>
  </div>
</template>

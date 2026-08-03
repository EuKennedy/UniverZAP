<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

import Button from 'dashboard/components-next/button/Button.vue';
import AthenasCreditsStrip from 'dashboard/components-next/athenas/AthenasCreditsStrip.vue';

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const assistants = ref([]);
const loading = ref(false);

const fetchAssistants = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAssistantsAPI.get();
    assistants.value = data?.payload || data || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || e.message);
  } finally {
    loading.value = false;
  }
};

const goToWizard = () => {
  router.push(accountScopedRoute('athenas_assistant_wizard'));
};

const openAssistant = id => {
  router.push(accountScopedRoute('athenas_assistant_edit', { id }));
};

const isEmpty = computed(() => !loading.value && !assistants.value.length);

onMounted(fetchAssistants);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-background">
    <header
      class="flex items-center justify-between flex-shrink-0 px-10 py-8 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1.5">
        <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.LIST.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 max-w-2xl leading-relaxed">
          {{ t('ATHENAS.LIST.SUBTITLE') }}
        </p>
      </div>
      <Button
        icon="i-lucide-sparkles"
        :label="t('ATHENAS.LIST.CREATE')"
        size="sm"
        data-onboarding="athenas-new-assistant"
        @click="goToWizard"
      />
    </header>

    <!-- Balance stays visible (a low balance must never be hidden) but no
         longer occupies the fold. Buying moves to the existing modal.
         Always rendered: it carries the onboarding tour anchor. -->
    <div class="px-10 pt-6">
      <AthenasCreditsStrip data-onboarding="athenas-billing-panel" />
    </div>

    <section v-if="loading" class="flex-1 flex items-center justify-center">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <section
      v-else-if="isEmpty"
      class="flex-1 flex flex-col items-center justify-center gap-5 px-8 text-center"
    >
      <div
        class="size-20 rounded-3xl bg-gradient-to-br from-n-brand/20 to-n-brand/[0.04] ring-1 ring-n-weak flex items-center justify-center"
      >
        <span class="i-lucide-brain-circuit size-9 text-n-brand" />
      </div>
      <div class="flex flex-col gap-2 max-w-md">
        <h2 class="text-xl font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.LIST.EMPTY_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11 leading-relaxed">
          {{ t('ATHENAS.LIST.EMPTY_DESCRIPTION') }}
        </p>
      </div>
      <Button
        icon="i-lucide-sparkles"
        :label="t('ATHENAS.LIST.CREATE_FIRST')"
        size="sm"
        @click="goToWizard"
      />
    </section>

    <section v-else class="px-10 py-8">
      <div
        class="grid gap-5 [grid-template-columns:repeat(auto-fill,minmax(320px,1fr))]"
      >
        <button
          v-for="assistant in assistants"
          :key="assistant.id"
          type="button"
          class="group relative flex flex-col gap-4 p-5 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak text-left transition-[transform,box-shadow,ring-color] duration-200 ease-out hover:ring-n-brand hover:-translate-y-0.5 hover:shadow-[0_10px_30px_-10px_rgba(0,0,0,0.25)]"
          @click="openAssistant(assistant.id)"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-3 min-w-0 flex-1">
              <span
                v-if="assistant.avatar_url"
                class="size-12 rounded-2xl bg-cover bg-center ring-1 ring-n-weak"
                :style="{ backgroundImage: `url(${assistant.avatar_url})` }"
              />
              <span
                v-else
                class="size-12 rounded-2xl bg-gradient-to-br from-n-brand to-n-teal-9 grid place-content-center"
              >
                <span class="i-lucide-bot size-6 text-white" />
              </span>
              <div class="flex flex-col gap-0.5 min-w-0">
                <h3
                  class="text-base font-semibold text-n-slate-12 truncate tracking-tight"
                >
                  {{ assistant.name }}
                </h3>
                <p class="text-[12px] text-n-slate-11 truncate">
                  {{ assistant.role }}
                </p>
              </div>
            </div>
            <span
              v-if="assistant.autopilot_enabled"
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[10px] uppercase font-bold tracking-wider bg-n-teal-3 text-n-teal-11 ring-1 ring-inset ring-n-teal-6"
            >
              <span class="i-lucide-zap size-2.5" />
              {{ t('ATHENAS.LIST.AUTOPILOT_BADGE') }}
            </span>
          </div>
          <p
            v-if="assistant.description"
            class="text-[13px] text-n-slate-11 line-clamp-3 leading-relaxed"
          >
            {{ assistant.description }}
          </p>
          <div
            class="flex items-center justify-between gap-4 mt-auto pt-3 border-t border-n-weak text-[11px] text-n-slate-11"
          >
            <span class="font-mono uppercase tracking-wide">
              {{ assistant.model }}
            </span>
            <span class="inline-flex items-center gap-3 tabular-nums">
              <span class="inline-flex items-center gap-1">
                <span class="i-lucide-book-open size-3" />
                {{ assistant.stats?.trainings_count ?? 0 }}
              </span>
              <span class="inline-flex items-center gap-1">
                <span class="i-lucide-zap size-3" />
                {{ assistant.stats?.intents_count ?? 0 }}
              </span>
            </span>
          </div>
        </button>
      </div>
    </section>
  </div>
</template>

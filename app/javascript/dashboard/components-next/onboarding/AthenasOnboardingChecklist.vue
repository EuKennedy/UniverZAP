<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAthenasAssistant } from 'dashboard/composables/useAthenasAssistant';
import Icon from 'next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId, currentAccount, updateAccount } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const { assistants, fetchAssistants } = useAthenasAssistant();

const isDismissed = ref(false);

onMounted(() => {
  fetchAssistants();
});

const isExplicitlyDone = computed(
  () =>
    currentAccount.value?.custom_attributes?.athenas_onboarding_done === true
);

const isExplicitlyDismissed = computed(
  () =>
    currentAccount.value?.custom_attributes?.athenas_onboarding_dismissed ===
    true
);

const hasCustomAssistant = computed(() => {
  if (!assistants.value.length) return false;
  return assistants.value.some(
    a =>
      a.system_prompt &&
      a.system_prompt.length > 0 &&
      !a.system_prompt.includes('Assistente padrão criado automaticamente')
  );
});

const hasInbox = computed(() => (inboxes.value || []).length > 0);

const hasTeam = computed(() => (agents.value || []).length > 1);

const goToAssistant = () => {
  const first = assistants.value[0];
  if (first) {
    router.push({
      name: 'athenas_assistant_edit',
      params: { accountId: accountId.value, id: first.id },
    });
  } else {
    router.push({
      name: 'athenas_assistant_wizard',
      params: { accountId: accountId.value },
    });
  }
};

const goToInbox = () => {
  router.push({
    name: 'settings_inbox_new',
    params: { accountId: accountId.value },
  });
};

const goToTeam = () => {
  router.push({
    name: 'agent_list',
    params: { accountId: accountId.value },
  });
};

const steps = computed(() => [
  {
    key: 'whatsapp',
    icon: 'i-lucide-message-circle',
    title: t('ATHENAS_ONBOARDING.STEPS.WHATSAPP.TITLE'),
    body: t('ATHENAS_ONBOARDING.STEPS.WHATSAPP.BODY'),
    cta: t('ATHENAS_ONBOARDING.STEPS.WHATSAPP.CTA'),
    done: hasInbox.value,
    onClick: () => goToInbox(),
  },
  {
    key: 'team',
    icon: 'i-lucide-users',
    title: t('ATHENAS_ONBOARDING.STEPS.TEAM.TITLE'),
    body: t('ATHENAS_ONBOARDING.STEPS.TEAM.BODY'),
    cta: t('ATHENAS_ONBOARDING.STEPS.TEAM.CTA'),
    done: hasTeam.value,
    onClick: () => goToTeam(),
  },
  {
    key: 'assistant',
    icon: 'i-lucide-sparkles',
    title: t('ATHENAS_ONBOARDING.STEPS.ASSISTANT.TITLE'),
    body: t('ATHENAS_ONBOARDING.STEPS.ASSISTANT.BODY'),
    cta: t('ATHENAS_ONBOARDING.STEPS.ASSISTANT.CTA'),
    done: hasCustomAssistant.value,
    onClick: () => goToAssistant(),
  },
]);

const progress = computed(() => {
  const total = steps.value.length;
  const done = steps.value.filter(s => s.done).length;
  return { total, done, percent: Math.round((done / total) * 100) };
});

const allDone = computed(() => progress.value.done === progress.value.total);

const isVisible = computed(() => {
  if (isDismissed.value) return false;
  if (isExplicitlyDismissed.value) return false;
  if (isExplicitlyDone.value) return false;
  return true;
});

const persistDismiss = async (markDone = false) => {
  isDismissed.value = true;
  try {
    await updateAccount({
      custom_attributes: {
        ...(currentAccount.value?.custom_attributes || {}),
        athenas_onboarding_dismissed: !markDone,
        athenas_onboarding_done: markDone,
      },
    });
  } catch {
    // best effort — banner still hides locally for the session
  }
};
</script>

<template>
  <div
    v-if="isVisible"
    class="relative rounded-xl border border-n-weak bg-n-surface-2 p-5 shadow-sm overflow-hidden"
  >
    <div class="flex items-start justify-between gap-4">
      <div class="flex items-start gap-3 min-w-0">
        <span
          class="inline-flex items-center justify-center size-10 rounded-full bg-n-teal-3"
        >
          <Icon icon="i-lucide-rocket" class="text-n-teal-11 size-5" />
        </span>
        <div class="flex flex-col min-w-0">
          <span class="text-base font-semibold text-n-slate-12">
            {{ t('ATHENAS_ONBOARDING.TITLE') }}
          </span>
          <span class="text-sm text-n-slate-11 mt-1">
            {{
              t('ATHENAS_ONBOARDING.SUBTITLE', {
                done: progress.done,
                total: progress.total,
              })
            }}
          </span>
        </div>
      </div>
      <Button slate ghost xs icon="i-lucide-x" @click="persistDismiss(false)" />
    </div>

    <div class="mt-3 h-1.5 w-full rounded-full bg-n-slate-3 overflow-hidden">
      <div
        class="h-full bg-n-teal-9 transition-all duration-500"
        :style="{ width: `${progress.percent}%` }"
      />
    </div>

    <ul class="mt-5 flex flex-col gap-3">
      <li
        v-for="step in steps"
        :key="step.key"
        class="flex items-center gap-3 rounded-lg border border-n-weak/60 bg-n-alpha-1/40 p-3 hover:bg-n-alpha-2 transition-colors"
      >
        <span
          class="inline-flex items-center justify-center size-8 rounded-full shrink-0"
          :class="
            step.done
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-slate-3 text-n-slate-11'
          "
        >
          <Icon
            :icon="step.done ? 'i-lucide-check' : step.icon"
            class="size-4"
          />
        </span>
        <div class="flex-1 min-w-0">
          <p
            class="text-sm font-medium text-n-slate-12 truncate"
            :class="{ 'line-through opacity-60': step.done }"
          >
            {{ step.title }}
          </p>
          <p class="text-xs text-n-slate-10 mt-0.5">{{ step.body }}</p>
        </div>
        <Button
          v-if="!step.done"
          :label="step.cta"
          teal
          sm
          @click="step.onClick"
        />
        <span
          v-else
          class="text-[11px] font-medium uppercase tracking-wide text-n-teal-11"
        >
          {{ t('ATHENAS_ONBOARDING.DONE_BADGE') }}
        </span>
      </li>
    </ul>

    <div
      v-if="allDone"
      class="mt-5 flex items-center justify-between rounded-lg bg-n-teal-3 p-3"
    >
      <span class="text-sm font-medium text-n-teal-12">
        {{ t('ATHENAS_ONBOARDING.ALL_DONE') }}
      </span>
      <Button
        :label="t('ATHENAS_ONBOARDING.FINISH')"
        teal
        sm
        @click="persistDismiss(true)"
      />
    </div>
  </div>
  <template v-else />
</template>

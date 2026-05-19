<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAthenasAssistant } from 'dashboard/composables/useAthenasAssistant';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Icon from 'next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const { isAdmin } = useAdmin();
const { accountId, currentAccount, updateAccount } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const { assistants, fetchAssistants } = useAthenasAssistant();

const isCollapsed = ref(true);
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
    router.push(
      frontendURL(`accounts/${accountId.value}/athenas/assistants/${first.id}`)
    );
  } else {
    router.push(
      frontendURL(`accounts/${accountId.value}/athenas/assistants/new`)
    );
  }
};

const steps = computed(() => [
  {
    key: 'assistant',
    icon: 'i-lucide-sparkles',
    title: t('ATHENAS_ONBOARDING.STEPS.ASSISTANT.TITLE'),
    body: t('ATHENAS_ONBOARDING.STEPS.ASSISTANT.BODY'),
    cta: t('ATHENAS_ONBOARDING.STEPS.ASSISTANT.CTA'),
    done: hasCustomAssistant.value,
    onClick: () => goToAssistant(),
  },
  {
    key: 'whatsapp',
    icon: 'i-lucide-message-circle',
    title: t('ATHENAS_ONBOARDING.STEPS.WHATSAPP.TITLE'),
    body: t('ATHENAS_ONBOARDING.STEPS.WHATSAPP.BODY'),
    cta: t('ATHENAS_ONBOARDING.STEPS.WHATSAPP.CTA'),
    done: hasInbox.value,
    onClick: () =>
      router.push(
        frontendURL(`accounts/${accountId.value}/settings/inboxes/new/whatsapp`)
      ),
  },
  {
    key: 'team',
    icon: 'i-lucide-users',
    title: t('ATHENAS_ONBOARDING.STEPS.TEAM.TITLE'),
    body: t('ATHENAS_ONBOARDING.STEPS.TEAM.BODY'),
    cta: t('ATHENAS_ONBOARDING.STEPS.TEAM.CTA'),
    done: hasTeam.value,
    onClick: () =>
      router.push(
        frontendURL(`accounts/${accountId.value}/settings/agents/new`)
      ),
  },
]);

const progress = computed(() => {
  const total = steps.value.length;
  const done = steps.value.filter(s => s.done).length;
  return { total, done, percent: Math.round((done / total) * 100) };
});

const allDone = computed(() => progress.value.done === progress.value.total);

const onSetupRoute = computed(() => {
  // hide while admin is actively configuring something to avoid covering
  // settings dialogs / wizards
  const name = route.name || '';
  return /^(login|signup|onboarding|reset|password)/.test(name);
});

const isVisible = computed(() => {
  if (!isAdmin.value) return false;
  // only surface the dock while the tenant has zero inboxes — once they
  // have at least one channel connected, we get out of the way
  if (hasInbox.value) return false;
  if (isDismissed.value) return false;
  if (isExplicitlyDismissed.value) return false;
  if (isExplicitlyDone.value) return false;
  if (onSetupRoute.value) return false;
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
    class="fixed bottom-4 ltr:left-20 rtl:right-20 z-40 max-sm:left-4 max-sm:right-4 max-sm:bottom-4"
  >
    <button
      v-if="isCollapsed"
      type="button"
      class="flex items-center gap-2 rounded-full bg-n-teal-9 text-white px-4 py-2.5 shadow-xl hover:bg-n-teal-10 transition-all"
      @click="isCollapsed = false"
    >
      <Icon icon="i-lucide-rocket" class="size-4" />
      <span class="text-sm font-semibold">
        {{
          t('ATHENAS_ONBOARDING.PILL_LABEL', {
            done: progress.done,
            total: progress.total,
          })
        }}
      </span>
      <span
        class="ml-1 inline-flex h-1.5 w-12 rounded-full bg-white/30 overflow-hidden"
      >
        <span
          class="h-full bg-white transition-all duration-500"
          :style="{ width: `${progress.percent}%` }"
        />
      </span>
    </button>

    <div
      v-else
      class="w-[380px] max-w-[calc(100vw-2rem)] rounded-xl border border-n-weak bg-n-surface-2 shadow-2xl overflow-hidden"
    >
      <header
        class="flex items-start justify-between gap-3 px-4 pt-4 pb-3 border-b border-n-weak"
      >
        <div class="flex items-start gap-2.5 min-w-0">
          <span
            class="inline-flex items-center justify-center size-9 rounded-full bg-n-teal-3 shrink-0"
          >
            <Icon icon="i-lucide-rocket" class="text-n-teal-11 size-4" />
          </span>
          <div class="flex flex-col min-w-0">
            <span class="text-sm font-semibold text-n-slate-12 truncate">
              {{ t('ATHENAS_ONBOARDING.TITLE') }}
            </span>
            <span class="text-xs text-n-slate-10 mt-0.5">
              {{
                t('ATHENAS_ONBOARDING.SUBTITLE', {
                  done: progress.done,
                  total: progress.total,
                })
              }}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <Button
            slate
            ghost
            xs
            icon="i-lucide-chevron-down"
            @click="isCollapsed = true"
          />
          <Button
            slate
            ghost
            xs
            icon="i-lucide-x"
            @click="persistDismiss(false)"
          />
        </div>
      </header>

      <div class="px-4 pt-3">
        <div class="h-1.5 w-full rounded-full bg-n-slate-3 overflow-hidden">
          <div
            class="h-full bg-n-teal-9 transition-all duration-500"
            :style="{ width: `${progress.percent}%` }"
          />
        </div>
      </div>

      <ul class="flex flex-col gap-2 px-4 py-3">
        <li
          v-for="step in steps"
          :key="step.key"
          class="flex items-center gap-3 rounded-lg border border-n-weak/60 bg-n-alpha-1/40 p-2.5"
        >
          <span
            class="inline-flex items-center justify-center size-7 rounded-full shrink-0"
            :class="
              step.done
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-slate-3 text-n-slate-11'
            "
          >
            <Icon
              :icon="step.done ? 'i-lucide-check' : step.icon"
              class="size-3.5"
            />
          </span>
          <div class="flex-1 min-w-0">
            <p
              class="text-xs font-medium text-n-slate-12 truncate"
              :class="{ 'line-through opacity-60': step.done }"
            >
              {{ step.title }}
            </p>
          </div>
          <Button
            v-if="!step.done"
            :label="step.cta"
            teal
            xs
            @click="step.onClick"
          />
          <span
            v-else
            class="text-[10px] font-medium uppercase tracking-wide text-n-teal-11"
          >
            {{ t('ATHENAS_ONBOARDING.DONE_BADGE') }}
          </span>
        </li>
      </ul>

      <div
        v-if="allDone"
        class="flex items-center justify-between gap-2 px-4 py-3 border-t border-n-weak bg-n-teal-3"
      >
        <span class="text-xs font-medium text-n-teal-12">
          {{ t('ATHENAS_ONBOARDING.ALL_DONE') }}
        </span>
        <Button
          :label="t('ATHENAS_ONBOARDING.FINISH')"
          teal
          xs
          @click="persistDismiss(true)"
        />
      </div>
    </div>
  </div>
  <template v-else />
</template>

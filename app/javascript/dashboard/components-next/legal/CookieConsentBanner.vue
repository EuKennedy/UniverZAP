<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  COOKIE_CONSENT_STORAGE_KEY,
  COOKIE_CONSENT_VERSION,
} from 'dashboard/constants/legal';
import Icon from 'next/icon/Icon.vue';

const { t } = useI18n();

const isVisible = ref(false);

const readStored = () => {
  try {
    const raw = localStorage.getItem(COOKIE_CONSENT_STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
};

const persist = choice => {
  try {
    localStorage.setItem(
      COOKIE_CONSENT_STORAGE_KEY,
      JSON.stringify({
        version: COOKIE_CONSENT_VERSION,
        choice,
        at: new Date().toISOString(),
      })
    );
  } catch {
    // localStorage blocked — banner re-prompts next session
  }
};

const decide = choice => {
  persist(choice);
  isVisible.value = false;
};

onMounted(() => {
  const stored = readStored();
  if (!stored || stored.version !== COOKIE_CONSENT_VERSION) {
    isVisible.value = true;
  }
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="opacity-0 translate-y-4"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 translate-y-0"
      leave-to-class="opacity-0 translate-y-4"
    >
      <aside
        v-if="isVisible"
        class="fixed bottom-4 left-4 right-4 sm:left-auto sm:right-4 sm:bottom-4 sm:max-w-[440px] z-[55] rounded-2xl bg-n-surface-2 ring-1 ring-n-teal-7/40 shadow-2xl backdrop-blur-xl"
        role="dialog"
        aria-modal="false"
        :aria-label="t('LEGAL.COOKIES.TITLE')"
      >
        <div class="flex items-start gap-3 p-5">
          <span
            class="inline-flex items-center justify-center size-9 rounded-xl bg-n-teal-3 text-n-teal-11 flex-shrink-0"
          >
            <Icon icon="i-lucide-cookie" class="size-4" />
          </span>
          <div class="flex flex-col gap-2 flex-1 min-w-0">
            <h3 class="text-[13px] font-semibold text-n-slate-12 m-0">
              {{ t('LEGAL.COOKIES.TITLE') }}
            </h3>
            <p class="text-[12px] text-n-slate-11 m-0 leading-relaxed">
              {{ t('LEGAL.COOKIES.BODY') }}
              <a
                href="/privacidade"
                target="_blank"
                rel="noopener"
                class="text-n-teal-11 hover:text-n-teal-12 underline underline-offset-2"
              >
                {{ t('LEGAL.COOKIES.LEARN_MORE') }}
              </a>
            </p>
          </div>
        </div>
        <footer
          class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak bg-n-alpha-1/40 rounded-b-2xl"
        >
          <button
            type="button"
            class="px-3 py-1.5 rounded-lg text-[12px] font-medium text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
            @click="decide('essential')"
          >
            {{ t('LEGAL.COOKIES.ESSENTIAL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-n-teal-9 hover:bg-n-teal-10 text-white text-[12px] font-semibold transition-colors cursor-pointer"
            @click="decide('all')"
          >
            {{ t('LEGAL.COOKIES.ACCEPT_ALL') }}
            <Icon icon="i-lucide-check" class="size-3.5" />
          </button>
        </footer>
      </aside>
    </Transition>
  </Teleport>
</template>

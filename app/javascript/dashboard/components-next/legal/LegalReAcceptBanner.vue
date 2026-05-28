<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { LEGAL_VERSIONS } from 'dashboard/constants/legal';
import Icon from 'next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const currentUser = useMapGetter('getCurrentUser');
const isBusy = ref(false);

const acceptedTerms = computed(
  () => currentUser.value?.accepted_terms_version || null
);
const acceptedPrivacy = computed(
  () => currentUser.value?.accepted_privacy_version || null
);

// LGPD §9.3: bloqueia o dashboard até o usuário reaceitar a versão atual.
// Aplica-se a qualquer divergência entre o que está no User e o que está
// publicado em /termos /privacidade.
const needsReAccept = computed(() => {
  if (!currentUser.value?.id) return false;
  if (acceptedTerms.value !== LEGAL_VERSIONS.terms) return true;
  if (acceptedPrivacy.value !== LEGAL_VERSIONS.privacy) return true;
  return false;
});

/* global axios */
const accept = async () => {
  if (isBusy.value) return;
  isBusy.value = true;
  try {
    // Use the global axios so the request rides the dashboard's auth
    // interceptor (devise_token_auth headers + CSRF). Plain fetch() bypassed
    // those headers and the API rejected with 401.
    await axios.post('/api/v1/profile/accept_terms', {
      terms_version: LEGAL_VERSIONS.terms,
      privacy_version: LEGAL_VERSIONS.privacy,
    });
    if (currentUser.value) {
      currentUser.value.accepted_terms_version = LEGAL_VERSIONS.terms;
      currentUser.value.accepted_privacy_version = LEGAL_VERSIONS.privacy;
    }
    useAlert(t('LEGAL.RE_ACCEPT.SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.message ||
        t('LEGAL.RE_ACCEPT.ERROR')
    );
  } finally {
    isBusy.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="needsReAccept"
        class="fixed inset-0 z-[70] flex items-center justify-center p-6 bg-black/90 backdrop-blur-md"
        role="dialog"
        aria-modal="true"
        :aria-label="t('LEGAL.RE_ACCEPT.TITLE')"
      >
        <div
          class="relative w-full max-w-md rounded-3xl bg-gradient-to-br from-n-surface-2 to-n-surface-1 border border-n-teal-7/30 shadow-2xl overflow-hidden"
        >
          <span
            class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-n-teal-9 via-n-teal-10 to-n-teal-9"
          />
          <div
            class="px-8 pt-8 pb-7 flex flex-col items-center text-center gap-5"
          >
            <span
              class="inline-flex items-center justify-center size-14 rounded-full bg-gradient-to-br from-n-teal-9 to-n-teal-10 text-white shadow-xl"
            >
              <Icon icon="i-lucide-scale" class="size-6" />
            </span>
            <div class="flex flex-col gap-2 max-w-sm">
              <h2
                class="text-xl font-semibold text-n-slate-12 m-0 leading-tight tracking-tight"
              >
                {{ t('LEGAL.RE_ACCEPT.TITLE') }}
              </h2>
              <p class="text-sm text-n-slate-11 m-0 leading-relaxed">
                {{ t('LEGAL.RE_ACCEPT.BODY') }}
              </p>
            </div>
            <div class="flex flex-col gap-2 w-full">
              <a
                href="/termos"
                target="_blank"
                rel="noopener"
                class="inline-flex items-center justify-center gap-1.5 px-4 py-2 rounded-lg ring-1 ring-n-weak text-[12.5px] font-medium text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
              >
                <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
                {{ t('LEGAL.RE_ACCEPT.READ_TERMS') }}
              </a>
              <a
                href="/privacidade"
                target="_blank"
                rel="noopener"
                class="inline-flex items-center justify-center gap-1.5 px-4 py-2 rounded-lg ring-1 ring-n-weak text-[12.5px] font-medium text-n-slate-12 hover:bg-n-alpha-2 transition-colors cursor-pointer"
              >
                <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
                {{ t('LEGAL.RE_ACCEPT.READ_PRIVACY') }}
              </a>
            </div>
            <Button
              :label="
                isBusy ? t('LEGAL.RE_ACCEPT.SAVING') : t('LEGAL.RE_ACCEPT.CTA')
              "
              teal
              solid
              lg
              :disabled="isBusy"
              class="w-full"
              @click="accept"
            />
            <p class="text-[10.5px] text-n-slate-10 leading-relaxed">
              {{ t('LEGAL.RE_ACCEPT.HINT') }}
            </p>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

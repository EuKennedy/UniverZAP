<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ id: { type: Number, required: true } });

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const assistant = ref(null);
const loading = ref(false);

const fetchAssistant = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAssistantsAPI.show(props.id);
    assistant.value = data;
  } catch (e) {
    useAlert(e?.response?.data?.error || e.message);
  } finally {
    loading.value = false;
  }
};

const goBack = () =>
  router.push(accountScopedRoute('athenas_assistants_index'));

const remove = async () => {
  if (!window.confirm(t('ATHENAS.EDIT.DELETE_CONFIRM'))) return;
  try {
    await AthenasAssistantsAPI.delete(props.id);
    useAlert(t('ATHENAS.EDIT.DELETE_SUCCESS'));
    goBack();
  } catch (e) {
    useAlert(e?.response?.data?.error || e.message);
  }
};

onMounted(fetchAssistant);
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-5 border-b border-n-weak"
    >
      <div class="flex items-center gap-3 min-w-0">
        <Button
          icon="i-lucide-arrow-left"
          size="xs"
          ghost
          slate
          @click="goBack"
        />
        <div class="flex flex-col gap-0.5 min-w-0">
          <h1
            class="text-base font-semibold text-n-slate-12 truncate tracking-tight"
          >
            {{ assistant?.name || t('ATHENAS.EDIT.LOADING') }}
          </h1>
          <p class="text-[11px] text-n-slate-11 truncate">
            {{ assistant?.role }}
          </p>
        </div>
      </div>
      <Button
        v-if="assistant"
        icon="i-lucide-trash-2"
        size="sm"
        faded
        ruby
        :label="t('ATHENAS.EDIT.DELETE')"
        @click="remove"
      />
    </header>

    <section v-if="loading" class="flex-1 flex items-center justify-center">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </section>

    <section v-else-if="assistant" class="flex-1 overflow-y-auto px-8 py-8">
      <div
        class="max-w-3xl mx-auto flex flex-col gap-6 p-6 rounded-2xl bg-n-alpha-1 ring-1 ring-n-weak"
      >
        <p class="text-sm text-n-slate-11 leading-relaxed">
          {{ t('ATHENAS.EDIT.PLACEHOLDER') }}
        </p>
        <pre
          class="text-[12px] text-n-slate-11 bg-n-solid-1 p-4 rounded-xl overflow-x-auto font-mono ring-1 ring-n-weak"
          >{{ JSON.stringify(assistant, null, 2) }}</pre
        >
      </div>
    </section>
  </div>
</template>

<script setup>
/**
 * O catálogo: o que o Gerente procura em cada conversa.
 *
 * Existe para responder a pergunta que a fila não responde, que é o que NÃO
 * apareceu. Uma fila vazia lê como "está tudo certo" ou como "ele não olhou
 * isso", e essas duas coisas são opostas. Aqui o operador vê a lista inteira e
 * decide o que continua valendo para o negócio dele.
 *
 * O interruptor troca de posição antes da resposta do servidor e volta se a
 * chamada falhar. Esperar o round trip faz um interruptor parecer quebrado.
 */
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AiManagerAPI from 'dashboard/api/aiManager';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const { t } = useI18n();

const KNOWN_CHECKS = [
  'promised_time_mismatch',
  'loose_promise',
  'died_on_price',
  'ungrounded_number',
];

const checks = ref([]);
const isLoading = ref(true);
const loadError = ref('');
const saveError = ref('');

const messageFrom = (caught, fallback) =>
  caught?.response?.data?.error || caught?.message || t(fallback);

// A copy das verificações conhecidas é nossa, e a do servidor é o plano B.
// Verificação que o backend passe a mandar aparece na lista com o texto dele,
// em vez de sumir do catálogo por falta de tradução.
const copyFor = (check, ourField, theirField) =>
  KNOWN_CHECKS.includes(check.key)
    ? t(`AI_MANAGER.CHECK.${check.key.toUpperCase()}.${ourField}`)
    : check[theirField];

const rows = computed(() =>
  checks.value.map(check => ({
    ...check,
    label: copyFor(check, 'TITLE', 'title'),
    what: copyFor(check, 'WHAT', 'what_it_measures'),
  }))
);

const fetchChecks = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await AiManagerAPI.listChecks();
    checks.value = data.payload || [];
  } catch (caught) {
    loadError.value = messageFrom(caught, 'AI_MANAGER.CHECKS.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const toggle = async (key, enabled) => {
  const row = checks.value.find(check => check.key === key);
  if (!row) return;

  saveError.value = '';
  row.enabled = enabled;
  try {
    await AiManagerAPI.updateCheck(key, enabled);
  } catch (caught) {
    row.enabled = !enabled;
    saveError.value = messageFrom(caught, 'AI_MANAGER.CHECKS.SAVE_ERROR');
  }
};

onMounted(fetchChecks);
</script>

<template>
  <section class="flex flex-col gap-4">
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-[15px] font-medium text-n-slate-12">
        {{ t('AI_MANAGER.CHECKS.TITLE') }}
      </h2>
      <p class="m-0 max-w-2xl text-[13px] leading-relaxed text-n-slate-11">
        {{ t('AI_MANAGER.CHECKS.SUBTITLE') }}
      </p>
    </div>

    <div v-if="isLoading" class="flex justify-center py-12 text-n-slate-11">
      <Spinner :size="20" />
    </div>

    <div
      v-else-if="loadError"
      class="flex flex-col gap-2.5 items-start px-4 py-3.5 rounded-xl border border-n-weak bg-n-solid-1"
      data-testid="checks-error"
    >
      <p class="m-0 text-[13px] text-n-ruby-11">{{ loadError }}</p>
      <Button
        variant="outline"
        color="slate"
        size="sm"
        :label="t('AI_MANAGER.RETRY')"
        data-testid="checks-retry"
        @click="fetchChecks"
      />
    </div>

    <p
      v-else-if="!rows.length"
      class="m-0 text-[13px] text-n-slate-11"
      data-testid="checks-empty"
    >
      {{ t('AI_MANAGER.CHECKS.EMPTY') }}
    </p>

    <div
      v-else
      class="flex flex-col rounded-xl border divide-y border-n-weak divide-n-weak"
    >
      <div
        v-for="row in rows"
        :key="row.key"
        class="flex gap-4 justify-between items-start px-4 py-3.5"
        :data-testid="`check-${row.key}`"
      >
        <div class="flex flex-col gap-1">
          <span
            class="text-[13px] font-medium leading-snug"
            :class="row.enabled ? 'text-n-slate-12' : 'text-n-slate-11'"
          >
            {{ row.label }}
          </span>
          <span class="text-[12px] leading-relaxed text-n-slate-11">
            {{ row.what }}
          </span>
        </div>
        <Switch
          class="mt-1"
          :model-value="row.enabled"
          :aria-label="row.label"
          :data-testid="`toggle-${row.key}`"
          @update:model-value="value => toggle(row.key, value)"
        />
      </div>
    </div>

    <p
      v-if="saveError"
      class="m-0 text-[12px] text-n-ruby-11"
      data-testid="checks-save-error"
    >
      {{ saveError }}
    </p>
  </section>
</template>

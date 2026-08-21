<script setup>
/**
 * Criar e acompanhar template sem sair do produto.
 *
 * Submeter era a única etapa do disparo que acontecia inteiramente no painel da
 * Meta: o operador criava lá, esperava sem saber quanto, e voltava aqui torcendo
 * para o sync ter pegado. Isto não acelera a aprovação — quem aprova é a Meta —
 * mas mostra o estado, e o motivo quando ela recusa.
 */
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});

const { t } = useI18n();

const templates = ref([]);
const isLoading = ref(false);
const isSubmitting = ref(false);
const loadError = ref('');
const formError = ref('');
const form = ref({
  name: '',
  category: 'UTILITY',
  language: 'pt_BR',
  body: '',
});

// UTILITY aprova mais rápido e custa menos; MARKETING é o que promoção exige.
// AUTHENTICATION fica fora porque é código de verificação, não campanha.
const CATEGORIES = ['UTILITY', 'MARKETING'];

const canSubmit = computed(
  () => form.value.name.trim() && form.value.body.trim() && !isSubmitting.value
);

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await WhatsappTemplatesAPI.get(props.inboxId);
    templates.value = data.template || [];
  } catch (error) {
    loadError.value =
      error?.response?.data?.error ||
      t('WHATSAPP_TEMPLATES.MANAGE.LOAD_FAILED');
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

const submit = async () => {
  isSubmitting.value = true;
  formError.value = '';
  try {
    await WhatsappTemplatesAPI.submit(props.inboxId, { ...form.value });
    useAlert(t('WHATSAPP_TEMPLATES.MANAGE.SUBMITTED'));
    form.value = { name: '', category: 'UTILITY', language: 'pt_BR', body: '' };
    await load();
  } catch (error) {
    // O erro da Meta chega inteiro de propósito: aqui quem lê é quem corrige,
    // e ele diz coisas acionáveis como nome repetido ou categoria incompatível.
    formError.value =
      error?.response?.data?.error ||
      t('WHATSAPP_TEMPLATES.MANAGE.SUBMIT_FAILED');
  } finally {
    isSubmitting.value = false;
  }
};

const remove = async name => {
  try {
    await WhatsappTemplatesAPI.remove(props.inboxId, name);
    await load();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('WHATSAPP_TEMPLATES.MANAGE.LOAD_FAILED')
    );
  }
};

const toneFor = status =>
  ({
    APPROVED: 'text-n-teal-11 bg-n-alpha-1',
    REJECTED: 'text-n-ruby-11 bg-n-alpha-1',
  })[status] || 'text-n-amber-11 bg-n-alpha-1';
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <section class="flex flex-col gap-3 max-w-2xl">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('WHATSAPP_TEMPLATES.MANAGE.NEW') }}
      </h2>
      <p class="m-0 text-[13px] text-n-slate-11">
        {{ t('WHATSAPP_TEMPLATES.MANAGE.NEW_HINT') }}
      </p>

      <label class="flex flex-col gap-1 text-[13px] text-n-slate-11">
        {{ t('WHATSAPP_TEMPLATES.MANAGE.NAME') }}
        <input
          v-model="form.name"
          :placeholder="t('WHATSAPP_TEMPLATES.MANAGE.NAME_PLACEHOLDER')"
          class="px-3 h-10 text-sm rounded-lg border outline-none border-n-weak bg-n-alpha-1 text-n-slate-12"
        />
      </label>

      <div class="flex gap-3">
        <label class="flex flex-col flex-1 gap-1 text-[13px] text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATES.MANAGE.CATEGORY') }}
          <select
            v-model="form.category"
            class="px-3 h-10 text-sm rounded-lg border outline-none border-n-weak bg-n-alpha-1 text-n-slate-12"
          >
            <option v-for="option in CATEGORIES" :key="option" :value="option">
              {{ t(`WHATSAPP_TEMPLATES.MANAGE.CATEGORIES.${option}`) }}
            </option>
          </select>
        </label>
        <label class="flex flex-col flex-1 gap-1 text-[13px] text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATES.MANAGE.LANGUAGE') }}
          <input
            v-model="form.language"
            class="px-3 h-10 text-sm rounded-lg border outline-none border-n-weak bg-n-alpha-1 text-n-slate-12"
          />
        </label>
      </div>

      <label class="flex flex-col gap-1 text-[13px] text-n-slate-11">
        {{ t('WHATSAPP_TEMPLATES.MANAGE.BODY') }}
        <textarea
          v-model="form.body"
          rows="3"
          class="px-3 py-2 text-sm rounded-lg border outline-none resize-y border-n-weak bg-n-alpha-1 text-n-slate-12"
        />
      </label>

      <p v-if="formError" class="m-0 text-[13px] text-n-ruby-11">
        {{ formError }}
      </p>

      <div>
        <Button
          size="sm"
          :label="t('WHATSAPP_TEMPLATES.MANAGE.SUBMIT')"
          :is-loading="isSubmitting"
          :disabled="!canSubmit"
          @click="submit"
        />
      </div>
    </section>

    <section class="flex flex-col gap-2">
      <div class="flex gap-2 justify-between items-center">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('WHATSAPP_TEMPLATES.MANAGE.LIST') }}
        </h2>
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-refresh-cw"
          :is-loading="isLoading"
          @click="load"
        />
      </div>

      <p v-if="loadError" class="m-0 text-[13px] text-n-ruby-11">
        {{ loadError }}
      </p>
      <p
        v-else-if="!isLoading && !templates.length"
        class="m-0 text-[13px] text-n-slate-11"
      >
        {{ t('WHATSAPP_TEMPLATES.MANAGE.EMPTY') }}
      </p>

      <div
        v-for="template in templates"
        :key="template.id || template.name"
        class="flex gap-3 items-center p-3 rounded-lg border border-n-weak"
      >
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-sm truncate text-n-slate-12">{{
            template.name
          }}</span>
          <span class="text-[12px] text-n-slate-11">
            {{
              t('WHATSAPP_TEMPLATES.MANAGE.META', {
                category: template.category,
                language: template.language,
              })
            }}
          </span>
          <!-- Sem o motivo, "recusado" não diz por onde começar. -->
          <span
            v-if="template.rejected_reason"
            class="text-[12px] text-n-ruby-11"
          >
            {{ template.rejected_reason }}
          </span>
        </div>
        <span
          class="px-2 py-0.5 text-[11px] rounded-full flex-shrink-0"
          :class="toneFor(template.status)"
        >
          {{ template.status }}
        </span>
        <Button
          size="xs"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          @click="remove(template.name)"
        />
      </div>
    </section>
  </div>
</template>

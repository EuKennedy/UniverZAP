<script setup>
/**
 * Escrever um status e mandar para uma ou várias conexões, agora ou depois.
 *
 * Publicar é irreversível: sai para todos os contatos de cada número e o
 * painel não tem como apagar depois, porque o endpoint de apagar da WAHA não
 * vale para todos os engines. Por isso publicar e agendar sempre passam pela
 * confirmação mostrando exatamente o que vai ao ar, onde e quando. Rascunho
 * não confirma: não sai de lugar nenhum.
 *
 * O envio em si acontece no backend, em segundo plano. Aqui só se grava o
 * post; o resultado de cada conexão aparece no histórico.
 */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';
import {
  apiErrorMessage,
  dateLocale,
  RECURRENCES,
  renderVariables,
  STATUS_BACKGROUNDS,
  STATUS_FONTS,
  STATUS_TEXT_LIMIT,
  STATUS_VARIABLES,
  SUGGESTION_TONES,
  toLocalInputValue,
} from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import StatusPreview from './StatusPreview.vue';
import StatusTemplatesMenu from './StatusTemplatesMenu.vue';

const props = defineProps({
  inboxes: { type: Array, required: true },
  defaultInboxId: { type: Number, default: null },
  // Rascunho ou agendado aberto a partir do histórico para editar.
  editingPost: { type: Object, default: null },
  // Preenche {{empresa}} na prévia; o backend usa o nome da conta de verdade.
  accountName: { type: String, default: '' },
});

const emit = defineEmits(['saved', 'cancelEdit']);

const { t, locale } = useI18n();

const KINDS = ['text', 'image', 'video'];

const kind = ref('text');
const body = ref('');
const backgroundColor = ref(STATUS_BACKGROUNDS[0].value);
const font = ref(0);
const selectedInboxIds = ref([]);
const selectedFile = ref(null);
const previewUrl = ref('');
const when = ref('now');
const scheduleAt = ref('');
const isSaving = ref(false);
const formError = ref('');
const fileInput = ref(null);
const confirmDialogRef = ref(null);
const showSuggest = ref(false);
const suggestPrompt = ref('');
const isSuggesting = ref(false);
const tone = ref('friendly');
const suggestions = ref([]);
const recurrence = ref('none');

const label = key => t(`WHATSAPP_PROFILE.STATUS.${key}`);
const isText = computed(() => kind.value === 'text');
const isEditing = computed(() => Boolean(props.editingPost));
const acceptedTypes = computed(() =>
  kind.value === 'image' ? 'image/jpeg,image/png,image/webp' : 'video/*'
);
const hasMedia = computed(() =>
  Boolean(selectedFile.value || previewUrl.value)
);
const selectedInboxes = computed(() =>
  props.inboxes.filter(inbox => selectedInboxIds.value.includes(inbox.id))
);
const scheduleDate = computed(() =>
  scheduleAt.value ? new Date(scheduleAt.value) : null
);
const minSchedule = computed(() => toLocalInputValue(new Date()));
const primaryLabel = computed(() =>
  when.value === 'later' ? label('SCHEDULE') : label('PUBLISH')
);
// A prévia mostra o texto como ele sai na primeira conexão marcada, com as
// variáveis já preenchidas, porque é isso que o cliente vai ler.
const previewInboxName = computed(
  () => selectedInboxes.value[0]?.name || props.inboxes[0]?.name || ''
);
const previewBody = computed(() =>
  renderVariables(
    body.value,
    { conexao: previewInboxName.value, empresa: props.accountName },
    when.value === 'later' && scheduleDate.value
      ? scheduleDate.value
      : new Date()
  )
);
const usesVariables = computed(() => /\{\{\s*\w+\s*\}\}/.test(body.value));
const recurrenceOptions = computed(() =>
  RECURRENCES.map(value => ({
    value,
    label: label(`RECURRENCE.${value.toUpperCase()}`),
  }))
);
const templateSnapshot = computed(() => ({
  body: body.value.trim(),
  backgroundColor: backgroundColor.value,
  font: font.value,
}));

const setFile = file => {
  selectedFile.value = file || null;
  previewUrl.value =
    file && window.URL?.createObjectURL ? URL.createObjectURL(file) : '';
};

const reset = () => {
  kind.value = 'text';
  body.value = '';
  backgroundColor.value = STATUS_BACKGROUNDS[0].value;
  font.value = 0;
  selectedInboxIds.value = props.defaultInboxId ? [props.defaultInboxId] : [];
  when.value = 'now';
  scheduleAt.value = '';
  formError.value = '';
  showSuggest.value = false;
  suggestPrompt.value = '';
  suggestions.value = [];
  recurrence.value = 'none';
  setFile(null);
  if (fileInput.value) fileInput.value.value = null;
};

const loadPost = post => {
  reset();
  kind.value = post.kind;
  body.value = post.body || '';
  backgroundColor.value = post.background_color || STATUS_BACKGROUNDS[0].value;
  font.value = post.font || 0;
  selectedInboxIds.value = [...(post.inbox_ids || [])];
  previewUrl.value = post.media?.url || '';
  recurrence.value = post.recurrence || 'none';
  if (post.scheduled_at) {
    when.value = 'later';
    scheduleAt.value = toLocalInputValue(new Date(post.scheduled_at));
  }
};

const selectKind = next => {
  kind.value = next;
  formError.value = '';
  setFile(null);
};

const toggleInbox = id => {
  selectedInboxIds.value = selectedInboxIds.value.includes(id)
    ? selectedInboxIds.value.filter(item => item !== id)
    : [...selectedInboxIds.value, id];
};

const openFileDialog = () => fileInput.value?.click();
const handleFileChange = () => setFile(fileInput.value?.files?.[0]);

const applyTemplate = template => {
  body.value = template.body;
  if (template.background_color)
    backgroundColor.value = template.background_color;
  font.value = template.font || 0;
};

// Variável entra no fim do texto, com espaço, para não colar na última palavra.
const variableToken = key => `{{${key}}}`;
const insertVariable = key => {
  const separator = body.value && !/\s$/.test(body.value) ? ' ' : '';
  body.value = `${body.value}${separator}${variableToken(key)}`;
};

// A IA devolve três opções no tom escolhido; nenhuma entra no campo sozinha,
// o operador escolhe a que combina e ainda pode editar depois.
const suggest = async () => {
  isSuggesting.value = true;
  formError.value = '';
  try {
    const { data } = await WhatsAppStatusAPI.suggest({
      prompt: suggestPrompt.value.trim(),
      body: body.value.trim(),
      kind: kind.value,
      tone: tone.value,
    });
    suggestions.value = data.texts?.length ? data.texts : [data.text];
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
  } finally {
    isSuggesting.value = false;
  }
};

// A validação acontece antes da confirmação: pedir "tem certeza?" para algo que
// nem sairia do lugar seria uma pergunta falsa.
const validationError = () => {
  if (!selectedInboxIds.value.length)
    return t('WHATSAPP_PROFILE.ERRORS.CONNECTION_REQUIRED');
  if (isText.value && !body.value.trim())
    return t('WHATSAPP_PROFILE.ERRORS.TEXT_REQUIRED');
  if (!isText.value && !hasMedia.value)
    return t('WHATSAPP_PROFILE.ERRORS.FILE_REQUIRED');
  if (when.value === 'later' && !(scheduleDate.value > new Date())) {
    return t('WHATSAPP_PROFILE.ERRORS.SCHEDULE_REQUIRED');
  }
  return '';
};

const pickSuggestion = text => {
  body.value = text;
  suggestions.value = [];
};

const requestSubmit = () => {
  formError.value = validationError();
  if (!formError.value) confirmDialogRef.value?.open();
};

const save = async intent => {
  isSaving.value = true;
  formError.value = '';
  try {
    const blobId =
      !isText.value && selectedFile.value
        ? (await uploadFile(selectedFile.value)).blobId
        : undefined;
    const { data } = await WhatsAppStatusAPI.save({
      id: props.editingPost?.id,
      kind: kind.value,
      body: body.value.trim(),
      backgroundColor: backgroundColor.value,
      font: font.value,
      inboxIds: selectedInboxIds.value,
      blobId,
      scheduledAt:
        intent === 'schedule' ? scheduleDate.value.toISOString() : undefined,
      recurrence: intent === 'schedule' ? recurrence.value : 'none',
      intent,
    });
    confirmDialogRef.value?.close();
    useAlert(label(`SAVED.${intent.toUpperCase()}`));
    reset();
    emit('saved', data);
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
    confirmDialogRef.value?.close();
  } finally {
    isSaving.value = false;
  }
};

const confirmSubmit = () =>
  save(when.value === 'later' ? 'schedule' : 'publish');

const cancelEdit = () => {
  reset();
  emit('cancelEdit');
};

watch(
  () => props.editingPost,
  post => (post ? loadPost(post) : reset()),
  { immediate: true }
);

// Trocar a conexão do perfil no topo da página puxa a mesma conexão como
// padrão aqui, mas só enquanto o operador ainda não escolheu outras.
watch(
  () => props.defaultInboxId,
  id => {
    if (!isEditing.value && selectedInboxIds.value.length <= 1 && id) {
      selectedInboxIds.value = [id];
    }
  }
);
</script>

<template>
  <!-- ⌘/Ctrl+Enter publica (ou agenda) de qualquer campo: abre a mesma
    confirmação do botão, então o atalho nunca pula a pergunta. -->
  <section
    class="flex flex-col gap-6 p-6 rounded-xl border border-n-weak bg-n-solid-1"
    @keydown.meta.enter.prevent="requestSubmit"
    @keydown.ctrl.enter.prevent="requestSubmit"
  >
    <div class="flex flex-wrap gap-3 justify-between items-start">
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-base font-medium text-n-slate-12">
          {{ isEditing ? label('EDIT_TITLE') : label('TITLE') }}
        </h2>
        <!-- As 24 horas ficam aqui, e não escondidas na confirmação: quem decide
          o que publicar precisa saber quanto tempo aquilo dura antes de escrever. -->
        <p class="m-0 text-[13px] text-n-slate-11">
          {{ label('DESCRIPTION') }}
        </p>
      </div>
      <StatusTemplatesMenu :current="templateSnapshot" @apply="applyTemplate" />
    </div>

    <div class="flex flex-col gap-2">
      <span
        class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
      >
        {{ label('CONNECTIONS') }}
      </span>
      <div class="flex flex-wrap gap-2">
        <label
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="flex gap-2 items-center px-3 py-1.5 text-[13px] rounded-lg border cursor-pointer border-n-weak text-n-slate-12"
          :class="selectedInboxIds.includes(inbox.id) ? 'bg-n-alpha-2' : ''"
          :data-testid="`connection-${inbox.id}`"
        >
          <Checkbox
            :model-value="selectedInboxIds.includes(inbox.id)"
            @change="toggleInbox(inbox.id)"
          />
          {{ inbox.name }}
        </label>
      </div>
    </div>

    <div class="grid gap-6 items-start md:grid-cols-[minmax(0,1fr)_14rem]">
      <div class="flex flex-col gap-4 min-w-0">
        <div class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1">
          <button
            v-for="option in KINDS"
            :key="option"
            type="button"
            class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
            :class="
              kind === option
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`kind-${option}`"
            @click="selectKind(option)"
          >
            {{ label(`KIND.${option.toUpperCase()}`) }}
          </button>
        </div>

        <div v-if="!isText" class="flex flex-wrap gap-3 items-center">
          <Button
            slate
            faded
            size="sm"
            :icon="kind === 'image' ? 'i-lucide-image' : 'i-lucide-video'"
            :label="
              kind === 'image' ? label('CHOOSE_IMAGE') : label('CHOOSE_VIDEO')
            "
            @click="openFileDialog"
          />
          <span
            v-if="selectedFile"
            class="text-[12px] truncate text-n-slate-11"
            data-testid="selected-file"
          >
            {{ selectedFile.name }}
          </span>
          <Button
            v-if="hasMedia"
            ghost
            slate
            size="xs"
            :label="label('REMOVE_FILE')"
            @click="setFile(null)"
          />
          <input
            ref="fileInput"
            type="file"
            :accept="acceptedTypes"
            class="hidden"
            @change="handleFileChange"
          />
        </div>

        <TextArea
          v-model="body"
          :label="isText ? '' : label('CAPTION')"
          :placeholder="
            isText ? label('TEXT_PLACEHOLDER') : label('CAPTION_PLACEHOLDER')
          "
          :max-length="STATUS_TEXT_LIMIT"
          show-character-count
          auto-height
          min-height="6rem"
        />

        <div class="flex flex-wrap gap-1.5 items-center -mt-2">
          <span class="text-[11px] text-n-slate-11">{{
            label('VARIABLES.LABEL')
          }}</span>
          <button
            v-for="key in STATUS_VARIABLES"
            :key="key"
            type="button"
            class="px-2 py-0.5 font-mono text-[11px] rounded-md border border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
            :title="label(`VARIABLES.${key.toUpperCase()}`)"
            :data-testid="`variable-${key}`"
            @click="insertVariable(key)"
          >
            {{ variableToken(key) }}
          </button>
        </div>

        <div class="flex flex-col gap-2">
          <Button
            v-if="!showSuggest"
            ghost
            size="sm"
            class="self-start"
            icon="i-lucide-sparkles"
            :label="label('SUGGEST.OPEN')"
            data-testid="suggest-toggle"
            @click="showSuggest = true"
          />
          <div v-else class="flex flex-wrap gap-2 items-end">
            <Input
              v-model="suggestPrompt"
              class="flex-1 min-w-48"
              :label="label('SUGGEST.LABEL')"
              :placeholder="label('SUGGEST.PLACEHOLDER')"
              data-testid="suggest-prompt"
              @enter="suggest"
            />
            <Button
              size="sm"
              icon="i-lucide-sparkles"
              :label="
                body.trim()
                  ? label('SUGGEST.IMPROVE')
                  : label('SUGGEST.GENERATE')
              "
              :is-loading="isSuggesting"
              data-testid="suggest-button"
              @click="suggest"
            />
          </div>
          <div v-if="showSuggest" class="flex flex-wrap gap-1.5 items-center">
            <span class="text-[11px] text-n-slate-11">{{
              label('SUGGEST.TONE')
            }}</span>
            <button
              v-for="option in SUGGESTION_TONES"
              :key="option"
              type="button"
              class="px-2.5 py-1 text-[12px] rounded-full border"
              :class="
                tone === option
                  ? 'border-n-brand/60 bg-n-alpha-2 text-n-slate-12'
                  : 'border-n-weak text-n-slate-11 hover:text-n-slate-12'
              "
              :data-testid="`tone-${option}`"
              @click="tone = option"
            >
              {{ label(`SUGGEST.TONES.${option.toUpperCase()}`) }}
            </button>
          </div>
          <div
            v-if="suggestions.length"
            class="grid gap-2 sm:grid-cols-3"
            data-testid="suggestions"
          >
            <button
              v-for="(text, index) in suggestions"
              :key="index"
              type="button"
              class="flex flex-col gap-2 p-3 text-start rounded-xl border transition-colors border-n-weak hover:border-n-brand/60 hover:bg-n-alpha-1"
              data-testid="suggestion"
              @click="pickSuggestion(text)"
            >
              <span class="text-[13px] leading-snug text-n-slate-12">{{
                text
              }}</span>
              <span class="mt-auto text-[11px] font-medium text-n-brand">
                {{ label('SUGGEST.USE') }}
              </span>
            </button>
          </div>
        </div>

        <div v-if="kind !== 'image'" class="flex flex-col gap-2">
          <span
            class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
          >
            {{ label('BACKGROUND') }}
          </span>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="color in STATUS_BACKGROUNDS"
              :key="color.value"
              type="button"
              class="rounded-full transition-transform size-7 hover:scale-110"
              :class="[
                color.className,
                backgroundColor === color.value
                  ? 'ring-2 ring-offset-2 ring-n-slate-12 ring-offset-n-solid-1'
                  : '',
              ]"
              :aria-label="color.value"
              @click="backgroundColor = color.value"
            />
          </div>
        </div>

        <div v-if="isText" class="flex flex-col gap-2">
          <span
            class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
          >
            {{ label('FONT') }}
          </span>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="option in STATUS_FONTS"
              :key="option.value"
              type="button"
              class="px-3 py-1.5 text-[13px] rounded-lg border border-n-weak text-n-slate-12"
              :class="[
                option.previewClass,
                font === option.value ? 'bg-n-alpha-2 border-n-slate-9' : '',
              ]"
              :data-testid="`font-${option.value}`"
              @click="font = option.value"
            >
              {{ label(`FONTS.${option.key}`) }}
            </button>
          </div>
        </div>

        <p
          v-if="kind === 'video'"
          class="m-0 text-[12px] leading-relaxed text-n-slate-11"
        >
          {{ label('VIDEO_HINT') }}
        </p>
      </div>

      <div class="flex flex-col gap-2 items-center mx-auto">
        <StatusPreview
          phone
          :title="previewInboxName"
          :kind="kind"
          :body="previewBody"
          :background-color="backgroundColor"
          :font="font"
          :media-url="previewUrl"
          :placeholder="label('TEXT_PLACEHOLDER')"
        />
        <p
          v-if="usesVariables && previewInboxName"
          class="m-0 max-w-56 text-[11px] text-center text-n-slate-10"
          data-testid="variables-hint"
        >
          {{
            t('WHATSAPP_PROFILE.STATUS.VARIABLES.PREVIEW_HINT', {
              name: previewInboxName,
            })
          }}
        </p>
      </div>
    </div>

    <div class="flex flex-col gap-3 pt-4 border-t border-n-weak">
      <div class="flex flex-wrap gap-3 items-center">
        <div class="flex gap-1 p-1 rounded-lg w-fit bg-n-alpha-1">
          <button
            v-for="option in ['now', 'later']"
            :key="option"
            type="button"
            class="px-3 py-1.5 text-[13px] font-medium rounded-md transition-colors"
            :class="
              when === option
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :data-testid="`when-${option}`"
            @click="when = option"
          >
            {{ label(`WHEN.${option.toUpperCase()}`) }}
          </button>
        </div>
        <input
          v-if="when === 'later'"
          v-model="scheduleAt"
          type="datetime-local"
          :min="minSchedule"
          class="!mb-0 !w-auto !h-9 px-3 text-sm rounded-lg border-0 outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
          :aria-label="label('WHEN.AT')"
          data-testid="schedule-at"
        />
        <Select
          v-if="when === 'later'"
          v-model="recurrence"
          :options="recurrenceOptions"
          :aria-label="label('RECURRENCE.LABEL')"
          data-testid="recurrence"
        />
        <span class="hidden ms-auto text-[11px] text-n-slate-10 md:inline">
          {{ label('SHORTCUT') }}
        </span>
      </div>

      <div class="flex flex-wrap gap-3 justify-between items-center">
        <p
          v-if="formError"
          class="m-0 text-[13px] text-n-ruby-11"
          data-testid="publish-error"
        >
          {{ formError }}
        </p>
        <span v-else />
        <div class="flex flex-wrap gap-2">
          <Button
            v-if="isEditing"
            ghost
            slate
            :label="label('CANCEL_EDIT')"
            @click="cancelEdit"
          />
          <Button
            slate
            faded
            icon="i-lucide-file-pen-line"
            :label="label('SAVE_DRAFT')"
            :is-loading="isSaving"
            data-testid="draft-button"
            @click="save('draft')"
          />
          <Button
            :label="primaryLabel"
            :icon="
              when === 'later' ? 'i-lucide-calendar-clock' : 'i-lucide-send'
            "
            data-testid="publish-button"
            @click="requestSubmit"
          />
        </div>
      </div>
    </div>

    <Dialog
      ref="confirmDialogRef"
      type="alert"
      width="md"
      :title="
        when === 'later'
          ? label('CONFIRM.SCHEDULE_TITLE')
          : label('CONFIRM.TITLE')
      "
      :description="label('CONFIRM.DESCRIPTION')"
      :confirm-button-label="
        when === 'later' ? label('CONFIRM.SCHEDULE') : label('CONFIRM.CONFIRM')
      "
      :cancel-button-label="label('CONFIRM.CANCEL')"
      :is-loading="isSaving"
      @confirm="confirmSubmit"
    >
      <!-- Confirmar sem ver o que vai ao ar, onde e quando é só um clique a
        mais. O que torna a pergunta útil é isso estar aqui. -->
      <div class="flex gap-4 items-start" data-testid="publish-preview">
        <StatusPreview
          class="!w-32"
          :kind="kind"
          :body="previewBody"
          :background-color="backgroundColor"
          :font="font"
          :media-url="previewUrl"
        />
        <div class="flex flex-col gap-3 min-w-0 text-[13px]">
          <div class="flex flex-col gap-1">
            <span
              class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
            >
              {{ label('CONNECTIONS') }}
            </span>
            <span
              v-for="inbox in selectedInboxes"
              :key="inbox.id"
              class="text-n-slate-12"
              data-testid="confirm-connection"
            >
              {{ inbox.name }}
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <span
              class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
            >
              {{ label('WHEN.LABEL') }}
            </span>
            <span class="text-n-slate-12">
              {{
                when === 'later' && scheduleDate
                  ? scheduleDate.toLocaleString(dateLocale(locale), {
                      dateStyle: 'short',
                      timeStyle: 'short',
                    })
                  : label('WHEN.NOW')
              }}
            </span>
            <span
              v-if="when === 'later' && recurrence !== 'none'"
              class="flex gap-1 items-center text-n-slate-11"
            >
              <span class="i-lucide-repeat size-3" />
              {{ label(`RECURRENCE.${recurrence.toUpperCase()}`) }}
            </span>
          </div>
          <span v-if="!isText && !body.trim()" class="text-n-slate-11">
            {{ label('CONFIRM.NO_CAPTION') }}
          </span>
        </div>
      </div>
    </Dialog>
  </section>
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useScheduledMessages } from 'dashboard/composables/useScheduledMessages';
import {
  VARIABLES,
  buildShortcuts,
  fromDateTimeLocal,
  missingVariables,
  previewText,
  toDateTimeLocal,
} from 'dashboard/helper/scheduledMessages';

// Agendar (ou editar) uma mensagem para esta conversa. Aberto pelo botão do
// composer, com o texto que já estava digitado, e pela ficha da cliente.
const props = defineProps({
  conversationId: { type: Number, required: true },
  contact: { type: Object, default: () => ({}) },
  conversation: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['saved']);

const { t, locale } = useI18n();
const { create, update, bestTime } = useScheduledMessages(
  computed(() => props.conversationId)
);

const dialogRef = ref(null);
const textareaRef = ref(null);
const editingId = ref(null);
const isSaving = ref(false);
const bestAt = ref(null);
const form = ref({ content: '', sendAt: '', cancelIfReply: true });

const shortcuts = computed(() => buildShortcuts(new Date(), bestAt.value));
const context = computed(() => ({
  contact: props.contact,
  conversation: props.conversation,
}));
const preview = computed(() => previewText(form.value.content, context.value));
const missing = computed(() =>
  missingVariables(form.value.content, context.value)
);
const missingNames = computed(() =>
  missing.value.map(name => `{${name}}`).join(', ')
);
const canConfirm = computed(
  () => Boolean(form.value.content.trim()) && Boolean(form.value.sendAt)
);

const formatWhen = date =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);

const loadBestTime = async () => {
  bestAt.value = null;
  try {
    const data = await bestTime();
    bestAt.value = data.at;
  } catch (error) {
    // Sem sugestão, os atalhos fixos continuam valendo.
  }
};

const open = ({ content = '', scheduled = null } = {}) => {
  editingId.value = scheduled?.id || null;
  form.value = {
    content: scheduled?.content || content,
    sendAt: toDateTimeLocal(scheduled?.send_at),
    cancelIfReply: scheduled ? scheduled.cancel_if_reply : true,
  };
  dialogRef.value?.open();
  loadBestTime();
};

const close = () => dialogRef.value?.close();

const pickShortcut = shortcut => {
  form.value.sendAt = toDateTimeLocal(shortcut.at);
};

const isShortcutActive = shortcut =>
  form.value.sendAt === toDateTimeLocal(shortcut.at);

const insertVariable = name => {
  const token = `{${name}}`;
  const el = textareaRef.value;
  const text = form.value.content;
  const start = el?.selectionStart ?? text.length;
  const end = el?.selectionEnd ?? text.length;
  form.value.content = `${text.slice(0, start)}${token}${text.slice(end)}`;
};

const confirm = async () => {
  if (!canConfirm.value) return;
  isSaving.value = true;
  const payload = {
    content: form.value.content.trim(),
    send_at: fromDateTimeLocal(form.value.sendAt),
    cancel_if_reply: form.value.cancelIfReply,
  };
  try {
    const saved = editingId.value
      ? await update(editingId.value, payload)
      : await create(payload);
    useAlert(
      t('SCHEDULED_MESSAGES.DIALOG.SAVED', {
        when: formatWhen(new Date(saved.send_at)),
      })
    );
    emit('saved', saved);
    close();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        t('SCHEDULED_MESSAGES.DIALOG.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open, close });

const fieldClass =
  'w-full px-3 text-sm rounded-lg outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand bg-n-alpha-black2 text-n-slate-12 !mb-0';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      editingId
        ? t('SCHEDULED_MESSAGES.DIALOG.EDIT_TITLE')
        : t('SCHEDULED_MESSAGES.DIALOG.TITLE')
    "
    :description="t('SCHEDULED_MESSAGES.DIALOG.DESCRIPTION')"
    :confirm-button-label="t('SCHEDULED_MESSAGES.DIALOG.CONFIRM')"
    :disable-confirm-button="!canConfirm"
    :is-loading="isSaving"
    width="md"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-4" data-testid="schedule-message-form">
      <div class="flex flex-col gap-1.5">
        <textarea
          ref="textareaRef"
          v-model="form.content"
          rows="4"
          :placeholder="t('SCHEDULED_MESSAGES.DIALOG.PLACEHOLDER')"
          :class="fieldClass"
          class="py-2 resize-y"
          data-testid="schedule-message-content"
        />
        <div class="flex flex-wrap items-center gap-1">
          <span class="text-[11px] text-n-slate-10">
            {{ t('SCHEDULED_MESSAGES.VARIABLES.LABEL') }}
          </span>
          <button
            v-for="name in VARIABLES"
            :key="name"
            type="button"
            class="px-2 py-0.5 rounded-md bg-n-alpha-2 text-[11px] text-n-slate-11 hover:bg-n-alpha-3 hover:text-n-slate-12"
            @click="insertVariable(name)"
          >
            {{ t(`SCHEDULED_MESSAGES.VARIABLES.${name.toUpperCase()}`) }}
          </button>
        </div>
        <p
          v-if="preview && preview !== form.content.trim()"
          class="m-0 px-3 py-2 rounded-lg bg-n-teal-2 text-xs text-n-slate-12 whitespace-pre-wrap"
          data-testid="schedule-message-preview"
        >
          <span class="font-medium text-n-teal-11">
            {{ t('SCHEDULED_MESSAGES.DIALOG.PREVIEW') }}
          </span>
          {{ preview }}
        </p>
        <p v-if="missing.length" class="m-0 text-[11px] text-n-amber-11">
          {{ t('SCHEDULED_MESSAGES.DIALOG.MISSING', { names: missingNames }) }}
        </p>
      </div>

      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('SCHEDULED_MESSAGES.DIALOG.WHEN') }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="shortcut in shortcuts"
            :key="shortcut.key"
            type="button"
            class="inline-flex items-center gap-1 px-2.5 h-7 rounded-full border text-xs transition-colors"
            :class="
              isShortcutActive(shortcut)
                ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-8'
            "
            :data-testid="`shortcut-${shortcut.key}`"
            @click="pickShortcut(shortcut)"
          >
            <span v-if="shortcut.best" class="i-lucide-sparkles size-3" />
            {{
              t(`SCHEDULED_MESSAGES.SHORTCUTS.${shortcut.key}`, {
                time: formatWhen(shortcut.at),
              })
            }}
          </button>
        </div>
        <input
          v-model="form.sendAt"
          type="datetime-local"
          :class="fieldClass"
          class="h-9"
          data-testid="schedule-message-date"
        />
      </div>

      <label class="flex items-start gap-2 cursor-pointer">
        <input
          v-model="form.cancelIfReply"
          type="checkbox"
          class="mt-0.5"
          data-testid="schedule-message-cancel-if-reply"
        />
        <span class="flex flex-col">
          <span class="text-sm text-n-slate-12">
            {{ t('SCHEDULED_MESSAGES.DIALOG.CANCEL_IF_REPLY') }}
          </span>
          <span class="text-[11px] text-n-slate-10">
            {{ t('SCHEDULED_MESSAGES.DIALOG.CANCEL_IF_REPLY_HINT') }}
          </span>
        </span>
      </label>
    </div>
  </Dialog>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import MessageSequencesAPI from 'dashboard/api/messageSequences';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SequenceEditorDialog from './SequenceEditorDialog.vue';
import { describeOffset } from '../helpers/sequences';

// Sequências presas ao horário agendado da cliente. Toda sequência nasce
// desligada; ligar pede confirmação porque é autorizar mensagem automática
// saindo pelo número do salão.
const { t } = useI18n();

const sequences = ref([]);
const isLoading = ref(false);
const editorRef = ref(null);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await MessageSequencesAPI.get();
    sequences.value = data.payload || [];
  } catch (error) {
    useAlert(t('BROADCAST.SEQUENCES.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const replace = saved => {
  const index = sequences.value.findIndex(item => item.id === saved.id);
  if (index === -1) sequences.value.push(saved);
  else sequences.value.splice(index, 1, saved);
};

const save = async ({ id, ...payload }) => {
  editorRef.value?.setSaving(true);
  try {
    const { data } = id
      ? await MessageSequencesAPI.update(id, payload)
      : await MessageSequencesAPI.create(payload);
    replace(data);
    editorRef.value?.close();
    useAlert(t('BROADCAST.SEQUENCES.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('BROADCAST.SEQUENCES.SAVE_ERROR')
    );
  } finally {
    editorRef.value?.setSaving(false);
  }
};

const toggle = async sequence => {
  const enabling = !sequence.enabled;
  const question = enabling
    ? t('BROADCAST.SEQUENCES.ENABLE_CONFIRM', { name: sequence.name })
    : t('BROADCAST.SEQUENCES.DISABLE_CONFIRM', { name: sequence.name });
  // eslint-disable-next-line no-alert
  if (!window.confirm(question)) return;
  try {
    const { data } = await MessageSequencesAPI.update(sequence.id, {
      enabled: enabling,
    });
    replace(data);
  } catch (error) {
    useAlert(t('BROADCAST.SEQUENCES.SAVE_ERROR'));
  }
};

const remove = async sequence => {
  const question = t('BROADCAST.SEQUENCES.DELETE_CONFIRM', {
    name: sequence.name,
  });
  // eslint-disable-next-line no-alert
  if (!window.confirm(question)) return;
  try {
    await MessageSequencesAPI.delete(sequence.id);
    sequences.value = sequences.value.filter(item => item.id !== sequence.id);
  } catch (error) {
    useAlert(t('BROADCAST.SEQUENCES.SAVE_ERROR'));
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="sequences-panel">
    <div class="flex items-start justify-between gap-4">
      <p class="m-0 text-sm text-n-slate-11 max-w-2xl">
        {{ t('BROADCAST.SEQUENCES.SUBTITLE') }}
      </p>
      <Button
        icon="i-lucide-plus"
        :label="t('BROADCAST.SEQUENCES.NEW')"
        data-testid="sequence-new"
        @click="editorRef?.open()"
      />
    </div>

    <div
      v-if="!sequences.length && !isLoading"
      class="flex flex-col items-center gap-2 py-16 text-center"
    >
      <span
        class="flex items-center justify-center size-12 rounded-2xl bg-n-teal-3 text-n-teal-11"
      >
        <Icon icon="i-lucide-list-ordered" class="size-6" />
      </span>
      <p class="m-0 text-sm text-n-slate-11 max-w-md">
        {{ t('BROADCAST.SEQUENCES.EMPTY') }}
      </p>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <div
        v-for="sequence in sequences"
        :key="sequence.id"
        class="flex flex-col gap-3 p-5 rounded-2xl bg-n-solid-1 border border-n-weak"
        data-testid="sequence-card"
      >
        <div class="flex items-center gap-2">
          <h3 class="flex-1 m-0 text-sm font-semibold text-n-slate-12 truncate">
            {{ sequence.name }}
          </h3>
          <span
            class="px-2 py-0.5 rounded-full text-[11px] font-medium"
            :class="
              sequence.enabled
                ? 'text-n-teal-11 bg-n-teal-3'
                : 'text-n-amber-11 bg-n-amber-3'
            "
          >
            {{
              sequence.enabled
                ? t('BROADCAST.SEQUENCES.ENABLED')
                : t('BROADCAST.SEQUENCES.DISABLED')
            }}
          </span>
        </div>
        <ol class="flex flex-col gap-2 m-0 p-0">
          <li
            v-for="(step, index) in sequence.steps"
            :key="index"
            class="list-none flex flex-col gap-0.5"
          >
            <span class="text-[11px] font-medium text-n-teal-11">
              {{ describeOffset(step, t) }}
            </span>
            <span class="text-xs text-n-slate-11 line-clamp-2">
              {{ step.text }}
            </span>
          </li>
        </ol>
        <p class="m-0 text-[11px] text-n-slate-10">
          {{
            t('BROADCAST.SEQUENCES.STATS', {
              pending: sequence.pending_count,
              sent: sequence.sent_count,
            })
          }}
        </p>
        <div class="flex items-center gap-2">
          <Button
            :variant="sequence.enabled ? 'outline' : 'solid'"
            :color="sequence.enabled ? 'slate' : 'teal'"
            size="sm"
            :icon="sequence.enabled ? 'i-lucide-pause' : 'i-lucide-play'"
            :label="
              sequence.enabled
                ? t('BROADCAST.SEQUENCES.DISABLE')
                : t('BROADCAST.SEQUENCES.ENABLE')
            "
            data-testid="sequence-toggle"
            @click="toggle(sequence)"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-pencil"
            :label="t('BROADCAST.SEQUENCES.EDIT')"
            @click="editorRef?.open(sequence)"
          />
          <Button
            class="ms-auto"
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-trash-2"
            @click="remove(sequence)"
          />
        </div>
      </div>
    </div>

    <SequenceEditorDialog ref="editorRef" @save="save" />
  </div>
</template>

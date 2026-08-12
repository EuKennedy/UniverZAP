<script setup>
// The "Integrações" tab: the tenant-facing surface for the generic Ai::CustomTool
// mechanism. The workspace owner connects the agent to their own HTTP endpoints
// (e.g. univercart's product search + cart builder) — each tool is scoped to
// THIS agent in THIS account, so nothing configured here leaks to another
// workspace. CRUD is driven straight off the Athenas API, like the trainings
// editor, rather than a global store.
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AthenasIntegrationForm from 'dashboard/components-next/athenas/AthenasIntegrationForm.vue';
import AthenasCalendarConnect from 'dashboard/components-next/athenas/AthenasCalendarConnect.vue';

const props = defineProps({
  assistantId: { type: Number, required: true },
});

// Bubbled up so the agent screen can reveal the "Configurar negócio" tab the
// moment the calendar is connected, without this component knowing the tabs
// exist.
defineEmits(['calendarConnected']);

const { t } = useI18n();

const tools = ref([]);
const loading = ref(false);
const saving = ref(false);
const view = ref('list'); // 'list' | 'form'
const editing = ref(null);

const deleteDialogRef = ref(null);
const pendingDelete = ref(null);

const errorMessage = (error, fallback) =>
  error?.response?.data?.message || error?.response?.data?.error || fallback;

const fetchTools = async () => {
  loading.value = true;
  try {
    const { data } = await AthenasAPI.listCustomTools(props.assistantId);
    tools.value = data?.payload || [];
  } catch {
    useAlert(t('ATHENAS.EDIT.INTEGRATIONS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

onMounted(fetchTools);

const openCreate = () => {
  editing.value = null;
  view.value = 'form';
};

const openEdit = tool => {
  editing.value = tool;
  view.value = 'form';
};

const closeForm = () => {
  view.value = 'list';
  editing.value = null;
};

const handleSubmit = async payload => {
  saving.value = true;
  try {
    if (editing.value) {
      await AthenasAPI.updateCustomTool(
        props.assistantId,
        editing.value.id,
        payload
      );
      useAlert(t('ATHENAS.EDIT.INTEGRATIONS.UPDATE_SUCCESS'));
    } else {
      await AthenasAPI.createCustomTool(props.assistantId, payload);
      useAlert(t('ATHENAS.EDIT.INTEGRATIONS.CREATE_SUCCESS'));
    }
    closeForm();
    await fetchTools();
  } catch (error) {
    useAlert(errorMessage(error, t('ATHENAS.EDIT.INTEGRATIONS.SAVE_ERROR')));
  } finally {
    saving.value = false;
  }
};

const toggleEnabled = async tool => {
  const next = !tool.enabled;
  try {
    await AthenasAPI.updateCustomTool(props.assistantId, tool.id, {
      enabled: next,
    });
    tool.enabled = next;
  } catch (error) {
    useAlert(errorMessage(error, t('ATHENAS.EDIT.INTEGRATIONS.SAVE_ERROR')));
  }
};

const askDelete = tool => {
  pendingDelete.value = tool;
  deleteDialogRef.value?.open();
};

const performDelete = async () => {
  const tool = pendingDelete.value;
  deleteDialogRef.value?.close();
  if (!tool) return;
  try {
    await AthenasAPI.deleteCustomTool(props.assistantId, tool.id);
    useAlert(t('ATHENAS.EDIT.INTEGRATIONS.DELETE_SUCCESS'));
    await fetchTools();
  } catch (error) {
    useAlert(errorMessage(error, t('ATHENAS.EDIT.INTEGRATIONS.DELETE_ERROR')));
  } finally {
    pendingDelete.value = null;
  }
};
</script>

<template>
  <section class="flex flex-col gap-5">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.EDIT.INTEGRATIONS.TITLE') }}
        </h2>
        <p class="text-[13px] text-n-slate-11 max-w-2xl">
          {{ t('ATHENAS.EDIT.INTEGRATIONS.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="view === 'list' && tools.length"
        size="sm"
        icon="i-lucide-plus"
        :label="t('ATHENAS.EDIT.INTEGRATIONS.ADD')"
        @click="openCreate"
      />
    </header>

    <!-- Above the HTTP tools because it is the one integration with a real
         onboarding behind it: connecting is what makes the "Configurar
         negócio" tab exist. -->
    <AthenasCalendarConnect
      v-if="view === 'list'"
      :assistant-id="assistantId"
      @connected="$emit('calendarConnected')"
    />

    <AthenasIntegrationForm
      v-if="view === 'form'"
      :mode="editing ? 'edit' : 'create'"
      :tool="editing || {}"
      :saving="saving"
      @submit="handleSubmit"
      @cancel="closeForm"
    />

    <template v-else>
      <div v-if="loading" class="flex items-center justify-center py-16">
        <span
          class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
        />
      </div>

      <div
        v-else-if="!tools.length"
        class="flex flex-col items-center gap-3 py-16 text-center rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span
          class="size-12 rounded-2xl bg-gradient-to-br from-n-teal-3 to-transparent ring-1 ring-n-weak grid place-content-center"
        >
          <span class="i-lucide-plug size-6 text-n-teal-11" />
        </span>
        <p class="text-[13px] text-n-slate-11 max-w-sm">
          {{ t('ATHENAS.EDIT.INTEGRATIONS.EMPTY') }}
        </p>
        <Button
          size="sm"
          icon="i-lucide-plus"
          :label="t('ATHENAS.EDIT.INTEGRATIONS.ADD')"
          @click="openCreate"
        />
      </div>

      <div v-else class="flex flex-col gap-3">
        <article
          v-for="tool in tools"
          :key="tool.id"
          class="flex items-start justify-between gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <div class="flex flex-col gap-1.5 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-[13px] font-semibold text-n-slate-12">
                {{ tool.title }}
              </span>
              <span
                class="px-1.5 py-0.5 rounded-md text-[10px] font-mono font-medium bg-n-alpha-2 text-n-slate-11 ring-1 ring-n-weak"
              >
                {{ tool.http_method }}
              </span>
              <span
                class="px-2 py-0.5 rounded-full text-[10px] font-medium ring-1"
                :class="
                  tool.enabled
                    ? 'bg-n-teal-3 text-n-teal-11 ring-n-teal-6'
                    : 'bg-n-slate-3 text-n-slate-11 ring-n-weak'
                "
              >
                {{
                  tool.enabled
                    ? t('ATHENAS.EDIT.INTEGRATIONS.ENABLED')
                    : t('ATHENAS.EDIT.INTEGRATIONS.DISABLED')
                }}
              </span>
            </div>
            <p
              v-if="tool.description"
              class="text-[12px] text-n-slate-11 leading-relaxed"
            >
              {{ tool.description }}
            </p>
            <div
              class="flex items-center gap-2 text-[11px] text-n-slate-10 font-mono min-w-0"
            >
              <span class="truncate">{{ tool.endpoint_url }}</span>
            </div>
          </div>

          <div class="flex items-center gap-1 shrink-0">
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              :icon="
                tool.enabled ? 'i-lucide-toggle-right' : 'i-lucide-toggle-left'
              "
              :label="
                tool.enabled
                  ? t('ATHENAS.EDIT.INTEGRATIONS.DISABLE')
                  : t('ATHENAS.EDIT.INTEGRATIONS.ENABLE')
              "
              @click="toggleEnabled(tool)"
            />
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-pencil-line"
              @click="openEdit(tool)"
            />
            <Button
              variant="ghost"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              @click="askDelete(tool)"
            />
          </div>
        </article>
      </div>
    </template>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('ATHENAS.EDIT.INTEGRATIONS.DELETE_TITLE')"
      :description="
        pendingDelete
          ? t('ATHENAS.EDIT.INTEGRATIONS.DELETE_CONFIRM', {
              title: pendingDelete.title,
            })
          : ''
      "
      :confirm-button-label="
        t('ATHENAS.EDIT.INTEGRATIONS.DELETE_CONFIRM_BUTTON')
      "
      @confirm="performDelete"
    />
  </section>
</template>

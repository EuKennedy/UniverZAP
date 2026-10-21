<script setup>
/**
 * Montar uma campanha: onde sai (conexões), quando começa, se recomeça a cada
 * N dias e o fluxo de passos, cada um com dia, horário e repostagem.
 *
 * O fluxo é mostrado como uma linha do tempo, na ordem em que sai, porque é
 * assim que o dono pensa a campanha ("dia 1 anuncia, dia 3 lembra, dia 5
 * última chamada"). Antes de ativar, "Próximas postagens" mostra as datas
 * reais que o agendador vai usar.
 */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import CampaignsAPI from 'dashboard/api/whatsappStatusCampaigns';
import {
  apiErrorMessage,
  backgroundClass,
  browserTimeZone,
  CAMPAIGN_CYCLES,
  CAMPAIGN_STATUS_STYLE,
  dateLocale,
  STATUS_BACKGROUNDS,
  toDateInputValue,
} from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CampaignStepForm from './CampaignStepForm.vue';
import StatusPreview from './StatusPreview.vue';

const props = defineProps({
  campaignId: { type: Number, default: null },
  folders: { type: Array, default: () => [] },
  defaultFolderId: { type: [String, Number], default: '' },
  inboxes: { type: Array, required: true },
  accountName: { type: String, default: '' },
});

const emit = defineEmits(['close', 'saved']);

const { t, locale } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.${key}`);

const blank = () => ({
  id: null,
  name: '',
  description: '',
  color: STATUS_BACKGROUNDS[2].value,
  folderId:
    typeof props.defaultFolderId === 'number' ? props.defaultFolderId : '',
  inboxIds: props.inboxes.length ? [props.inboxes[0].id] : [],
  startsOn: toDateInputValue(new Date()),
  endsOn: '',
  cycleDays: 0,
  timeZone: browserTimeZone(),
  status: 'draft',
  steps: [],
  publishedCount: 0,
});

const campaign = ref(blank());
const preview = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const formError = ref('');
const stepFormRef = ref(null);

const isActive = computed(() => campaign.value.status === 'active');
const previewName = computed(
  () =>
    props.inboxes.find(inbox => campaign.value.inboxIds.includes(inbox.id))
      ?.name || ''
);
const folderOptions = computed(() => [
  { value: '', label: t('WHATSAPP_PROFILE.CAMPAIGNS.FOLDERS.UNFILED') },
  ...props.folders.map(folder => ({ value: folder.id, label: folder.name })),
]);
const cycleOptions = computed(() =>
  CAMPAIGN_CYCLES.map(days => ({
    value: days,
    label: days
      ? t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.CYCLE_EVERY', { days })
      : label('CYCLE_ONCE'),
  }))
);
// A linha do tempo segue a ordem de saída, não a ordem em que os passos
// foram criados: quem adiciona o "dia 0" depois ainda vê ele em primeiro.
const timeline = computed(() =>
  campaign.value.steps
    .map((step, index) => ({ step, index }))
    .sort(
      (a, b) =>
        a.step.dayOffset - b.step.dayOffset ||
        a.step.timeOfDay.localeCompare(b.step.timeOfDay)
    )
);
const totalPosts = computed(() =>
  campaign.value.steps.reduce((sum, step) => sum + 1 + step.repostCount, 0)
);

const fromApi = data => ({
  id: data.id,
  name: data.name,
  description: data.description || '',
  color: data.color || STATUS_BACKGROUNDS[2].value,
  folderId: data.folder_id || '',
  inboxIds: data.inbox_ids || [],
  startsOn: data.starts_on || '',
  endsOn: data.ends_on || '',
  cycleDays: data.cycle_days || 0,
  timeZone: data.time_zone || browserTimeZone(),
  status: data.status,
  publishedCount: data.published_count || 0,
  steps: (data.steps || []).map(step => ({
    id: step.id,
    kind: step.kind,
    body: step.body || '',
    backgroundColor: step.background_color || STATUS_BACKGROUNDS[0].value,
    font: step.font || 0,
    dayOffset: step.day_offset,
    timeOfDay: step.time_of_day,
    repostCount: step.repost_count,
    repostIntervalHours: step.repost_interval_hours,
    mediaUrl: step.media?.url || '',
  })),
});

const fetchPreview = async () => {
  if (!campaign.value.id) return;
  try {
    const { data } = await CampaignsAPI.preview(campaign.value.id);
    preview.value = data.payload || [];
  } catch {
    preview.value = [];
  }
};

const load = async () => {
  preview.value = [];
  formError.value = '';
  if (!props.campaignId) {
    campaign.value = blank();
    return;
  }
  isLoading.value = true;
  try {
    const { data } = await CampaignsAPI.find(props.campaignId);
    campaign.value = fromApi(data);
    await fetchPreview();
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
  } finally {
    isLoading.value = false;
  }
};

const toggleInbox = id => {
  const ids = campaign.value.inboxIds;
  campaign.value.inboxIds = ids.includes(id)
    ? ids.filter(item => item !== id)
    : [...ids, id];
};

const openStep = (step = null, index = null) =>
  stepFormRef.value?.open(step, index);

const saveStep = (step, index) => {
  const steps = [...campaign.value.steps];
  if (index === null) steps.push(step);
  else steps.splice(index, 1, step);
  campaign.value.steps = steps;
};

const duplicateStep = index => {
  const { id, blobId, ...copy } = campaign.value.steps[index];
  campaign.value.steps = [
    ...campaign.value.steps,
    { ...copy, dayOffset: copy.dayOffset + 1 },
  ];
};

const removeStep = index => {
  campaign.value.steps = campaign.value.steps.filter((_, i) => i !== index);
};

const run = async (request, successKey) => {
  isSaving.value = true;
  formError.value = '';
  try {
    const { data } = await request();
    campaign.value = fromApi(data);
    useAlert(label(successKey));
    emit('saved', data);
    await fetchPreview();
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
  } finally {
    isSaving.value = false;
  }
};

const save = () => {
  if (!campaign.value.name.trim()) {
    formError.value = label('NAME_REQUIRED');
    return null;
  }
  return run(() => CampaignsAPI.save(campaign.value), 'SAVED');
};

// Ativar salva antes: o operador não precisa lembrar de clicar em dois botões.
const activate = async () => {
  await save();
  if (formError.value || !campaign.value.id) return;
  await run(() => CampaignsAPI.activate(campaign.value.id), 'ACTIVATED');
};

const pause = () => run(() => CampaignsAPI.pause(campaign.value.id), 'PAUSED');

const remove = async () => {
  isSaving.value = true;
  try {
    await CampaignsAPI.remove(campaign.value.id);
    useAlert(label('DELETED'));
    emit('saved');
    emit('close');
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('WHATSAPP_PROFILE.ERRORS.GENERIC')
    );
  } finally {
    isSaving.value = false;
  }
};

const formatOccurrence = value =>
  new Date(value).toLocaleString(dateLocale(locale), {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

watch(() => props.campaignId, load, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-5" data-testid="campaign-editor">
    <div class="flex flex-wrap gap-3 items-center">
      <Button
        ghost
        slate
        size="sm"
        icon="i-lucide-arrow-left"
        :label="label('BACK')"
        data-testid="editor-back"
        @click="emit('close')"
      />
      <span
        class="px-2 py-0.5 text-[11px] font-medium rounded-md"
        :class="CAMPAIGN_STATUS_STYLE[campaign.status]"
        data-testid="editor-status"
      >
        {{
          t(
            `WHATSAPP_PROFILE.CAMPAIGNS.STATUS.${campaign.status.toUpperCase()}`
          )
        }}
      </span>
      <span v-if="campaign.publishedCount" class="text-[12px] text-n-slate-11">
        {{
          t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.PUBLISHED_COUNT', {
            count: campaign.publishedCount,
          })
        }}
      </span>
      <div class="flex flex-wrap gap-2 ms-auto">
        <Button
          v-if="campaign.id"
          ghost
          ruby
          size="sm"
          icon="i-lucide-trash-2"
          :label="label('DELETE')"
          data-testid="editor-delete"
          @click="remove"
        />
        <Button
          slate
          faded
          size="sm"
          icon="i-lucide-save"
          :label="label('SAVE')"
          :is-loading="isSaving"
          data-testid="editor-save"
          @click="save"
        />
        <Button
          v-if="isActive"
          size="sm"
          amber
          faded
          icon="i-lucide-pause"
          :label="label('PAUSE')"
          data-testid="editor-pause"
          @click="pause"
        />
        <Button
          v-else
          size="sm"
          icon="i-lucide-play"
          :label="label('ACTIVATE')"
          :is-loading="isSaving"
          data-testid="editor-activate"
          @click="activate"
        />
      </div>
    </div>

    <p
      v-if="formError"
      class="px-3 py-2 m-0 text-[13px] rounded-lg bg-n-ruby-3 text-n-ruby-11"
      data-testid="editor-error"
    >
      {{ formError }}
    </p>

    <section
      class="grid gap-4 p-5 rounded-xl border border-n-weak bg-n-solid-1 md:grid-cols-2"
    >
      <Input
        v-model="campaign.name"
        :label="label('NAME')"
        :placeholder="label('NAME_PLACEHOLDER')"
        data-testid="editor-name"
      />
      <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
        {{ label('FOLDER') }}
        <Select
          v-model="campaign.folderId"
          :options="folderOptions"
          data-testid="editor-folder"
        />
      </div>
      <Input
        v-model="campaign.description"
        class="md:col-span-2"
        :label="label('DESCRIPTION')"
        :placeholder="label('DESCRIPTION_PLACEHOLDER')"
      />

      <div class="flex flex-col gap-2 md:col-span-2">
        <span class="text-[13px] text-n-slate-12">{{ label('COLOR') }}</span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="color in STATUS_BACKGROUNDS"
            :key="color.value"
            type="button"
            class="rounded-full transition-transform size-6 hover:scale-110"
            :class="[
              color.className,
              campaign.color === color.value
                ? 'ring-2 ring-offset-2 ring-n-slate-12 ring-offset-n-solid-1'
                : '',
            ]"
            :aria-label="color.value"
            @click="campaign.color = color.value"
          />
        </div>
      </div>

      <div class="flex flex-col gap-2 md:col-span-2">
        <span class="text-[13px] text-n-slate-12">
          {{ t('WHATSAPP_PROFILE.STATUS.CONNECTIONS') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <label
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="flex gap-2 items-center px-3 py-1.5 text-[13px] rounded-lg border cursor-pointer border-n-weak text-n-slate-12"
            :class="campaign.inboxIds.includes(inbox.id) ? 'bg-n-alpha-2' : ''"
            :data-testid="`editor-connection-${inbox.id}`"
          >
            <Checkbox
              :model-value="campaign.inboxIds.includes(inbox.id)"
              @change="toggleInbox(inbox.id)"
            />
            {{ inbox.name }}
          </label>
        </div>
      </div>

      <label class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
        {{ label('STARTS_ON') }}
        <input
          v-model="campaign.startsOn"
          type="date"
          class="!mb-0 !h-9 !px-3 text-sm rounded-lg border-0 outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
          data-testid="editor-starts-on"
        />
      </label>
      <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
        {{ label('CYCLE') }}
        <Select
          v-model="campaign.cycleDays"
          :options="cycleOptions"
          data-testid="editor-cycle"
        />
      </div>
      <label
        v-if="campaign.cycleDays > 0"
        class="flex flex-col gap-1.5 text-[13px] text-n-slate-12"
      >
        {{ label('ENDS_ON') }}
        <input
          v-model="campaign.endsOn"
          type="date"
          :min="campaign.startsOn"
          class="!mb-0 !h-9 !px-3 text-sm rounded-lg border-0 outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
          data-testid="editor-ends-on"
        />
        <span class="text-[11px] text-n-slate-10">{{
          label('ENDS_ON_HINT')
        }}</span>
      </label>
    </section>

    <section
      class="flex flex-col gap-4 p-5 rounded-xl border border-n-weak bg-n-solid-1"
    >
      <div class="flex flex-wrap gap-3 justify-between items-center">
        <div class="flex flex-col gap-0.5">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ label('FLOW') }}
          </h3>
          <p class="m-0 text-[12px] text-n-slate-11">
            {{
              t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.FLOW_SUMMARY', {
                steps: campaign.steps.length,
                posts: totalPosts,
              })
            }}
          </p>
        </div>
        <Button
          size="sm"
          icon="i-lucide-plus"
          :label="label('ADD_STEP')"
          data-testid="add-step"
          @click="openStep()"
        />
      </div>

      <p
        v-if="!campaign.steps.length"
        class="py-6 m-0 text-[13px] text-center text-n-slate-11"
        data-testid="flow-empty"
      >
        {{ label('FLOW_EMPTY') }}
      </p>

      <ol
        v-else
        class="flex flex-col gap-0 p-0 m-0 list-none"
        data-testid="flow"
      >
        <li
          v-for="({ step, index }, position) in timeline"
          :key="`${index}-${step.id || 'new'}`"
          class="flex gap-4"
          data-testid="flow-step"
        >
          <div class="flex flex-col items-center">
            <span
              class="flex justify-center items-center text-[11px] font-bold rounded-full size-9 shrink-0 text-[#06131C]"
              :class="backgroundClass(campaign.color)"
            >
              {{
                t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.DAY_SHORT', {
                  day: step.dayOffset + 1,
                })
              }}
            </span>
            <span
              v-if="position < timeline.length - 1"
              class="flex-1 w-px my-1 bg-n-weak"
            />
          </div>
          <div
            class="flex flex-1 gap-3 items-start p-3 mb-3 min-w-0 rounded-xl border border-n-weak"
          >
            <StatusPreview
              compact
              :kind="step.kind"
              :body="step.body"
              :background-color="step.backgroundColor"
              :font="step.font"
              :media-url="step.mediaUrl"
            />
            <div class="flex flex-col flex-1 gap-1 min-w-0">
              <span class="text-[12px] font-semibold text-n-slate-12">
                {{
                  t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.STEP_WHEN', {
                    day: step.dayOffset + 1,
                    time: step.timeOfDay,
                  })
                }}
              </span>
              <p
                class="m-0 text-[13px] text-n-slate-11 line-clamp-2 break-words"
              >
                {{
                  step.body ||
                  t(
                    `WHATSAPP_PROFILE.HISTORY.NO_TEXT.${step.kind.toUpperCase()}`
                  )
                }}
              </p>
              <span
                v-if="step.repostCount"
                class="flex gap-1 items-center text-[11px] text-n-slate-10"
                data-testid="step-repost-info"
              >
                <span class="i-lucide-repeat-2 size-3" />
                {{
                  t('WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.REPOST_INFO', {
                    count: step.repostCount,
                    hours: step.repostIntervalHours,
                  })
                }}
              </span>
            </div>
            <div class="flex gap-0.5 shrink-0">
              <Button
                ghost
                slate
                size="xs"
                icon="i-lucide-pencil"
                :aria-label="label('EDIT_STEP')"
                data-testid="step-edit"
                @click="openStep(step, index)"
              />
              <Button
                ghost
                slate
                size="xs"
                icon="i-lucide-copy"
                :aria-label="label('DUPLICATE_STEP')"
                @click="duplicateStep(index)"
              />
              <Button
                ghost
                ruby
                size="xs"
                icon="i-lucide-trash-2"
                :aria-label="label('REMOVE_STEP')"
                data-testid="step-remove"
                @click="removeStep(index)"
              />
            </div>
          </div>
        </li>
      </ol>
    </section>

    <section
      v-if="campaign.id"
      class="flex flex-col gap-3 p-5 rounded-xl border border-n-weak bg-n-solid-1"
      data-testid="campaign-preview"
    >
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ label('NEXT_POSTS') }}
      </h3>
      <p v-if="!preview.length" class="m-0 text-[13px] text-n-slate-11">
        {{ label('NEXT_POSTS_EMPTY') }}
      </p>
      <ul v-else class="grid gap-2 p-0 m-0 list-none sm:grid-cols-2">
        <li
          v-for="occurrence in preview"
          :key="`${occurrence.at}-${occurrence.step_id}`"
          class="flex gap-2 items-center px-3 py-2 text-[12px] rounded-lg bg-n-alpha-1"
          data-testid="preview-item"
        >
          <span
            class="size-2 rounded-full shrink-0"
            :class="backgroundClass(campaign.color)"
          />
          <span class="font-semibold text-n-slate-12 whitespace-nowrap">
            {{ formatOccurrence(occurrence.at) }}
          </span>
          <span class="truncate text-n-slate-11">{{ occurrence.body }}</span>
          <span
            v-if="occurrence.repost"
            class="ms-auto i-lucide-repeat-2 size-3 text-n-slate-10 shrink-0"
          />
        </li>
      </ul>
    </section>

    <CampaignStepForm
      ref="stepFormRef"
      :preview-name="previewName"
      :account-name="accountName"
      @save="saveStep"
    />
  </div>
</template>

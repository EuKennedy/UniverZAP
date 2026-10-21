<script setup>
/**
 * O mês inteiro de status: o que já saiu, o que está agendado e de qual
 * campanha cada um veio, pela cor. Clicar num dia vazio abre o compositor já
 * agendado para aquele dia; arrastar um agendado para outro dia remarca,
 * mantendo o horário.
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';
import CampaignsAPI from 'dashboard/api/whatsappStatusCampaigns';
import {
  apiErrorMessage,
  backgroundClass,
  dateLocale,
  isSameDay,
  monthGrid,
  postDay,
} from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  refreshKey: { type: Number, default: 0 },
});

const emit = defineEmits(['edit', 'create', 'changed']);

const { t, locale } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.CALENDAR.${key}`);

const MAX_PER_DAY = 3;
const STATUS_ICON = {
  scheduled: 'i-lucide-clock',
  publishing: 'i-lucide-loader-circle',
  published: 'i-lucide-check',
  partially_published: 'i-lucide-triangle-alert',
  failed: 'i-lucide-x',
  draft: 'i-lucide-file-pen-line',
};

const reference = ref(new Date());
const posts = ref([]);
const campaigns = ref([]);
const campaignFilter = ref('');
const dragging = ref(null);
const dropDay = ref(null);

const days = computed(() => monthGrid(reference.value));
// "outubro de 2026" → "Outubro de 2026": só a primeira letra, para não
// virar "Outubro De 2026" como faria a classe capitalize.
const monthLabel = computed(() => {
  const text = reference.value.toLocaleDateString(dateLocale(locale), {
    month: 'long',
    year: 'numeric',
  });
  return text.charAt(0).toUpperCase() + text.slice(1);
});
const weekdays = computed(() =>
  days.value
    .slice(0, 7)
    .map(day =>
      day.toLocaleDateString(dateLocale(locale), { weekday: 'short' })
    )
);
const campaignOptions = computed(() => [
  { value: '', label: label('ALL_CAMPAIGNS') },
  ...campaigns.value.map(campaign => ({
    value: campaign.id,
    label: campaign.name,
  })),
]);
const legend = computed(() => {
  const seen = new Map();
  posts.value.forEach(post => {
    if (post.campaign && !seen.has(post.campaign.id))
      seen.set(post.campaign.id, post.campaign);
  });
  return [...seen.values()];
});

const today = new Date();
const isCurrentMonth = day => day.getMonth() === reference.value.getMonth();
const postsOn = day =>
  posts.value.filter(post => isSameDay(postDay(post), day));
const time = post =>
  postDay(post).toLocaleTimeString(dateLocale(locale), {
    hour: '2-digit',
    minute: '2-digit',
  });
const dotClass = post =>
  post.campaign ? backgroundClass(post.campaign.color) : 'bg-n-slate-9';

const fetchMonth = async () => {
  const grid = days.value;
  const until = new Date(grid.at(-1));
  until.setHours(23, 59, 59, 999);
  try {
    const { data } = await WhatsAppStatusAPI.list({
      from: grid[0].toISOString(),
      until: until.toISOString(),
      per: 200,
      campaignId: campaignFilter.value || undefined,
    });
    posts.value = (data.payload || []).filter(post => post.status !== 'draft');
  } catch {
    posts.value = [];
  }
};

const fetchCampaigns = async () => {
  try {
    const { data } = await CampaignsAPI.list();
    campaigns.value = data.payload || [];
  } catch {
    campaigns.value = [];
  }
};

const shiftMonth = delta => {
  const next = new Date(reference.value);
  next.setDate(1);
  next.setMonth(next.getMonth() + delta);
  reference.value = next;
};

const goToday = () => {
  reference.value = new Date();
};

// Só agendado pode ser arrastado: o que já saiu não volta no tempo.
const startDrag = (event, post) => {
  if (post.status !== 'scheduled') return;
  dragging.value = post;
  event.dataTransfer.effectAllowed = 'move';
};

const isPast = day => {
  const end = new Date(day);
  end.setHours(23, 59, 59, 999);
  return end < new Date();
};

const drop = async day => {
  const post = dragging.value;
  dragging.value = null;
  dropDay.value = null;
  if (!post || isSameDay(postDay(post), day) || isPast(day)) return;
  const original = postDay(post);
  const target = new Date(day);
  target.setHours(original.getHours(), original.getMinutes(), 0, 0);
  try {
    await WhatsAppStatusAPI.reschedule(post.id, target.toISOString());
    useAlert(label('RESCHEDULED'));
    await fetchMonth();
    emit('changed');
  } catch (error) {
    useAlert(apiErrorMessage(error, t('WHATSAPP_PROFILE.ERRORS.GENERIC')));
  }
};

const openDay = day => {
  if (isPast(day)) return;
  emit('create', day);
};

const openPost = post => {
  if (['scheduled', 'draft'].includes(post.status)) emit('edit', post);
};

watch([reference, campaignFilter], fetchMonth);
watch(
  () => props.refreshKey,
  () => {
    fetchMonth();
    fetchCampaigns();
  }
);
onMounted(() => {
  fetchMonth();
  fetchCampaigns();
});
</script>

<template>
  <section
    class="flex flex-col gap-4 p-5 rounded-xl border border-n-weak bg-n-solid-1"
    data-testid="status-calendar"
  >
    <div class="flex flex-wrap gap-3 items-center">
      <div class="flex gap-1 items-center">
        <Button
          slate
          faded
          size="sm"
          icon="i-lucide-chevron-left"
          :aria-label="label('PREVIOUS')"
          data-testid="calendar-prev"
          @click="shiftMonth(-1)"
        />
        <Button
          slate
          faded
          size="sm"
          icon="i-lucide-chevron-right"
          :aria-label="label('NEXT')"
          data-testid="calendar-next"
          @click="shiftMonth(1)"
        />
      </div>
      <h2
        class="m-0 text-lg font-bold text-n-slate-12"
        data-testid="calendar-month"
      >
        {{ monthLabel }}
      </h2>
      <Button ghost slate size="sm" :label="label('TODAY')" @click="goToday" />
      <div class="flex gap-2 items-center ms-auto">
        <Select
          v-model="campaignFilter"
          :options="campaignOptions"
          data-testid="calendar-campaign"
        />
      </div>
    </div>

    <div
      v-if="legend.length"
      class="flex flex-wrap gap-3 text-[11px] text-n-slate-11"
      data-testid="calendar-legend"
    >
      <span
        v-for="campaign in legend"
        :key="campaign.id"
        class="flex gap-1.5 items-center"
      >
        <span
          class="rounded-sm size-2.5"
          :class="backgroundClass(campaign.color)"
        />
        {{ campaign.name }}
      </span>
      <span class="flex gap-1.5 items-center">
        <span class="rounded-sm size-2.5 bg-n-slate-9" />
        {{ label('NO_CAMPAIGN') }}
      </span>
    </div>

    <div class="overflow-x-auto">
      <div
        class="grid grid-cols-7 min-w-[44rem] rounded-xl border border-n-weak overflow-hidden"
      >
        <span
          v-for="weekday in weekdays"
          :key="weekday"
          class="px-2 py-1.5 text-[11px] font-semibold tracking-wide uppercase border-b bg-n-alpha-1 border-n-weak text-n-slate-11"
        >
          {{ weekday }}
        </span>
        <div
          v-for="day in days"
          :key="day.toISOString()"
          class="flex flex-col gap-1 p-1.5 min-h-24 border-b border-e border-n-weak group"
          :class="[
            isCurrentMonth(day) ? '' : 'bg-n-alpha-1 opacity-60',
            dropDay && isSameDay(dropDay, day) ? '!bg-n-alpha-3' : '',
          ]"
          data-testid="calendar-day"
          @dragover.prevent="dropDay = day"
          @dragleave="dropDay = null"
          @drop.prevent="drop(day)"
        >
          <div class="flex justify-between items-center">
            <span
              class="flex justify-center items-center text-[11px] font-semibold rounded-full size-5"
              :class="
                isSameDay(day, today)
                  ? 'bg-brand-gradient text-[#06131C]'
                  : 'text-n-slate-11'
              "
            >
              {{ day.getDate() }}
            </span>
            <button
              v-if="!isPast(day)"
              type="button"
              class="hidden justify-center items-center rounded-md size-5 text-n-slate-11 hover:bg-n-alpha-2 group-hover:flex"
              :aria-label="label('ADD')"
              data-testid="calendar-add"
              @click="openDay(day)"
            >
              <span class="i-lucide-plus size-3.5" />
            </button>
          </div>
          <button
            v-for="post in postsOn(day).slice(0, MAX_PER_DAY)"
            :key="post.id"
            type="button"
            class="flex gap-1 items-center px-1.5 py-1 w-full text-[11px] rounded-md text-start bg-n-alpha-2 hover:bg-n-alpha-3"
            :class="
              post.status === 'scheduled'
                ? 'cursor-grab active:cursor-grabbing'
                : ''
            "
            :draggable="post.status === 'scheduled'"
            :title="post.body || ''"
            data-testid="calendar-post"
            @dragstart="event => startDrag(event, post)"
            @click="openPost(post)"
          >
            <span
              class="rounded-full size-2 shrink-0"
              :class="dotClass(post)"
            />
            <span class="font-semibold text-n-slate-12">{{ time(post) }}</span>
            <span class="flex-1 truncate text-n-slate-11">
              {{
                post.campaign?.name ||
                post.body ||
                t(`WHATSAPP_PROFILE.HISTORY.NO_TEXT.${post.kind.toUpperCase()}`)
              }}
            </span>
            <span
              class="size-3 shrink-0 text-n-slate-10"
              :class="STATUS_ICON[post.status]"
            />
          </button>
          <span
            v-if="postsOn(day).length > MAX_PER_DAY"
            class="px-1.5 text-[10px] text-n-slate-10"
          >
            {{
              t('WHATSAPP_PROFILE.CALENDAR.MORE', {
                count: postsOn(day).length - MAX_PER_DAY,
              })
            }}
          </span>
        </div>
      </div>
    </div>
    <p class="m-0 text-[11px] text-n-slate-10">{{ label('HINT') }}</p>
  </section>
</template>

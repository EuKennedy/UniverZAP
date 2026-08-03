<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import Button from 'dashboard/components-next/button/Button.vue';

// The commercial half of the module. Everything above this tab answers "is the
// agent good"; this one answers "is it worth paying for", which is the question
// that decides whether the operator tops up credits again.
const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();

const BANDS = ['hot', 'warm', 'cold'];

const data = ref(null);
const loading = ref(false);
const band = ref(null);
const selected = ref([]);
const message = ref('');
const composing = ref(false);
const busy = ref(false);

const items = computed(() => data.value?.items || []);
const counts = computed(() => data.value?.counts || {});
const roi = computed(() => data.value?.roi || {});

const brl = value =>
  (value || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const bandClass = value =>
  ({
    hot: 'bg-n-ruby-3 text-n-ruby-11 ring-n-ruby-6',
    warm: 'bg-n-amber-3 text-n-amber-11 ring-n-amber-6',
    cold: 'bg-n-slate-3 text-n-slate-11 ring-n-weak',
  })[value];

const bandLabel = value => t(`ATHENAS.RADAR.BANDS.${value.toUpperCase()}`);

const reasonLabel = reason =>
  reason ? t(`ATHENAS.RADAR.REASONS.${reason.toUpperCase()}`) : '';

const fetchRadar = async () => {
  loading.value = true;
  try {
    const { data: payload } = await AthenasAPI.listOpportunities(
      props.assistantId,
      { band: band.value, status: 'open' }
    );
    data.value = payload;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

// What customers keep asking. A term that shows up forty times is either a page
// the operator should write or a product they should stock.
const themes = ref([]);

const fetchThemes = async () => {
  try {
    const { data: payload } = await AthenasAPI.themes(props.assistantId);
    themes.value = payload.themes || [];
  } catch {
    themes.value = [];
  }
};

onMounted(() => {
  fetchRadar();
  fetchThemes();
});

const setBand = value => {
  band.value = band.value === value ? null : value;
  selected.value = [];
  fetchRadar();
};

const toggle = id => {
  selected.value = selected.value.includes(id)
    ? selected.value.filter(item => item !== id)
    : [...selected.value, id];
};

const sendFollowUp = async () => {
  busy.value = true;
  try {
    await AthenasAPI.bulkFollowUp(props.assistantId, {
      opportunityIds: selected.value,
      message: message.value,
    });
    composing.value = false;
    message.value = '';
    selected.value = [];
    await fetchRadar();
  } finally {
    busy.value = false;
  }
};

const mark = async (opportunity, status) => {
  busy.value = true;
  try {
    await AthenasAPI.updateOpportunity(props.assistantId, opportunity.id, {
      status,
      won_brl: status === 'won' ? opportunity.potential_brl : undefined,
    });
    await fetchRadar();
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col gap-5">
    <header class="flex flex-col gap-1">
      <h2 class="text-base font-semibold text-n-slate-12 tracking-tight">
        {{ t('ATHENAS.RADAR.TITLE') }}
      </h2>
      <p class="text-[13px] text-n-slate-11 max-w-2xl">
        {{ t('ATHENAS.RADAR.SUBTITLE') }}
      </p>
    </header>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div
        class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
          {{ t('ATHENAS.RADAR.REVENUE') }}
        </span>
        <span class="text-2xl font-semibold text-n-slate-12 tabular-nums">
          {{ brl(roi.revenue_brl) }}
        </span>
        <span class="text-[11px] text-n-slate-10">
          {{ t('ATHENAS.RADAR.COST', { value: brl(roi.cost_brl) }) }}
        </span>
      </div>
      <div
        class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
          {{ t('ATHENAS.RADAR.ROI') }}
        </span>
        <span
          class="text-2xl font-semibold tabular-nums"
          :class="roi.roi ? 'text-n-teal-11' : 'text-n-slate-12'"
        >
          {{ roi.roi ? `${roi.roi}x` : t('ATHENAS.RADAR.NO_DATA') }}
        </span>
        <span
          v-if="roi.cost_per_conversation_brl"
          class="text-[11px] text-n-slate-10"
        >
          {{
            t('ATHENAS.RADAR.PER_CONVERSATION', {
              value: brl(roi.cost_per_conversation_brl),
            })
          }}
        </span>
      </div>
      <div
        class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
          {{ t('ATHENAS.RADAR.HOURS_SAVED') }}
        </span>
        <span class="text-2xl font-semibold text-n-slate-12 tabular-nums">
          {{ `${roi.hours_saved || 0}h` }}
        </span>
        <span class="text-[11px] text-n-slate-10">
          {{ t('ATHENAS.RADAR.HOURS_ASSUMPTION') }}
        </span>
      </div>
      <div
        class="flex flex-col gap-1 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
          {{ t('ATHENAS.RADAR.AFTER_HOURS') }}
        </span>
        <span class="text-2xl font-semibold text-n-teal-11 tabular-nums">
          {{ brl(roi.after_hours_revenue_brl) }}
        </span>
        <span class="text-[11px] text-n-slate-10">
          {{ t('ATHENAS.RADAR.AFTER_HOURS_HINT') }}
        </span>
      </div>
    </div>

    <div class="flex items-center justify-between gap-3 flex-wrap">
      <div class="flex items-center gap-1 p-0.5 rounded-lg bg-n-alpha-2">
        <button
          v-for="option in BANDS"
          :key="option"
          type="button"
          class="px-3 py-1 rounded-md text-[12px] font-medium transition-colors tabular-nums"
          :class="
            band === option
              ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setBand(option)"
        >
          {{ bandLabel(option) }}
          <span v-if="counts[option]" class="ml-1 opacity-60">
            {{ counts[option] }}
          </span>
        </button>
      </div>
      <Button
        v-if="selected.length"
        size="sm"
        icon="i-lucide-send"
        :label="t('ATHENAS.RADAR.FOLLOW_UP', { n: selected.length })"
        @click="composing = true"
      />
    </div>

    <div
      v-if="composing"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
    >
      <p class="text-[12px] text-n-slate-11">
        {{ t('ATHENAS.RADAR.FOLLOW_UP_HELP') }}
      </p>
      <textarea
        v-model="message"
        rows="3"
        class="w-full px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-n-weak text-[13px] text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-n-teal-8"
        :placeholder="t('ATHENAS.RADAR.FOLLOW_UP_PLACEHOLDER')"
      />
      <div class="flex items-center justify-end gap-2">
        <Button
          variant="ghost"
          size="sm"
          :label="t('ATHENAS.RADAR.CANCEL')"
          @click="composing = false"
        />
        <Button
          size="sm"
          :label="t('ATHENAS.RADAR.SEND')"
          :disabled="busy || !message.trim()"
          @click="sendFollowUp"
        />
      </div>
    </div>

    <div v-if="loading" class="flex items-center justify-center py-16">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </div>

    <div
      v-else-if="!items.length"
      class="flex flex-col items-center gap-2 py-16 text-center rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
    >
      <span
        class="size-12 rounded-2xl bg-gradient-to-br from-n-teal-3 to-transparent ring-1 ring-n-weak grid place-content-center"
      >
        <span class="i-lucide-radar size-6 text-n-teal-11" />
      </span>
      <p class="text-[13px] text-n-slate-11 max-w-xs">
        {{ t('ATHENAS.RADAR.EMPTY') }}
      </p>
    </div>

    <article
      v-for="item in items"
      :key="item.id"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 transition-colors"
      :class="selected.includes(item.id) ? 'ring-n-teal-8' : 'ring-n-weak'"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="flex items-start gap-3 min-w-0">
          <input
            type="checkbox"
            class="mt-1 size-4 rounded accent-n-teal-9"
            :checked="selected.includes(item.id)"
            @change="toggle(item.id)"
          />
          <div class="flex flex-col gap-0.5 min-w-0">
            <span class="text-[13px] font-medium text-n-slate-12 truncate">
              {{ item.contact_name || t('ATHENAS.RADAR.NO_NAME') }}
            </span>
            <span v-if="item.interest" class="text-[12px] text-n-slate-11">
              {{ item.interest }}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <span
            v-if="item.potential_brl"
            class="text-[13px] font-semibold text-n-slate-12 tabular-nums"
          >
            {{ brl(item.potential_brl) }}
          </span>
          <span
            class="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium ring-1 tabular-nums"
            :class="bandClass(item.band)"
          >
            {{ item.temperature }}
          </span>
        </div>
      </div>

      <div
        class="flex flex-wrap items-center gap-3 text-[11px] text-n-slate-10"
      >
        <span v-if="item.block_reason">{{
          reasonLabel(item.block_reason)
        }}</span>
        <span v-if="item.suggested_action" class="text-n-teal-11">
          {{ item.suggested_action }}
        </span>
      </div>

      <div class="flex items-center gap-2">
        <Button
          variant="ghost"
          size="sm"
          icon="i-lucide-check"
          :label="t('ATHENAS.RADAR.WON')"
          :disabled="busy"
          @click="mark(item, 'won')"
        />
        <Button
          variant="ghost"
          size="sm"
          icon="i-lucide-x"
          :label="t('ATHENAS.RADAR.LOST')"
          :disabled="busy"
          @click="mark(item, 'lost')"
        />
      </div>
    </article>
    <div
      v-if="themes.length"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
    >
      <span class="text-[13px] font-medium text-n-slate-12">
        {{ t('ATHENAS.RADAR.THEMES') }}
      </span>
      <p class="text-[12px] text-n-slate-11">
        {{ t('ATHENAS.RADAR.THEMES_HELP') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <span
          v-for="theme in themes"
          :key="theme.term"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[12px] bg-n-alpha-1 ring-1 ring-n-weak text-n-slate-11"
          :title="theme.sample"
        >
          {{ theme.term }}
          <span class="text-n-slate-10 tabular-nums">{{ theme.count }}</span>
        </span>
      </div>
    </div>
  </section>
</template>

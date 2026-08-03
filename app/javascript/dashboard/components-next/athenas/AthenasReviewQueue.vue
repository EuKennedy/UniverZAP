<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import Button from 'dashboard/components-next/button/Button.vue';

// The work queue. Everything here exists to answer one question fast: what did
// the agent get wrong, and what should it have said instead. Ordering comes
// from the server (guardrail severity, then recency) so the top of the list is
// always the most expensive mistake still unreviewed.
const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();

const FILTERS = ['all', 'flagged', 'unreviewed', 'reviewed'];
const REASONS = [
  'info_incorreta',
  'preco_inventado',
  'tom_inadequado',
  'deveria_transbordar',
  'nao_entendeu',
];
// Corrections that take effect on the next customer. Tone is not among them:
// it changes the agent everywhere, so it waits for a tested prompt version.
const IMMEDIATE_REASONS = [
  'info_incorreta',
  'preco_inventado',
  'deveria_transbordar',
  'nao_entendeu',
];
const SEVERE_FLAGS = [
  'preco_inventado',
  'horario_divergente',
  'cliente_insatisfeito',
];

const data = ref(null);
const loading = ref(false);
const filter = ref('flagged');
const page = ref(1);
// id of the response whose correction panel is open
const correcting = ref(null);
const draftReason = ref('info_incorreta');
const draftText = ref('');
const saving = ref(false);

const items = computed(() => data.value?.items || []);
const counts = computed(() => data.value?.counts || {});
const total = computed(() => data.value?.total || 0);
const perPage = computed(() => data.value?.per_page || 25);
const lastPage = computed(() =>
  Math.max(1, Math.ceil(total.value / perPage.value))
);

const flagLabel = flag => t(`ATHENAS.ANALYTICS.FLAGS.${flag.toUpperCase()}`);
const reasonLabel = reason =>
  t(`ATHENAS.REVIEW.REASONS.${reason.toUpperCase()}`);

const flagClass = flag =>
  SEVERE_FLAGS.includes(flag)
    ? 'bg-n-ruby-3 text-n-ruby-11 ring-n-ruby-6'
    : 'bg-n-amber-3 text-n-amber-11 ring-n-amber-6';

const timeAgo = epoch => {
  const mins = Math.round(Date.now() / 1000 - epoch) / 60;
  if (mins < 60) return t('ATHENAS.ANALYTICS.AGO_MIN', { n: Math.round(mins) });
  if (mins < 1440) {
    return t('ATHENAS.ANALYTICS.AGO_HOUR', { n: Math.round(mins / 60) });
  }
  return t('ATHENAS.ANALYTICS.AGO_DAY', { n: Math.round(mins / 1440) });
};

const fetchQueue = async () => {
  loading.value = true;
  try {
    const { data: payload } = await AthenasAPI.listResponses(
      props.assistantId,
      {
        filter: filter.value,
        page: page.value,
      }
    );
    data.value = payload;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

watch([filter, page], fetchQueue);
onMounted(fetchQueue);

const setFilter = value => {
  filter.value = value;
  page.value = 1;
};

// Replaces the row in place instead of refetching: losing your scroll position
// after every rating is what makes a queue unusable at volume.
const applyLocal = (responseId, feedback) => {
  const row = items.value.find(item => item.id === responseId);
  if (row) row.feedback = feedback;
};

const rate = async (item, rating, extra = {}) => {
  saving.value = true;
  try {
    const { data: feedback } = await AthenasAPI.rateResponse(
      props.assistantId,
      item.id,
      { rating, ...extra }
    );
    applyLocal(item.id, feedback);
    correcting.value = null;
    draftText.value = '';
  } finally {
    saving.value = false;
  }
};

const openCorrection = item => {
  correcting.value = correcting.value === item.id ? null : item.id;
  draftReason.value =
    item.auto_flag === 'preco_inventado' ? 'preco_inventado' : 'info_incorreta';
  draftText.value = item.feedback?.corrected_text || '';
};

const submitCorrection = item =>
  rate(item, 'down', {
    reason: draftReason.value,
    corrected_text: draftText.value,
  });

const willApplyNow = computed(
  () => IMMEDIATE_REASONS.includes(draftReason.value) && draftText.value.trim()
);
</script>

<template>
  <section class="flex flex-col gap-5">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.REVIEW.TITLE') }}
        </h2>
        <p class="text-[13px] text-n-slate-11 max-w-2xl">
          {{ t('ATHENAS.REVIEW.SUBTITLE') }}
        </p>
      </div>
      <div
        v-if="
          counts.approval_rate !== null && counts.approval_rate !== undefined
        "
        class="flex flex-col items-end gap-0.5 px-4 py-2.5 rounded-xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span class="text-[11px] uppercase tracking-wider text-n-slate-11">
          {{ t('ATHENAS.REVIEW.APPROVAL') }}
        </span>
        <span class="text-xl font-semibold text-n-slate-12 tabular-nums">
          {{ `${counts.approval_rate}%` }}
        </span>
        <span class="text-[11px] text-n-slate-10 tabular-nums">
          {{ t('ATHENAS.REVIEW.REVIEWED_COUNT', { n: counts.reviewed }) }}
        </span>
      </div>
    </header>

    <div class="flex items-center gap-1 p-0.5 rounded-lg bg-n-alpha-2 w-fit">
      <button
        v-for="option in FILTERS"
        :key="option"
        type="button"
        class="px-3 py-1 rounded-md text-[12px] font-medium transition-colors tabular-nums"
        :class="
          filter === option
            ? 'bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="setFilter(option)"
      >
        {{ t(`ATHENAS.REVIEW.FILTERS.${option.toUpperCase()}`) }}
        <span
          v-if="option === 'flagged' && counts.flagged"
          class="ml-1 opacity-60"
        >
          {{ counts.flagged }}
        </span>
        <span
          v-if="option === 'unreviewed' && counts.unreviewed"
          class="ml-1 opacity-60"
        >
          {{ counts.unreviewed }}
        </span>
      </button>
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
        <span class="i-lucide-shield-check size-6 text-n-teal-11" />
      </span>
      <p class="text-[13px] text-n-slate-11 max-w-xs">
        {{ t('ATHENAS.REVIEW.EMPTY') }}
      </p>
    </div>

    <template v-else>
      <article
        v-for="item in items"
        :key="item.id"
        class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <p
          v-if="item.user_message"
          class="text-[12px] text-n-slate-11 leading-relaxed pl-3 border-l-2 border-n-weak"
        >
          {{ item.user_message }}
        </p>
        <p
          class="text-[13px] text-n-slate-12 leading-relaxed whitespace-pre-wrap"
        >
          {{ item.ai_response }}
        </p>

        <div
          class="flex flex-wrap items-center gap-2 text-[11px] text-n-slate-10 tabular-nums"
        >
          <span
            v-for="flag in item.auto_flags"
            :key="flag"
            class="inline-flex items-center px-2 py-0.5 rounded-full font-medium ring-1"
            :class="flagClass(flag)"
          >
            {{ flagLabel(flag) }}
          </span>
          <span
            v-if="item.delivery_status === 'failed'"
            class="inline-flex items-center px-2 py-0.5 rounded-full font-medium ring-1 bg-n-slate-3 text-n-slate-11 ring-n-weak"
          >
            {{ t('ATHENAS.REVIEW.NOT_DELIVERED') }}
          </span>
          <span v-for="source in item.sources" :key="source" class="opacity-80">
            {{ t('ATHENAS.REVIEW.SOURCE', { title: source }) }}
          </span>
          <span>{{ timeAgo(item.created_at) }}</span>
        </div>

        <div
          v-if="item.feedback"
          class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-xl bg-n-alpha-1 text-[12px]"
        >
          <span class="i-lucide-check size-3.5 text-n-teal-11" />
          <span class="text-n-slate-11">
            {{
              item.feedback.rating === 'down'
                ? t('ATHENAS.REVIEW.RECORDED_CORRECTION', {
                    reason: reasonLabel(item.feedback.reason),
                  })
                : t(
                    `ATHENAS.REVIEW.RECORDED_${item.feedback.rating.toUpperCase()}`
                  )
            }}
          </span>
          <span
            v-if="item.feedback.applied_at"
            class="text-n-teal-11 font-medium"
          >
            {{ t('ATHENAS.REVIEW.APPLIED') }}
          </span>
          <span
            v-else-if="item.feedback.rating === 'down'"
            class="text-n-amber-11"
          >
            {{ t('ATHENAS.REVIEW.PENDING_APPLY') }}
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            icon="i-lucide-thumbs-up"
            :label="t('ATHENAS.REVIEW.GOOD')"
            :disabled="saving"
            @click="rate(item, 'up')"
          />
          <Button
            variant="ghost"
            size="sm"
            icon="i-lucide-star"
            :label="t('ATHENAS.REVIEW.IDEAL')"
            :disabled="saving"
            @click="rate(item, 'ideal')"
          />
          <Button
            variant="ghost"
            size="sm"
            color="ruby"
            icon="i-lucide-pencil-line"
            :label="t('ATHENAS.REVIEW.CORRECT')"
            :disabled="saving"
            @click="openCorrection(item)"
          />
        </div>

        <div
          v-if="correcting === item.id"
          class="flex flex-col gap-3 p-3 rounded-xl bg-n-alpha-1 ring-1 ring-n-weak"
        >
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="reason in REASONS"
              :key="reason"
              type="button"
              class="px-2.5 py-1 rounded-md text-[11px] font-medium transition-colors ring-1"
              :class="
                draftReason === reason
                  ? 'bg-n-teal-3 text-n-teal-11 ring-n-teal-6'
                  : 'bg-n-solid-1 text-n-slate-11 ring-n-weak hover:text-n-slate-12'
              "
              @click="draftReason = reason"
            >
              {{ reasonLabel(reason) }}
            </button>
          </div>
          <textarea
            v-model="draftText"
            rows="3"
            class="w-full px-3 py-2 rounded-lg bg-n-solid-1 ring-1 ring-n-weak text-[13px] text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-n-teal-8"
            :placeholder="t('ATHENAS.REVIEW.CORRECTION_PLACEHOLDER')"
          />
          <div class="flex items-center justify-between gap-3 flex-wrap">
            <p class="text-[11px] text-n-slate-10 max-w-md">
              {{
                willApplyNow
                  ? t('ATHENAS.REVIEW.WILL_APPLY_NOW')
                  : t('ATHENAS.REVIEW.WILL_WAIT_VERSION')
              }}
            </p>
            <Button
              size="sm"
              :label="t('ATHENAS.REVIEW.SAVE_CORRECTION')"
              :disabled="saving || !draftText.trim()"
              @click="submitCorrection(item)"
            />
          </div>
        </div>
      </article>

      <div
        v-if="lastPage > 1"
        class="flex items-center justify-between gap-3 pt-1"
      >
        <Button
          variant="ghost"
          size="sm"
          icon="i-lucide-chevron-left"
          :label="t('ATHENAS.REVIEW.PREV')"
          :disabled="page <= 1"
          @click="page -= 1"
        />
        <span class="text-[12px] text-n-slate-10 tabular-nums">
          {{ t('ATHENAS.REVIEW.PAGE', { page, total: lastPage }) }}
        </span>
        <Button
          variant="ghost"
          size="sm"
          icon="i-lucide-chevron-right"
          trailing-icon
          :label="t('ATHENAS.REVIEW.NEXT')"
          :disabled="page >= lastPage"
          @click="page += 1"
        />
      </div>
    </template>
  </section>
</template>

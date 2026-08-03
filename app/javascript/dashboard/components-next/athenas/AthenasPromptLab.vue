<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import Button from 'dashboard/components-next/button/Button.vue';

// The lab. A candidate version answers the same real questions the live agent
// already answered, side by side, and a human votes. Nothing here can reach a
// customer: the replay has no conversation to reply into.
const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();

const CHECKS = ['sample', 'win_rate', 'critical_losses', 'cost', 'latency'];

const versions = ref([]);
const live = ref(null);
const selected = ref(null);
const draftPrompt = ref('');
const report = ref(null);
const duels = ref([]);
// Reviewers vote for the column they were told is new, so the origin of each
// column stays hidden until the vote lands.
const blind = ref(true);
const loading = ref(false);
const busy = ref(false);
const editing = ref(false);

const pending = computed(() => duels.value.filter(duel => !duel.winner));
const candidates = computed(() =>
  versions.value.filter(version => version.status !== 'live')
);

const statusClass = status =>
  ({
    live: 'bg-n-teal-3 text-n-teal-11 ring-n-teal-6',
    testing: 'bg-n-amber-3 text-n-amber-11 ring-n-amber-6',
    draft: 'bg-n-slate-3 text-n-slate-11 ring-n-weak',
    archived: 'bg-n-slate-3 text-n-slate-10 ring-n-weak',
  })[status];

const checkLabel = key => t(`ATHENAS.LAB.CHECKS.${key.toUpperCase()}`);

const formatCheck = (key, check) => {
  if (check.value === null || check.value === undefined) return '—';
  if (key === 'win_rate') return `${Math.round(check.value * 100)}%`;
  if (key === 'cost') return `${check.value}x`;
  if (key === 'latency') return `${(check.value / 1000).toFixed(1)}s`;
  return `${check.value}`;
};

const loadVersions = async () => {
  const { data } = await AthenasAPI.listPromptVersions(props.assistantId);
  versions.value = data.versions || [];
  live.value = data.live || null;
  if (!selected.value) selected.value = candidates.value[0] || null;
};

const loadDuels = async () => {
  if (!selected.value) {
    duels.value = [];
    return;
  }
  const [{ data: comparisons }, { data: stats }] = await Promise.all([
    AthenasAPI.listComparisons(props.assistantId, {
      versionId: selected.value.id,
    }),
    AthenasAPI.promotionStats(props.assistantId, selected.value.id),
  ]);
  duels.value = comparisons.items || [];
  report.value = stats;
};

const refresh = async () => {
  loading.value = true;
  try {
    await loadVersions();
    await loadDuels();
  } finally {
    loading.value = false;
  }
};

onMounted(refresh);

const select = async version => {
  selected.value = version;
  await loadDuels();
};

const createDraft = async () => {
  busy.value = true;
  try {
    const { data } = await AthenasAPI.createPromptVersion(props.assistantId, {
      system_prompt: draftPrompt.value || undefined,
    });
    editing.value = false;
    draftPrompt.value = '';
    await refresh();
    await select(data);
  } finally {
    busy.value = false;
  }
};

const runLab = async () => {
  busy.value = true;
  try {
    await AthenasAPI.replayPromptVersion(props.assistantId, selected.value.id);
  } finally {
    busy.value = false;
  }
};

const vote = async (duel, winner) => {
  const { data } = await AthenasAPI.judgeComparison(
    props.assistantId,
    duel.id,
    winner
  );
  Object.assign(duel, data);
  const { data: stats } = await AthenasAPI.promotionStats(
    props.assistantId,
    selected.value.id
  );
  report.value = stats;
};

const promote = async () => {
  busy.value = true;
  try {
    await AthenasAPI.promotePromptVersion(props.assistantId, selected.value.id);
    await refresh();
  } finally {
    busy.value = false;
  }
};

const rollback = async () => {
  busy.value = true;
  try {
    await AthenasAPI.rollbackPromptVersion(props.assistantId);
    await refresh();
  } finally {
    busy.value = false;
  }
};

const openEditor = () => {
  editing.value = true;
  draftPrompt.value = '';
};
</script>

<template>
  <section class="flex flex-col gap-5">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.LAB.TITLE') }}
        </h2>
        <p class="text-[13px] text-n-slate-11 max-w-2xl">
          {{ t('ATHENAS.LAB.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          v-if="live"
          variant="ghost"
          size="sm"
          icon="i-lucide-undo-2"
          :label="t('ATHENAS.LAB.ROLLBACK')"
          :disabled="busy"
          @click="rollback"
        />
        <Button
          size="sm"
          icon="i-lucide-plus"
          :label="t('ATHENAS.LAB.NEW_VERSION')"
          :disabled="busy"
          @click="openEditor"
        />
      </div>
    </header>

    <div v-if="loading" class="flex items-center justify-center py-16">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </div>

    <template v-else>
      <div
        v-if="editing"
        class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <p class="text-[12px] text-n-slate-11">
          {{ t('ATHENAS.LAB.DRAFT_HELP') }}
        </p>
        <textarea
          v-model="draftPrompt"
          rows="6"
          class="w-full px-3 py-2 rounded-lg bg-n-alpha-1 ring-1 ring-n-weak text-[13px] text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-n-teal-8 font-mono"
          :placeholder="t('ATHENAS.LAB.DRAFT_PLACEHOLDER')"
        />
        <div class="flex items-center justify-end gap-2">
          <Button
            variant="ghost"
            size="sm"
            :label="t('ATHENAS.LAB.CANCEL')"
            @click="editing = false"
          />
          <Button
            size="sm"
            :label="t('ATHENAS.LAB.CREATE_DRAFT')"
            :disabled="busy"
            @click="createDraft"
          />
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <span
          v-if="live"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[12px] font-medium ring-1"
          :class="statusClass('live')"
        >
          {{ t('ATHENAS.LAB.LIVE_NOW', { version: live.version }) }}
        </span>
        <button
          v-for="version in candidates"
          :key="version.id"
          type="button"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[12px] font-medium ring-1 transition-colors"
          :class="[
            statusClass(version.status),
            selected && selected.id === version.id
              ? 'ring-n-teal-8'
              : 'opacity-70 hover:opacity-100',
          ]"
          @click="select(version)"
        >
          {{ version.version }}
        </button>
      </div>

      <div
        v-if="!selected"
        class="flex flex-col items-center gap-2 py-16 text-center rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
      >
        <span
          class="size-12 rounded-2xl bg-gradient-to-br from-n-teal-3 to-transparent ring-1 ring-n-weak grid place-content-center"
        >
          <span class="i-lucide-flask-conical size-6 text-n-teal-11" />
        </span>
        <p class="text-[13px] text-n-slate-11 max-w-xs">
          {{ t('ATHENAS.LAB.EMPTY') }}
        </p>
      </div>

      <template v-else>
        <div
          class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <div class="flex items-center justify-between gap-3 flex-wrap">
            <span class="text-[13px] font-medium text-n-slate-12">
              {{ t('ATHENAS.LAB.CRITERIA') }}
            </span>
            <div class="flex items-center gap-2">
              <Button
                variant="ghost"
                size="sm"
                icon="i-lucide-play"
                :label="t('ATHENAS.LAB.RUN')"
                :disabled="busy"
                @click="runLab"
              />
              <Button
                size="sm"
                icon="i-lucide-rocket"
                :label="t('ATHENAS.LAB.PROMOTE')"
                :disabled="busy || !report || !report.promotable"
                @click="promote"
              />
            </div>
          </div>
          <div v-if="report" class="grid grid-cols-2 lg:grid-cols-5 gap-2">
            <div
              v-for="key in CHECKS"
              :key="key"
              class="flex flex-col gap-0.5 px-3 py-2 rounded-xl ring-1"
              :class="
                report.checks[key].pass
                  ? 'bg-n-teal-2 ring-n-teal-6'
                  : 'bg-n-alpha-1 ring-n-weak'
              "
            >
              <span
                class="text-[10px] uppercase tracking-wider text-n-slate-11"
              >
                {{ checkLabel(key) }}
              </span>
              <span
                class="text-[15px] font-semibold tabular-nums"
                :class="
                  report.checks[key].pass ? 'text-n-teal-11' : 'text-n-slate-12'
                "
              >
                {{ formatCheck(key, report.checks[key]) }}
              </span>
            </div>
          </div>
        </div>

        <div class="flex items-center justify-between gap-3">
          <span class="text-[13px] font-medium text-n-slate-12">
            {{ t('ATHENAS.LAB.DUELS', { n: pending.length }) }}
          </span>
          <button
            type="button"
            class="text-[12px] text-n-slate-11 hover:text-n-slate-12"
            @click="blind = !blind"
          >
            {{ blind ? t('ATHENAS.LAB.BLIND_ON') : t('ATHENAS.LAB.BLIND_OFF') }}
          </button>
        </div>

        <p v-if="!duels.length" class="text-[12px] text-n-slate-11">
          {{ t('ATHENAS.LAB.NO_DUELS') }}
        </p>

        <article
          v-for="duel in duels"
          :key="duel.id"
          class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <p
            class="text-[12px] text-n-slate-11 leading-relaxed pl-3 border-l-2 border-n-weak"
          >
            {{ duel.user_message }}
          </p>
          <div class="grid md:grid-cols-2 gap-3">
            <div
              class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 ring-1"
              :class="
                duel.winner === 'a' ? 'ring-n-teal-7' : 'ring-transparent'
              "
            >
              <span
                class="text-[11px] uppercase tracking-wider text-n-slate-11"
              >
                {{
                  blind ? t('ATHENAS.LAB.COLUMN_1') : t('ATHENAS.LAB.COLUMN_A')
                }}
              </span>
              <p
                class="text-[13px] text-n-slate-12 leading-relaxed whitespace-pre-wrap"
              >
                {{ duel.response_a }}
              </p>
              <span
                v-if="!blind"
                class="text-[11px] text-n-slate-10 tabular-nums"
              >
                {{
                  t('ATHENAS.LAB.TELEMETRY', {
                    cost: (duel.telemetry_a.cost_brl || 0).toFixed(3),
                    latency: (
                      (duel.telemetry_a.latency_ms || 0) / 1000
                    ).toFixed(1),
                  })
                }}
              </span>
            </div>
            <div
              class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 ring-1"
              :class="
                duel.winner === 'b' ? 'ring-n-teal-7' : 'ring-transparent'
              "
            >
              <span
                class="text-[11px] uppercase tracking-wider text-n-slate-11"
              >
                {{
                  blind ? t('ATHENAS.LAB.COLUMN_2') : t('ATHENAS.LAB.COLUMN_B')
                }}
              </span>
              <p
                class="text-[13px] text-n-slate-12 leading-relaxed whitespace-pre-wrap"
              >
                {{ duel.response_b }}
              </p>
              <span
                v-if="duel.critical_loss"
                class="inline-flex w-fit items-center px-2 py-0.5 rounded-full text-[11px] font-medium ring-1 bg-n-ruby-3 text-n-ruby-11 ring-n-ruby-6"
              >
                {{ t('ATHENAS.LAB.CRITICAL_LOSS') }}
              </span>
              <span
                v-if="!blind"
                class="text-[11px] text-n-slate-10 tabular-nums"
              >
                {{
                  t('ATHENAS.LAB.TELEMETRY', {
                    cost: (duel.telemetry_b.cost_brl || 0).toFixed(3),
                    latency: (
                      (duel.telemetry_b.latency_ms || 0) / 1000
                    ).toFixed(1),
                  })
                }}
              </span>
            </div>
          </div>
          <div v-if="!duel.winner" class="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              :label="blind ? t('ATHENAS.LAB.VOTE_1') : t('ATHENAS.LAB.VOTE_A')"
              @click="vote(duel, 'a')"
            />
            <Button
              variant="ghost"
              size="sm"
              :label="blind ? t('ATHENAS.LAB.VOTE_2') : t('ATHENAS.LAB.VOTE_B')"
              @click="vote(duel, 'b')"
            />
            <Button
              variant="ghost"
              size="sm"
              :label="t('ATHENAS.LAB.VOTE_TIE')"
              @click="vote(duel, 'tie')"
            />
          </div>
          <span v-else class="text-[12px] text-n-teal-11">
            {{ t(`ATHENAS.LAB.VOTED_${duel.winner.toUpperCase()}`) }}
          </span>
        </article>
      </template>
    </template>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import confetti from 'canvas-confetti';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const store = useStore();

const salesGoals = useMapGetter('salesGoals/getSalesGoals');
const uiFlags = useMapGetter('salesGoals/getUIFlags');
const agents = useMapGetter('agents/getAgents');

const PERIODS = ['daily', 'weekly', 'monthly'];

const PERIOD_ICONS = {
  daily: 'i-lucide-sun',
  weekly: 'i-lucide-calendar-days',
  monthly: 'i-lucide-calendar-range',
};

const currencyFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const numberFormatter = new Intl.NumberFormat('pt-BR', {
  maximumFractionDigits: 0,
});

const formatCurrency = value => currencyFormatter.format(Number(value) || 0);

// Render a goal value honoring its unit: currency goals show BRL, count goals
// (e.g. "Depoimentos") show a plain number.
const formatValue = (goal, value) =>
  goal?.unit === 'count'
    ? numberFormatter.format(Number(value) || 0)
    : formatCurrency(value);

const currencySymbol = 'R$';

const prefersReducedMotion = () =>
  typeof window !== 'undefined' &&
  window.matchMedia &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// --- color tiers --------------------------------------------------------
const tierFor = percent => {
  if (percent >= 100) return 'gold';
  if (percent >= 70) return 'teal';
  if (percent >= 40) return 'amber';
  return 'ruby';
};

const TIER_STYLES = {
  ruby: {
    bar: 'bg-n-ruby-9',
    text: 'text-n-ruby-11',
    badge: 'bg-n-ruby-3 text-n-ruby-11',
    ring: 'border-n-ruby-7',
  },
  amber: {
    bar: 'bg-n-amber-9',
    text: 'text-n-amber-11',
    badge: 'bg-n-amber-3 text-n-amber-11',
    ring: 'border-n-amber-7',
  },
  teal: {
    bar: 'bg-n-teal-9',
    text: 'text-n-teal-11',
    badge: 'bg-n-teal-3 text-n-teal-11',
    ring: 'border-n-teal-7',
  },
  gold: {
    bar: 'bg-emerald-500',
    text: 'text-emerald-500',
    badge: 'bg-emerald-500/15 text-emerald-500',
    ring: 'border-emerald-500',
  },
};

const RANK_BADGES = {
  0: 'bg-amber-400/20 text-amber-500 border-amber-400/40',
  1: 'bg-n-slate-4 text-n-slate-11 border-n-slate-6',
  2: 'bg-orange-500/15 text-orange-500 border-orange-500/30',
};

// --- derived list (leaderboard) ----------------------------------------
const rankedGoals = computed(() =>
  [...salesGoals.value].sort(
    (a, b) => (b.progress?.percent ?? 0) - (a.progress?.percent ?? 0)
  )
);

// --- modal state --------------------------------------------------------
const isModalOpen = ref(false);
const editingId = ref(null);
const form = reactive({
  userId: null,
  name: '',
  unit: 'currency',
  period: 'monthly',
  targetAmount: '',
});

const isEditing = computed(() => editingId.value !== null);

const selectedAgent = computed(() =>
  agents.value.find(agent => agent.id === form.userId)
);

const resetForm = () => {
  form.userId = null;
  form.name = '';
  form.unit = 'currency';
  form.period = 'monthly';
  form.targetAmount = '';
};

const openCreate = () => {
  editingId.value = null;
  resetForm();
  isModalOpen.value = true;
};

const openEdit = goal => {
  editingId.value = goal.id;
  form.userId = goal.user_id;
  form.name = goal.name ?? '';
  form.unit = goal.unit ?? 'currency';
  form.period = goal.period;
  form.targetAmount = String(goal.target_amount ?? '');
  isModalOpen.value = true;
};

const closeModal = () => {
  isModalOpen.value = false;
  editingId.value = null;
  resetForm();
};

// --- confetti -----------------------------------------------------------
const celebrate = () => {
  if (prefersReducedMotion()) return;
  confetti({
    particleCount: 90,
    spread: 70,
    origin: { y: 0.6 },
    colors: ['#10b981', '#fbbf24', '#34d399', '#fde68a'],
  });
};

// --- actions ------------------------------------------------------------
const handleSubmit = async () => {
  const amount = Number(String(form.targetAmount).replace(',', '.'));
  if (!form.userId) {
    useAlert(t('METAS.MODAL.VALIDATION.AGENT'));
    return;
  }
  if (!form.name.trim()) {
    useAlert(t('METAS.MODAL.VALIDATION.NAME'));
    return;
  }
  if (!amount || amount <= 0) {
    useAlert(t('METAS.MODAL.VALIDATION.AMOUNT'));
    return;
  }

  const payload = {
    user_id: form.userId,
    name: form.name.trim(),
    unit: form.unit,
    period: form.period,
    target_amount: amount,
  };

  try {
    if (isEditing.value) {
      const previous = salesGoals.value.find(g => g.id === editingId.value);
      const wasBelow = (previous?.progress?.percent ?? 0) < 100;
      const updated = await store.dispatch('salesGoals/update', {
        id: editingId.value,
        ...payload,
      });
      useAlert(t('METAS.MODAL.UPDATE_SUCCESS'));
      if (wasBelow && (updated?.progress?.percent ?? 0) >= 100) {
        await nextTick();
        celebrate();
      }
    } else {
      await store.dispatch('salesGoals/create', payload);
      useAlert(t('METAS.MODAL.CREATE_SUCCESS'));
    }
    closeModal();
  } catch (error) {
    useAlert(
      error?.message ||
        t(
          isEditing.value
            ? 'METAS.MODAL.UPDATE_ERROR'
            : 'METAS.MODAL.CREATE_ERROR'
        )
    );
  }
};

// --- per-card register (count goals) -----------------------------------
const isRegisterOpen = ref(false);
const registerGoal = ref(null);
const registerValue = ref('');

const openRegister = goal => {
  registerGoal.value = goal;
  registerValue.value = '';
  isRegisterOpen.value = true;
};

const closeRegister = () => {
  isRegisterOpen.value = false;
  registerGoal.value = null;
  registerValue.value = '';
};

const submitRegister = async () => {
  const goal = registerGoal.value;
  const value = Number(String(registerValue.value).replace(',', '.'));
  if (!goal || !value || value <= 0) {
    useAlert(t('METAS.REGISTER.VALIDATION'));
    return;
  }
  try {
    const wasBelow = (goal.progress?.percent ?? 0) < 100;
    await store.dispatch('salesGoals/registerRecord', {
      userId: goal.user_id,
      category: goal.category,
      amount: value,
    });
    useAlert(t('METAS.REGISTER.SUCCESS'));
    const refreshed = salesGoals.value.find(g => g.id === goal.id);
    if (wasBelow && (refreshed?.progress?.percent ?? 0) >= 100) {
      await nextTick();
      celebrate();
    }
    closeRegister();
  } catch (error) {
    useAlert(error?.message || t('METAS.REGISTER.ERROR'));
  }
};

const handleDelete = async goal => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('METAS.DELETE.CONFIRM', { name: goal.user.name })))
    return;
  try {
    await store.dispatch('salesGoals/delete', goal.id);
    useAlert(t('METAS.DELETE.SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('METAS.DELETE.ERROR'));
  }
};

onMounted(() => {
  store.dispatch('salesGoals/get');
  store.dispatch('agents/get');
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header
      class="flex items-center justify-between gap-4 px-8 py-6 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t('METAS.TITLE') }}
        </h1>
        <p class="m-0 max-w-2xl text-sm text-n-slate-11">
          {{ t('METAS.SUBTITLE') }}
        </p>
      </div>
      <Button
        icon="i-lucide-plus"
        :label="t('METAS.NEW')"
        @click="openCreate"
      />
    </header>

    <div class="flex-1 px-8 py-6">
      <!-- Loading -->
      <div
        v-if="uiFlags.isFetching"
        class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3"
      >
        <div
          v-for="n in 3"
          :key="n"
          class="h-44 rounded-2xl bg-n-solid-1 border border-n-weak animate-pulse"
        />
      </div>

      <!-- Empty -->
      <div
        v-else-if="!rankedGoals.length"
        class="flex flex-col items-center justify-center gap-3 py-24 text-center"
      >
        <span
          class="flex items-center justify-center rounded-2xl size-14 bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-target" class="size-7" />
        </span>
        <h3 class="m-0 text-base font-medium text-n-slate-12">
          {{ t('METAS.EMPTY_TITLE') }}
        </h3>
        <p class="m-0 max-w-md text-sm text-n-slate-11">
          {{ t('METAS.EMPTY_BODY') }}
        </p>
        <Button
          icon="i-lucide-plus"
          :label="t('METAS.NEW')"
          class="mt-2"
          @click="openCreate"
        />
      </div>

      <!-- Leaderboard grid -->
      <div v-else class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="(goal, index) in rankedGoals"
          :key="goal.id"
          class="group relative flex flex-col gap-4 p-5 rounded-2xl bg-n-solid-1 border transition-all duration-300 hover:shadow-lg"
          :class="[
            goal.progress.percent >= 100
              ? 'border-emerald-500/40 shadow-[0_0_24px_-6px] shadow-emerald-500/30'
              : 'border-n-weak hover:border-n-strong',
          ]"
        >
          <!-- Rank badge for top 3 -->
          <span
            v-if="index < 3"
            class="absolute -top-2 -left-2 z-10 flex items-center justify-center px-2 h-6 min-w-6 rounded-full border text-xs font-semibold"
            :class="RANK_BADGES[index]"
          >
            {{ t('METAS.CARD.RANK', { rank: index + 1 }) }}
          </span>

          <!-- Top row: avatar + name + period + actions -->
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-3 min-w-0">
              <Avatar
                :src="goal.user.thumbnail"
                :name="goal.user.name"
                :size="40"
              />
              <div class="flex flex-col gap-1 min-w-0">
                <h3 class="m-0 text-sm font-semibold text-n-slate-12 truncate">
                  {{ goal.name }}
                </h3>
                <span class="text-xs text-n-slate-11 truncate">
                  {{ goal.user.name }}
                </span>
                <div class="flex items-center gap-1.5 mt-0.5">
                  <span
                    class="inline-flex items-center gap-1 self-start px-2 py-0.5 rounded-full text-[11px] font-medium"
                    :class="TIER_STYLES[tierFor(goal.progress.percent)].badge"
                  >
                    <Icon :icon="PERIOD_ICONS[goal.period]" class="size-3" />
                    {{ t(`METAS.PERIOD.${goal.period.toUpperCase()}`) }}
                  </span>
                  <span
                    v-if="goal.unit === 'count'"
                    class="inline-flex items-center gap-1 self-start px-2 py-0.5 rounded-full text-[11px] font-medium bg-n-slate-3 text-n-slate-11"
                  >
                    <Icon icon="i-lucide-hash" class="size-3" />
                    {{ t('METAS.UNIT.COUNT') }}
                  </span>
                </div>
              </div>
            </div>
            <div
              class="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100"
            >
              <Button
                v-if="goal.unit === 'count'"
                variant="ghost"
                color="teal"
                size="sm"
                icon="i-lucide-plus-circle"
                :aria-label="t('METAS.CARD.REGISTER')"
                @click="openRegister(goal)"
              />
              <Button
                variant="ghost"
                color="slate"
                size="sm"
                icon="i-lucide-pencil"
                :aria-label="t('METAS.CARD.EDIT')"
                @click="openEdit(goal)"
              />
              <Button
                variant="ghost"
                color="ruby"
                size="sm"
                icon="i-lucide-trash-2"
                :aria-label="t('METAS.CARD.DELETE')"
                @click="handleDelete(goal)"
              />
            </div>
          </div>

          <!-- Progress -->
          <div class="flex flex-col gap-2">
            <div class="flex items-end justify-between gap-2">
              <div class="flex items-baseline gap-1 min-w-0">
                <span
                  class="text-base font-semibold tabular-nums truncate"
                  :class="TIER_STYLES[tierFor(goal.progress.percent)].text"
                >
                  {{ formatValue(goal, goal.progress.current) }}
                </span>
                <span class="text-xs text-n-slate-10 shrink-0">
                  {{ t('METAS.CARD.OF') }}
                  {{ formatValue(goal, goal.progress.target) }}
                </span>
              </div>
              <span
                class="text-sm font-bold tabular-nums"
                :class="TIER_STYLES[tierFor(goal.progress.percent)].text"
              >
                {{ Math.round(goal.progress.percent) }}%
              </span>
            </div>

            <div
              class="relative h-2.5 w-full overflow-hidden rounded-full bg-n-alpha-2"
            >
              <div
                class="absolute inset-y-0 left-0 rounded-full transition-[width] duration-700 ease-out"
                :class="TIER_STYLES[tierFor(goal.progress.percent)].bar"
                :style="{
                  width: `${Math.min(goal.progress.percent, 100)}%`,
                }"
              />
            </div>

            <p
              v-if="goal.progress.percent >= 100"
              class="m-0 text-xs font-semibold text-emerald-500"
            >
              {{ t('METAS.CARD.ACHIEVED') }}
            </p>
            <p v-else class="m-0 text-xs text-n-slate-11">
              {{
                t('METAS.CARD.REMAINING', {
                  amount: formatValue(goal, goal.progress.remaining),
                })
              }}
            </p>
          </div>
        </article>
      </div>
    </div>

    <!-- Create / Edit modal -->
    <div
      v-if="isModalOpen"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
      @click.self="closeModal"
    >
      <div
        class="flex flex-col w-full max-w-md gap-5 p-6 rounded-2xl bg-n-solid-1 border border-n-weak shadow-2xl"
      >
        <div class="flex items-start justify-between gap-4">
          <h2 class="m-0 text-lg font-semibold text-n-slate-12">
            {{
              isEditing
                ? t('METAS.MODAL.EDIT_TITLE')
                : t('METAS.MODAL.CREATE_TITLE')
            }}
          </h2>
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-x"
            @click="closeModal"
          />
        </div>

        <form class="flex flex-col gap-5" @submit.prevent="handleSubmit">
          <!-- Agent -->
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('METAS.MODAL.AGENT_LABEL') }}
            </label>
            <div
              class="flex items-center gap-2 px-3 h-11 rounded-xl bg-n-alpha-1 border border-n-weak focus-within:border-n-teal-8"
            >
              <Avatar
                v-if="selectedAgent"
                :src="selectedAgent.thumbnail"
                :name="selectedAgent.name"
                :size="24"
              />
              <Icon
                v-else
                icon="i-lucide-user"
                class="size-4 text-n-slate-10"
              />
              <select
                v-model="form.userId"
                class="flex-1 h-full bg-transparent text-sm text-n-slate-12 focus:outline-none cursor-pointer"
              >
                <option :value="null" disabled>
                  {{ t('METAS.MODAL.AGENT_PLACEHOLDER') }}
                </option>
                <option
                  v-for="agent in agents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name }}
                </option>
              </select>
            </div>
          </div>

          <!-- Goal name -->
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('METAS.MODAL.NAME_LABEL') }}
            </label>
            <input
              v-model="form.name"
              type="text"
              maxlength="60"
              :placeholder="t('METAS.MODAL.NAME_PLACEHOLDER')"
              class="px-3 h-11 rounded-xl bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8"
            />
          </div>

          <!-- Unit toggle -->
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('METAS.MODAL.UNIT_LABEL') }}
            </label>
            <div class="grid grid-cols-2 gap-2">
              <button
                type="button"
                class="flex items-center justify-center gap-1.5 py-3 rounded-xl border text-xs font-medium transition-all cursor-pointer"
                :class="
                  form.unit === 'currency'
                    ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
                    : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:border-n-strong'
                "
                @click="form.unit = 'currency'"
              >
                <Icon icon="i-lucide-circle-dollar-sign" class="size-4" />
                {{ t('METAS.UNIT.CURRENCY') }}
              </button>
              <button
                type="button"
                class="flex items-center justify-center gap-1.5 py-3 rounded-xl border text-xs font-medium transition-all cursor-pointer"
                :class="
                  form.unit === 'count'
                    ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
                    : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:border-n-strong'
                "
                @click="form.unit = 'count'"
              >
                <Icon icon="i-lucide-hash" class="size-4" />
                {{ t('METAS.UNIT.COUNT') }}
              </button>
            </div>
          </div>

          <!-- Period radio cards -->
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('METAS.MODAL.PERIOD_LABEL') }}
            </label>
            <div class="grid grid-cols-3 gap-2">
              <button
                v-for="period in PERIODS"
                :key="period"
                type="button"
                class="flex flex-col items-center gap-1.5 py-3 rounded-xl border text-xs font-medium transition-all cursor-pointer"
                :class="
                  form.period === period
                    ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
                    : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:border-n-strong'
                "
                @click="form.period = period"
              >
                <Icon :icon="PERIOD_ICONS[period]" class="size-5" />
                {{ t(`METAS.PERIOD.${period.toUpperCase()}`) }}
              </button>
            </div>
          </div>

          <!-- Target amount -->
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('METAS.MODAL.TARGET_LABEL') }}
            </label>
            <div
              class="flex items-center gap-1 px-3 h-11 rounded-xl bg-n-alpha-1 border border-n-weak focus-within:border-n-teal-8"
            >
              <span class="text-sm font-medium text-n-slate-10">{{
                form.unit === 'count' ? '#' : currencySymbol
              }}</span>
              <input
                v-model="form.targetAmount"
                type="number"
                min="0"
                :step="form.unit === 'count' ? '1' : '0.01'"
                inputmode="decimal"
                :placeholder="
                  form.unit === 'count'
                    ? '0'
                    : t('METAS.MODAL.TARGET_PLACEHOLDER')
                "
                class="flex-1 h-full bg-transparent text-sm text-n-slate-12 tabular-nums focus:outline-none"
              />
            </div>
          </div>

          <div class="flex items-center justify-end gap-2 pt-1">
            <Button
              type="button"
              variant="ghost"
              color="slate"
              :label="t('METAS.MODAL.CANCEL')"
              @click="closeModal"
            />
            <Button
              type="submit"
              :label="t('METAS.MODAL.SAVE')"
              :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
            />
          </div>
        </form>
      </div>
    </div>

    <!-- Register progress modal (count goals) -->
    <div
      v-if="isRegisterOpen"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
      @click.self="closeRegister"
    >
      <div
        class="flex flex-col w-full max-w-sm gap-5 p-6 rounded-2xl bg-n-solid-1 border border-n-weak shadow-2xl"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="m-0 text-lg font-semibold text-n-slate-12 truncate">
              {{ t('METAS.REGISTER.TITLE', { name: registerGoal?.name }) }}
            </h2>
            <p class="m-0 text-sm text-n-slate-11 truncate">
              {{ registerGoal?.user?.name }}
            </p>
          </div>
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-x"
            @click="closeRegister"
          />
        </div>
        <form class="flex flex-col gap-5" @submit.prevent="submitRegister">
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('METAS.REGISTER.VALUE_LABEL') }}
            </label>
            <div
              class="flex items-center gap-1 px-3 h-11 rounded-xl bg-n-alpha-1 border border-n-weak focus-within:border-n-teal-8"
            >
              <span class="text-sm font-medium text-n-slate-10">#</span>
              <input
                v-model="registerValue"
                type="number"
                min="0"
                step="1"
                inputmode="numeric"
                :placeholder="t('METAS.REGISTER.VALUE_PLACEHOLDER')"
                class="flex-1 h-full bg-transparent text-sm text-n-slate-12 tabular-nums focus:outline-none"
              />
            </div>
          </div>
          <div class="flex items-center justify-end gap-2 pt-1">
            <Button
              type="button"
              variant="ghost"
              color="slate"
              :label="t('METAS.REGISTER.CANCEL')"
              @click="closeRegister"
            />
            <Button type="submit" :label="t('METAS.REGISTER.SAVE')" />
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
// "Configurar negócio": everything the agent needs before it can offer a time.
//
// Four things, in the order the operator thinks about them: what the agenda is
// called, when the business is open, what it sells time for, and how far ahead
// or how close to the hour the agent is allowed to act.
//
// The first three are what make the slot arithmetic OURS. Duration and buffer
// left as prose in a knowledge document would have the model adding 90 minutes
// to 14:00 by itself, and it gets that wrong the same way it used to get prices
// wrong.
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();

// 0 = Sunday, matching Ruby's Date#wday so nothing has to translate on the way
// in or out.
const WEEKDAYS = [0, 1, 2, 3, 4, 5, 6];

const INPUT_CLASS =
  'w-full px-3 h-9 rounded-lg bg-n-alpha-1 border border-n-weak text-[13px] text-n-slate-12 outline-none focus:border-n-brand';

// One template for the caption row and every service row, so the columns are
// the same columns and not two lists that happen to look alike.
const SERVICE_GRID = 'gap-2 sm:grid-cols-[2fr_1fr_1fr_1fr_auto]';

const loading = ref(true);
const saving = ref(false);
const connected = ref(false);

const professional = ref({ name: '', timezone: 'America/Sao_Paulo' });
const settings = ref({
  minimum_lead_minutes: 120,
  horizon_days: 60,
  cancellation_window_hours: 2,
});
// One entry per range, not per day: a salon stops for lunch, and a single
// open/close pair per weekday would have the agent offering 12:30.
const hours = ref([]);
const services = ref([]);
const newService = ref(null);

const hoursFor = weekday =>
  hours.value.filter(hour => Number(hour.weekday) === weekday);

// The column is cents because money in a float is a rounding bug waiting for a
// price that ends in 90. The operator types 199, never 19900, so the conversion
// lives here and the two never meet.
const toReais = cents =>
  cents === null || cents === undefined || cents === '' ? '' : cents / 100;

const toCents = price => {
  if (price === null || price === undefined || String(price).trim() === '') {
    return null;
  }
  return Math.round(Number(String(price).replace(',', '.')) * 100);
};

const withPrice = service => ({
  ...service,
  price: toReais(service.price_cents),
});

const isOpen = weekday => hoursFor(weekday).length > 0;

const addRange = weekday => {
  hours.value.push({ weekday, starts_at: '09:00', ends_at: '18:00' });
};

const removeRange = row => {
  hours.value = hours.value.filter(hour => hour !== row);
};

const toggleDay = weekday => {
  if (isOpen(weekday)) {
    hours.value = hours.value.filter(hour => Number(hour.weekday) !== weekday);
  } else {
    addRange(weekday);
  }
};

const load = async () => {
  loading.value = true;
  try {
    const [setup, serviceList] = await Promise.all([
      AthenasAPI.calendarSetup(props.assistantId),
      AthenasAPI.listCalendarServices(props.assistantId),
    ]);
    connected.value = Boolean(setup.data?.connection);
    if (setup.data?.professional) {
      professional.value = {
        name: setup.data.professional.name,
        timezone: setup.data.professional.timezone,
      };
      hours.value = (setup.data.professional.hours || []).map(hour => ({
        weekday: hour.weekday,
        starts_at: hour.starts_at,
        ends_at: hour.ends_at,
      }));
    }
    if (setup.data?.settings) settings.value = { ...setup.data.settings };
    services.value = (serviceList.data?.payload || []).map(withPrice);
  } catch {
    useAlert(t('ATHENAS.EDIT.BUSINESS.LOAD_FAILED'));
  } finally {
    loading.value = false;
  }
};

// The agenda, the week and the rules save together because they are one form.
// Saving them one field at a time would let the operator leave with services
// nobody can be booked for, because the week was never written.
const save = async () => {
  saving.value = true;
  try {
    await AthenasAPI.updateCalendarSetup(props.assistantId, {
      professional: professional.value,
      settings: settings.value,
      hours: hours.value,
    });
    useAlert(t('ATHENAS.EDIT.BUSINESS.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('ATHENAS.EDIT.BUSINESS.SAVE_FAILED')
    );
  } finally {
    saving.value = false;
  }
};

const startService = () => {
  newService.value = {
    name: '',
    duration_minutes: 60,
    buffer_minutes: 0,
    price: '',
  };
};

const saveService = async service => {
  const payload = {
    name: service.name,
    duration_minutes: Number(service.duration_minutes),
    buffer_minutes: Number(service.buffer_minutes || 0),
    price_cents: toCents(service.price),
  };
  try {
    if (service.id) {
      await AthenasAPI.updateCalendarService(
        props.assistantId,
        service.id,
        payload
      );
    } else {
      await AthenasAPI.createCalendarService(props.assistantId, payload);
      newService.value = null;
    }
    const { data } = await AthenasAPI.listCalendarServices(props.assistantId);
    services.value = (data?.payload || []).map(withPrice);
    useAlert(t('ATHENAS.EDIT.BUSINESS.SERVICE_SAVED'));
  } catch {
    useAlert(t('ATHENAS.EDIT.BUSINESS.SERVICE_FAILED'));
  }
};

const removeService = async service => {
  try {
    await AthenasAPI.deleteCalendarService(props.assistantId, service.id);
    services.value = services.value.filter(item => item.id !== service.id);
  } catch {
    useAlert(t('ATHENAS.EDIT.BUSINESS.SERVICE_FAILED'));
  }
};

const ready = computed(
  () => connected.value && professional.value.name && services.value.length > 0
);

onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-6">
    <header class="flex flex-col gap-1">
      <h2 class="text-base font-semibold tracking-tight text-n-slate-12">
        {{ t('ATHENAS.EDIT.BUSINESS.TITLE') }}
      </h2>
      <p class="text-[13px] text-n-slate-11 max-w-2xl">
        {{ t('ATHENAS.EDIT.BUSINESS.SUBTITLE') }}
      </p>
    </header>

    <div v-if="loading" class="flex justify-center py-10">
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-10"
      />
    </div>

    <template v-else>
      <!-- Says out loud what is still missing, because a half-configured
           agenda looks identical to a working one until a customer asks. -->
      <div
        v-if="!ready"
        class="flex items-start gap-3 p-3 border rounded-xl border-n-amber-7/40 bg-n-amber-3/15"
      >
        <span class="i-lucide-info size-4 text-n-amber-11 mt-0.5" />
        <p class="m-0 text-[13px] text-n-slate-11">
          {{ t('ATHENAS.EDIT.BUSINESS.INCOMPLETE') }}
        </p>
      </div>

      <!-- AGENDA -->
      <div class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('ATHENAS.EDIT.BUSINESS.AGENDA_TITLE') }}
        </h3>
        <p class="m-0 text-[12px] text-n-slate-11">
          {{ t('ATHENAS.EDIT.BUSINESS.AGENDA_HINT') }}
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="flex flex-col gap-1.5">
            <span class="text-[12px] font-medium text-n-slate-11">
              {{ t('ATHENAS.EDIT.BUSINESS.PROFESSIONAL_NAME') }}
            </span>
            <input v-model="professional.name" :class="INPUT_CLASS" />
          </label>
          <label class="flex flex-col gap-1.5">
            <span class="text-[12px] font-medium text-n-slate-11">
              {{ t('ATHENAS.EDIT.BUSINESS.TIMEZONE') }}
            </span>
            <input v-model="professional.timezone" :class="INPUT_CLASS" />
          </label>
        </div>
      </div>

      <!-- WEEK -->
      <div class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('ATHENAS.EDIT.BUSINESS.HOURS_TITLE') }}
        </h3>
        <p class="m-0 text-[12px] text-n-slate-11">
          {{ t('ATHENAS.EDIT.BUSINESS.HOURS_HINT') }}
        </p>

        <div
          v-for="weekday in WEEKDAYS"
          :key="weekday"
          class="flex flex-wrap items-center gap-3 py-2 border-b border-n-weak/60 last:border-0"
        >
          <label class="flex items-center gap-2 w-36 flex-shrink-0">
            <input
              type="checkbox"
              :checked="isOpen(weekday)"
              class="accent-n-brand"
              @change="toggleDay(weekday)"
            />
            <span class="text-[13px] text-n-slate-12">
              {{ t(`ATHENAS.EDIT.BUSINESS.WEEKDAYS.D${weekday}`) }}
            </span>
          </label>

          <span v-if="!isOpen(weekday)" class="text-[12px] text-n-slate-10">
            {{ t('ATHENAS.EDIT.BUSINESS.CLOSED') }}
          </span>

          <div v-else class="flex flex-col gap-2">
            <div
              v-for="(row, index) in hoursFor(weekday)"
              :key="`${weekday}-${index}`"
              class="flex items-center gap-2"
            >
              <input
                v-model="row.starts_at"
                type="time"
                class="px-2 h-9 rounded-lg bg-n-alpha-1 border border-n-weak text-[13px] text-n-slate-12"
              />
              <span class="text-[12px] text-n-slate-10">
                {{ t('ATHENAS.EDIT.BUSINESS.TO') }}
              </span>
              <input
                v-model="row.ends_at"
                type="time"
                class="px-2 h-9 rounded-lg bg-n-alpha-1 border border-n-weak text-[13px] text-n-slate-12"
              />
              <button
                type="button"
                class="text-n-slate-10 hover:text-n-ruby-11"
                :aria-label="t('ATHENAS.EDIT.BUSINESS.REMOVE_RANGE')"
                @click="removeRange(row)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
            <button
              type="button"
              class="text-[12px] text-n-brand text-left"
              @click="addRange(weekday)"
            >
              {{ t('ATHENAS.EDIT.BUSINESS.ADD_RANGE') }}
            </button>
          </div>
        </div>
      </div>

      <!-- SERVICES -->
      <div class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak">
        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1">
            <h3 class="m-0 text-sm font-semibold text-n-slate-12">
              {{ t('ATHENAS.EDIT.BUSINESS.SERVICES_TITLE') }}
            </h3>
            <p class="m-0 text-[12px] text-n-slate-11">
              {{ t('ATHENAS.EDIT.BUSINESS.SERVICES_HINT') }}
            </p>
          </div>
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('ATHENAS.EDIT.BUSINESS.ADD_SERVICE')"
            @click="startService"
          />
        </div>

        <!-- The captions sit here once instead of above every row: repeated on
             ten services they stop reading as a table and the columns stop
             lining up to the eye. Below `sm` the grid stacks and the
             placeholders carry the same words. -->
        <div
          v-if="services.length || newService"
          :class="SERVICE_GRID"
          class="hidden sm:grid text-[11px] text-n-slate-11"
        >
          <span>{{ t('ATHENAS.EDIT.BUSINESS.SERVICE_NAME') }}</span>
          <span>{{ t('ATHENAS.EDIT.BUSINESS.DURATION') }}</span>
          <span>{{ t('ATHENAS.EDIT.BUSINESS.BUFFER') }}</span>
          <span>{{ t('ATHENAS.EDIT.BUSINESS.PRICE') }}</span>
          <span />
        </div>

        <div
          v-for="service in [...services, newService].filter(Boolean)"
          :key="service.id || 'new'"
          :class="SERVICE_GRID"
          class="grid items-center"
        >
          <input
            v-model="service.name"
            :class="INPUT_CLASS"
            :placeholder="t('ATHENAS.EDIT.BUSINESS.SERVICE_NAME')"
            :aria-label="t('ATHENAS.EDIT.BUSINESS.SERVICE_NAME')"
          />
          <input
            v-model="service.duration_minutes"
            type="number"
            min="5"
            :class="INPUT_CLASS"
            :placeholder="t('ATHENAS.EDIT.BUSINESS.DURATION')"
            :aria-label="t('ATHENAS.EDIT.BUSINESS.DURATION')"
          />
          <input
            v-model="service.buffer_minutes"
            type="number"
            min="0"
            :class="INPUT_CLASS"
            :placeholder="t('ATHENAS.EDIT.BUSINESS.BUFFER')"
            :aria-label="t('ATHENAS.EDIT.BUSINESS.BUFFER')"
          />
          <div class="relative">
            <span
              class="absolute inset-y-0 left-3 flex items-center text-[13px] text-n-slate-10 pointer-events-none"
            >
              {{ t('ATHENAS.EDIT.BUSINESS.CURRENCY') }}
            </span>
            <input
              v-model="service.price"
              type="text"
              inputmode="decimal"
              :class="INPUT_CLASS"
              class="pl-9"
              :placeholder="t('ATHENAS.EDIT.BUSINESS.PRICE_PLACEHOLDER')"
              :aria-label="t('ATHENAS.EDIT.BUSINESS.PRICE')"
            />
          </div>
          <div class="flex items-center gap-1">
            <Button
              size="sm"
              variant="faded"
              :label="t('ATHENAS.EDIT.BUSINESS.SAVE_SERVICE')"
              @click="saveService(service)"
            />
            <button
              v-if="service.id"
              type="button"
              class="p-2 text-n-slate-10 hover:text-n-ruby-11"
              :aria-label="t('ATHENAS.EDIT.BUSINESS.REMOVE_SERVICE')"
              @click="removeService(service)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </div>
        </div>

        <p
          v-if="!services.length && !newService"
          class="m-0 text-[12px] text-n-slate-10"
        >
          {{ t('ATHENAS.EDIT.BUSINESS.SERVICES_EMPTY') }}
        </p>
      </div>

      <!-- RULES -->
      <div class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak">
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('ATHENAS.EDIT.BUSINESS.RULES_TITLE') }}
        </h3>
        <div class="grid gap-3 sm:grid-cols-3">
          <label class="flex flex-col gap-1.5">
            <span class="text-[12px] font-medium text-n-slate-11">
              {{ t('ATHENAS.EDIT.BUSINESS.LEAD') }}
            </span>
            <input
              v-model="settings.minimum_lead_minutes"
              type="number"
              min="0"
              :class="INPUT_CLASS"
            />
            <span class="text-[11px] text-n-slate-10">
              {{ t('ATHENAS.EDIT.BUSINESS.LEAD_HINT') }}
            </span>
          </label>
          <label class="flex flex-col gap-1.5">
            <span class="text-[12px] font-medium text-n-slate-11">
              {{ t('ATHENAS.EDIT.BUSINESS.HORIZON') }}
            </span>
            <input
              v-model="settings.horizon_days"
              type="number"
              min="1"
              :class="INPUT_CLASS"
            />
            <span class="text-[11px] text-n-slate-10">
              {{ t('ATHENAS.EDIT.BUSINESS.HORIZON_HINT') }}
            </span>
          </label>
          <label class="flex flex-col gap-1.5">
            <span class="text-[12px] font-medium text-n-slate-11">
              {{ t('ATHENAS.EDIT.BUSINESS.CANCEL_WINDOW') }}
            </span>
            <input
              v-model="settings.cancellation_window_hours"
              type="number"
              min="0"
              :class="INPUT_CLASS"
            />
            <span class="text-[11px] text-n-slate-10">
              {{ t('ATHENAS.EDIT.BUSINESS.CANCEL_WINDOW_HINT') }}
            </span>
          </label>
        </div>
      </div>

      <div class="flex justify-end">
        <Button
          :label="t('ATHENAS.EDIT.BUSINESS.SAVE')"
          :disabled="saving"
          @click="save"
        />
      </div>
    </template>
  </section>
</template>

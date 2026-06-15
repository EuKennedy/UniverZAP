<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SaleRecordsAPI from 'dashboard/api/saleRecords';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// Conversation-scoped "register a sale" modal. The agent records a BRL
// amount for the current contact; the backend adds it to the contact's
// cumulative `valor_em_compras` and counts it toward the agent's active
// sales goal. Dark-first, emerald accents, a small 💰 for celebration.
const props = defineProps({
  contactId: {
    type: [Number, String],
    default: null,
  },
  contactName: {
    type: String,
    default: '',
  },
  currentTotal: {
    type: Number,
    default: 0,
  },
  open: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();

const brlFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const amount = ref('');
const orderNumber = ref('');
const paidAt = ref('');
const isSaving = ref(false);

const todayISO = () => new Date().toISOString().slice(0, 10);

const formattedCurrentTotal = computed(() =>
  brlFormatter.format(Number(props.currentTotal) || 0)
);

const parsedAmount = computed(() => {
  const normalized = String(amount.value).trim().replace(',', '.');
  const value = Number.parseFloat(normalized);
  return Number.isFinite(value) ? value : 0;
});

const isValid = computed(() => parsedAmount.value > 0);

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      amount.value = '';
      orderNumber.value = '';
      paidAt.value = todayISO();
      isSaving.value = false;
    }
  }
);

const close = () => {
  if (isSaving.value) return;
  emit('close');
};

const save = async () => {
  if (!isValid.value) {
    useAlert(t('METAS.SALE.MODAL.VALIDATION'));
    return;
  }
  isSaving.value = true;
  try {
    const { data } = await SaleRecordsAPI.create(
      props.contactId,
      parsedAmount.value,
      {
        category: 'sales',
        order_number: orderNumber.value.trim() || undefined,
        paid_at: paidAt.value || undefined,
      }
    );
    useAlert(t('METAS.SALE.MODAL.SUCCESS'));
    emit('saved', data.contact_total);
    emit('close');
  } catch (error) {
    useAlert(t('METAS.SALE.MODAL.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="w-full max-w-md p-6 rounded-2xl bg-n-solid-2 ring-1 ring-n-strong shadow-xl flex flex-col gap-5"
      >
        <div class="flex items-start gap-3">
          <span
            class="flex items-center justify-center flex-shrink-0 rounded-xl size-11 bg-n-teal-3 text-n-teal-11"
          >
            <Icon icon="i-lucide-circle-dollar-sign" class="size-6" />
          </span>
          <div class="flex flex-col min-w-0">
            <h3 class="m-0 text-base font-medium text-n-slate-12">
              {{ `${t('METAS.SALE.MODAL.TITLE')} 💰` }}
            </h3>
            <p class="m-0 text-sm truncate text-n-slate-11">
              {{ contactName }}
            </p>
          </div>
        </div>

        <div
          class="flex items-center justify-between px-4 py-3 rounded-xl bg-n-solid-1 ring-1 ring-n-weak"
        >
          <span class="text-sm text-n-slate-11">
            {{ t('METAS.SALE.MODAL.CURRENT_TOTAL') }}
          </span>
          <span class="text-sm font-medium tabular-nums text-n-slate-12">
            {{ formattedCurrentTotal }}
          </span>
        </div>

        <div class="flex flex-col gap-1.5">
          <label
            for="register-sale-amount"
            class="text-sm font-medium text-n-slate-12"
          >
            {{ t('METAS.SALE.MODAL.AMOUNT_LABEL') }}
          </label>
          <div
            class="flex items-center gap-2 px-3 rounded-xl bg-n-alpha-black2 ring-1 ring-n-weak focus-within:ring-n-teal-8"
          >
            <span class="text-sm font-medium text-n-teal-11">{{ 'R$' }}</span>
            <input
              id="register-sale-amount"
              v-model="amount"
              type="text"
              inputmode="decimal"
              autocomplete="off"
              :placeholder="t('METAS.SALE.MODAL.AMOUNT_PLACEHOLDER')"
              class="flex-1 h-11 bg-transparent border-0 outline-none text-sm text-n-slate-12 tabular-nums placeholder:text-n-slate-10"
              @keydown.enter="save"
            />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="flex flex-col gap-1.5">
            <label
              for="register-sale-order"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ t('METAS.SALE.MODAL.ORDER_LABEL') }}
            </label>
            <div
              class="flex items-center gap-2 px-3 rounded-xl bg-n-alpha-black2 ring-1 ring-n-weak focus-within:ring-n-teal-8"
            >
              <span class="text-sm font-medium text-n-slate-10">#</span>
              <input
                id="register-sale-order"
                v-model="orderNumber"
                type="text"
                autocomplete="off"
                :placeholder="t('METAS.SALE.MODAL.ORDER_PLACEHOLDER')"
                class="flex-1 h-11 bg-transparent border-0 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
                @keydown.enter="save"
              />
            </div>
          </div>
          <div class="flex flex-col gap-1.5">
            <label
              for="register-sale-paid"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ t('METAS.SALE.MODAL.PAID_AT_LABEL') }}
            </label>
            <div
              class="flex items-center px-3 rounded-xl bg-n-alpha-black2 ring-1 ring-n-weak focus-within:ring-n-teal-8"
            >
              <input
                id="register-sale-paid"
                v-model="paidAt"
                type="date"
                class="flex-1 h-11 bg-transparent border-0 outline-none text-sm text-n-slate-12"
              />
            </div>
          </div>
        </div>

        <div class="flex items-center justify-end gap-2">
          <NextButton
            :label="t('METAS.SALE.MODAL.CANCEL')"
            slate
            faded
            :disabled="isSaving"
            @click="close"
          />
          <NextButton
            :label="t('METAS.SALE.MODAL.SAVE')"
            teal
            :is-loading="isSaving"
            :disabled="isSaving || !isValid"
            @click="save"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>

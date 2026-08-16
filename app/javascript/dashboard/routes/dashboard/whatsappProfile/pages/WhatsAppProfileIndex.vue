<script setup>
/**
 * "Meu WhatsApp": a tela que tira o celular da mão do dono.
 *
 * A lista de conexões vem do backend, e não do store de inboxes, porque uma
 * inbox pode ser WAHA por dois caminhos diferentes (canal de API criado pelo
 * fluxo de conexão ou canal de WhatsApp com provider waha). Quem sabe dizer
 * qual é qual é o resolvedor do backend, então repetir essa regra aqui só
 * criaria uma segunda versão dela para divergir com o tempo.
 */
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { useAccount } from 'dashboard/composables/useAccount';
import WhatsAppProfileAPI from 'dashboard/api/whatsappProfile';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import WhatsAppProfileCard from '../components/WhatsAppProfileCard.vue';
import WhatsAppStatusComposer from '../components/WhatsAppStatusComposer.vue';

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const isLoading = ref(true);
const loadError = ref('');
const inboxes = ref([]);
const selectedInboxId = ref(null);

const hasInboxes = computed(() => inboxes.value.length > 0);
const hasChoice = computed(() => inboxes.value.length > 1);
const selectedInbox = computed(() =>
  inboxes.value.find(inbox => inbox.id === selectedInboxId.value)
);
const options = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const fetchInboxes = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await WhatsAppProfileAPI.inboxes();
    inboxes.value = data.payload || [];
    selectedInboxId.value = inboxes.value.length ? inboxes.value[0].id : null;
  } catch (error) {
    loadError.value =
      error?.response?.data?.error ||
      error?.message ||
      t('WHATSAPP_PROFILE.ERRORS.GENERIC');
  } finally {
    isLoading.value = false;
  }
};

const goToConnections = () =>
  router.push(accountScopedRoute('settings_inbox_new'));

onMounted(fetchInboxes);
</script>

<template>
  <div class="flex overflow-auto flex-col w-full h-full bg-n-background">
    <header
      class="flex flex-wrap gap-4 justify-between items-end px-8 py-6 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t('WHATSAPP_PROFILE.TITLE') }}
        </h1>
        <p class="m-0 max-w-xl text-sm text-n-slate-11">
          {{ t('WHATSAPP_PROFILE.SUBTITLE') }}
        </p>
      </div>

      <div v-if="hasInboxes" class="flex flex-col gap-1.5 items-start">
        <span
          class="text-[11px] font-medium tracking-wide uppercase text-n-slate-11"
        >
          {{ t('WHATSAPP_PROFILE.CONNECTION') }}
        </span>
        <!-- Com uma conexão só, um seletor seria enfeite. O nome basta. -->
        <Select
          v-if="hasChoice"
          v-model="selectedInboxId"
          :options="options"
          data-testid="inbox-select"
        />
        <span
          v-else
          class="px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ selectedInbox?.name }}
        </span>
      </div>
    </header>

    <div v-if="isLoading" class="flex flex-1 justify-center items-center">
      <Spinner :size="24" />
    </div>

    <div
      v-else-if="loadError"
      class="px-8 py-6 text-sm text-n-ruby-11"
      data-testid="load-error"
    >
      {{ loadError }}
    </div>

    <!-- Sem conexão WAHA não há o que editar. Dizer isso e apontar o caminho
      é mais honesto que abrir a tela com campos que não salvam. -->
    <div
      v-else-if="!hasInboxes"
      class="flex flex-1 justify-center items-center px-8 py-16"
      data-testid="empty-state"
    >
      <div class="flex flex-col gap-3 items-center max-w-md text-center">
        <span
          class="flex justify-center items-center rounded-full size-12 bg-n-alpha-2 text-n-slate-11"
        >
          <span class="i-lucide-message-circle-off size-5" />
        </span>
        <h2 class="m-0 text-base font-medium text-n-slate-12">
          {{ t('WHATSAPP_PROFILE.EMPTY.TITLE') }}
        </h2>
        <p class="m-0 text-sm leading-relaxed text-n-slate-11">
          {{ t('WHATSAPP_PROFILE.EMPTY.DESCRIPTION') }}
        </p>
        <Button
          class="mt-1"
          :label="t('WHATSAPP_PROFILE.EMPTY.ACTION')"
          icon="i-lucide-plug-zap"
          @click="goToConnections"
        />
      </div>
    </div>

    <div
      v-else
      class="grid flex-1 gap-6 px-8 py-6 items-start lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)]"
    >
      <WhatsAppProfileCard :inbox-id="selectedInboxId" />
      <WhatsAppStatusComposer :inbox-id="selectedInboxId" />
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import BelezakiCustomerCard from 'dashboard/components/widgets/conversation/belezaki/CustomerCard.vue';
import ContactFieldValue from './ContactFieldValue.vue';
import ContactIdentity from './ContactIdentity.vue';
import { useContactFieldLabel } from './useContactFieldLabel';

// Everything about one contact without leaving the list. The salon's card is
// fetched here, for this one person, when the panel opens.
const props = defineProps({
  contact: { type: Object, required: true },
  fields: { type: Array, required: true },
  labelColors: { type: Object, default: () => ({}) },
  showBelezaki: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'showDetails']);

const { t } = useI18n();
const fieldLabel = useContactFieldLabel();

const contactId = computed(() => String(props.contact.id));

useEventListener(document, 'keydown', event => {
  if (event.key === 'Escape') emit('close');
});
</script>

<template>
  <div class="fixed inset-0 z-40" @click="emit('close')">
    <aside
      class="absolute inset-y-0 flex flex-col overflow-y-auto border-s end-0 w-full max-w-md shadow-2xl border-n-weak bg-n-solid-1"
      @click.stop
    >
      <header
        class="relative flex items-start justify-between flex-shrink-0 gap-2 p-4 overflow-hidden border-b border-n-weak"
      >
        <span
          class="absolute rounded-full pointer-events-none -top-20 -end-10 size-56 bg-brand-gradient opacity-[0.12] blur-3xl"
        />
        <ContactIdentity :contact="contact" :size="48" show-phone />
        <Button
          icon="i-lucide-x"
          color="slate"
          variant="ghost"
          size="xs"
          :aria-label="t('CONTACTS_LAYOUT.PREVIEW.CLOSE')"
          @click="emit('close')"
        />
      </header>

      <div class="flex flex-shrink-0 gap-2 p-4 border-b border-n-weak">
        <Button
          class="flex-1"
          size="sm"
          color="slate"
          variant="faded"
          icon="i-lucide-square-arrow-out-up-right"
          :label="t('CONTACTS_LAYOUT.PREVIEW.OPEN_DETAILS')"
          @click="emit('showDetails', contact.id)"
        />
        <ComposeConversation :contact-id="contactId">
          <template #trigger>
            <Button
              size="sm"
              icon="i-lucide-send"
              :label="t('CONTACTS_LAYOUT.PREVIEW.SEND_MESSAGE')"
            />
          </template>
        </ComposeConversation>
      </div>

      <dl class="grid gap-3 p-4 text-sm">
        <div
          v-for="field in fields"
          :key="field.key"
          class="grid grid-cols-[8rem_minmax(0,1fr)] gap-3"
        >
          <dt class="truncate text-n-slate-11">{{ fieldLabel(field) }}</dt>
          <dd class="min-w-0">
            <ContactFieldValue
              :field="field"
              :contact="contact"
              :label-colors="labelColors"
              wrap
            />
          </dd>
        </div>
      </dl>

      <div v-if="showBelezaki" class="px-4 pb-4">
        <BelezakiCustomerCard :contact-id="contact.id" />
      </div>
    </aside>
  </div>
</template>

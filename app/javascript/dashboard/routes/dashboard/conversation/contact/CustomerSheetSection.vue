<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import VerticalStatusesAPI from 'dashboard/api/verticalStatuses';
import CustomerSheet from './CustomerSheet.vue';
import BelezakiCustomerCard from 'dashboard/components/widgets/conversation/belezaki/CustomerCard.vue';

// Store wiring for the customer sheet shown in the conversation's right panel.
const props = defineProps({
  contact: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();
const profile = computed(() => currentAccount.value.vertical_profile);

const currentChat = useMapGetter('getSelectedChat');
const attributeDefinitions = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);
const contactConversationsGetter = useMapGetter(
  'contactConversations/getContactConversation'
);
const previousConversations = computed(() =>
  contactConversationsGetter.value(props.contact.id)
);

// The salon's agenda lives inside this same sheet. The section only exists
// while the server offers the belezaki app; "connect it in Apps" is a state
// of the card itself, so an unlinked account still sees where to go.
const belezakiIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'belezaki'
);
const showBelezaki = computed(() => !!belezakiIntegration.value.id);

const stages = ref([]);
const isScheduling = ref(false);
const sheet = ref(null);

const loadStages = async () => {
  try {
    const { data } = await VerticalStatusesAPI.fetchAll();
    stages.value = data.statuses || [];
  } catch {
    stages.value = [];
  }
};

watch(
  () => props.contact.id,
  contactId => {
    if (contactId) store.dispatch('contactConversations/get', contactId);
  },
  { immediate: true }
);

onMounted(loadStages);

const onUpdate = async (key, value) => {
  const customAttributes = {
    ...(currentChat.value.custom_attributes || {}),
    [key]: value,
  };
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes,
    });
    useAlert(t('CUSTOM_ATTRIBUTES.FORM.UPDATE.SUCCESS'));
  } catch {
    useAlert(t('CUSTOM_ATTRIBUTES.FORM.UPDATE.ERROR'));
  }
};

const onSchedule = async attributes => {
  isScheduling.value = true;
  try {
    await store.dispatch('scheduleConversation', {
      conversationId: currentChat.value.id,
      attributes,
    });
    sheet.value?.closeSchedule();
    useAlert(t('CONTACT_PANEL.SHEET.SCHEDULE.SUCCESS'));
  } catch {
    useAlert(t('CONTACT_PANEL.SHEET.SCHEDULE.ERROR'));
  } finally {
    isScheduling.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col w-full gap-2">
    <CustomerSheet
      ref="sheet"
      :contact="contact"
      :conversation="currentChat"
      :stages="stages"
      :attribute-definitions="attributeDefinitions"
      :previous-conversations="previousConversations"
      :is-scheduling="isScheduling"
      :profile="profile"
      @update="onUpdate"
      @schedule="onSchedule"
    />
    <BelezakiCustomerCard
      v-if="showBelezaki && contact.id"
      :contact-id="contact.id"
    />
  </div>
</template>

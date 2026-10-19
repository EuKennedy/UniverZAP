<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import VerticalStatusesAPI from 'dashboard/api/verticalStatuses';
import CustomerSheet from './CustomerSheet.vue';

// Store wiring for the customer sheet shown in the conversation's right panel.
const props = defineProps({
  contact: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useStore();

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
  <CustomerSheet
    ref="sheet"
    :contact="contact"
    :conversation="currentChat"
    :stages="stages"
    :attribute-definitions="attributeDefinitions"
    :previous-conversations="previousConversations"
    :is-scheduling="isScheduling"
    @update="onUpdate"
    @schedule="onSchedule"
  />
</template>

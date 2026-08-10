<script setup>
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useToggle } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useEmitter } from 'dashboard/composables/emitter';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import WootDropdownItem from 'shared/components/ui/dropdown/DropdownItem.vue';
import WootDropdownMenu from 'shared/components/ui/dropdown/DropdownMenu.vue';
import wootConstants from 'dashboard/constants/globals';
import {
  CMD_REOPEN_CONVERSATION,
  CMD_RESOLVE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';
import ConversationKanbanAttachModal from 'dashboard/components-next/ConversationKanbanAttach/ConversationKanbanAttachModal.vue';
import ConversationKanbanViewerModal from 'dashboard/components-next/ConversationKanbanAttach/ConversationKanbanViewerModal.vue';
import { useAthenasAssistant } from 'dashboard/composables/useAthenasAssistant';
import { useAthenasCredits } from 'dashboard/composables/useAthenasCredits';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
const { checkMissingAttributes } = useConversationRequiredAttributes();

// Athenas saldo chip — replaces the old floating bottom-36 widget so
// the saldo lives next to "Mover/Visualizar Kanban" instead of
// hovering over chat content. Click opens the same paywall modal.
const {
  balanceCents: athenasBalanceCents,
  isLoaded: athenasLoaded,
  status: athenasStatus,
  openTopUpModal: openAthenasTopUp,
  refresh: refreshAthenasCredits,
} = useAthenasCredits();
const athenasBalanceWhole = computed(() =>
  Math.floor((athenasBalanceCents.value || 0) / 100)
);
const athenasButtonColor = computed(() => {
  if (athenasStatus.value === 'exhausted') return 'ruby';
  if (athenasStatus.value === 'warn_95' || athenasStatus.value === 'warn_80')
    return 'amber';
  return 'teal';
});
refreshAthenasCredits();

const arrowDownButtonRef = ref(null);
const isLoading = ref(false);
const resolveAttributesModalRef = ref(null);

const [showActionsDropdown, toggleDropdown] = useToggle();
const closeDropdown = () => toggleDropdown(false);
const openDropdown = () => toggleDropdown(true);

const currentChat = computed(() => getters.getSelectedChat.value);

// UniverZAP: Kanban attach modal + read-only viewer + Autopilot dropdown.
// Viewer is mounted lazily — v-if + ref keeps the funnel/tasks fetch out of
// the conversation header until the operator actually peeks at the board.
const showKanbanModal = ref(false);
const showKanbanViewerModal = ref(false);
const [showAutopilotMenu, toggleAutopilotMenu] = useToggle();
const closeAutopilotMenu = () => toggleAutopilotMenu(false);

const {
  assistants: athenasAssistants,
  fetchAssistants: fetchAthenasAssistants,
} = useAthenasAssistant();
const aiAssistants = computed(() => athenasAssistants.value || []);

const ensureAssistantsLoaded = async () => {
  try {
    await fetchAthenasAssistants();
  } catch (_) {
    /* noop */
  }
};

const openKanbanModal = () => {
  showKanbanModal.value = true;
  closeDropdown();
};
const closeKanbanModal = () => {
  showKanbanModal.value = false;
};
const openKanbanViewerModal = () => {
  showKanbanViewerModal.value = true;
  closeDropdown();
};
const closeKanbanViewerModal = () => {
  showKanbanViewerModal.value = false;
};

const openAutopilotMenu = async () => {
  await ensureAssistantsLoaded();
  toggleAutopilotMenu(true);
  closeDropdown();
};

// Read autopilot state from the canonical columns (ai_mode + ai_assistant_id)
// with a fallback to additional_attributes for older payloads.
const autopilotEnabled = computed(() => {
  const chat = currentChat.value;
  if (!chat) return false;
  if (chat.ai_mode === 'autopilot') return true;
  return !!chat.additional_attributes?.autopilot_enabled;
});
// Explicitly silenced HERE. The only state that beats the agent's own switch,
// so it is read on its own rather than folded into autopilotEnabled: `false`
// and "never set" mean opposite things now.
const autopilotSilenced = computed(
  () => currentChat.value?.additional_attributes?.autopilot_enabled === false
);

// The agent answers everywhere it is assigned when its own autopilot is on, so
// a conversation nobody armed by hand is still being answered. Without this the
// button read "off" while the agent was replying, and turning it "on" looked
// like the fix when the real action available is to silence it.
const agentAutopilotOn = computed(() =>
  aiAssistants.value.some(
    assistant => assistant.active && assistant.autopilot_enabled
  )
);

// What actually happens in THIS conversation, which is the only thing the
// operator cares about when looking at the button.
const answeringHere = computed(
  () =>
    !autopilotSilenced.value &&
    (autopilotEnabled.value || agentAutopilotOn.value)
);

const autopilotAssistantId = computed(() => {
  const chat = currentChat.value;
  return (
    chat?.ai_assistant_id ||
    chat?.additional_attributes?.autopilot_assistant_id ||
    null
  );
});

const setAutopilot = async ({ assistantId, enabled }) => {
  try {
    await store.dispatch('setAutopilot', {
      conversationId: currentChat.value.id,
      aiAssistantId: assistantId,
      enabled,
    });
    useAlert(
      enabled
        ? t('CONVERSATION.AUTOPILOT.ENABLED')
        : t('CONVERSATION.AUTOPILOT.DISABLED')
    );
    closeAutopilotMenu();
  } catch (error) {
    useAlert(error?.message || t('CONVERSATION.AUTOPILOT.ERROR'));
  }
};

const isOpen = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.OPEN
);
const isPending = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.PENDING
);
const isResolved = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.RESOLVED
);
const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const showAdditionalActions = computed(
  () => !isPending.value && !isSnoozed.value
);

const showOpenButton = computed(() => {
  return isPending.value || isSnoozed.value;
});

const getConversationParams = () => {
  const allConversations = document.querySelectorAll(
    '.conversations-list .conversation'
  );

  const activeConversation = document.querySelector(
    'div.conversations-list div.conversation.active'
  );
  const activeConversationIndex = [...allConversations].indexOf(
    activeConversation
  );
  const lastConversationIndex = allConversations.length - 1;

  return {
    all: allConversations,
    activeIndex: activeConversationIndex,
    lastIndex: lastConversationIndex,
  };
};

const openSnoozeModal = () => {
  const ninja = document.querySelector('ninja-keys');
  ninja.open({ parent: 'snooze_conversation' });
};

const toggleStatus = (status, snoozedUntil, customAttributes = null) => {
  closeDropdown();
  isLoading.value = true;

  const payload = {
    conversationId: currentChat.value.id,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
    isLoading.value = false;
  });
};

const handleResolveWithAttributes = ({ attributes, context }) => {
  if (context) {
    const currentCustomAttributes = currentChat.value.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };
    toggleStatus(
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
};

const onCmdOpenConversation = () => {
  toggleStatus(wootConstants.STATUS_TYPE.OPEN);
};

const copyCsatLink = async () => {
  const uuid = currentChat.value?.uuid;
  if (!uuid) {
    useAlert(t('CONVERSATION.CSAT_LINK.MISSING_UUID'));
    return;
  }
  const link = `${window.location.origin}/survey/responses/${uuid}`;
  try {
    await navigator.clipboard.writeText(link);
    useAlert(t('CONVERSATION.CSAT_LINK.COPIED'));
  } catch (_) {
    useAlert(link);
  }
  closeDropdown();
};

const onCmdResolveConversation = () => {
  const currentCustomAttributes = currentChat.value.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    const conversationContext = {
      id: currentChat.value.id,
      snoozedUntil: null,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleStatus(wootConstants.STATUS_TYPE.RESOLVED);
  }
};

const keyboardEvents = {
  'Alt+KeyM': {
    action: () => arrowDownButtonRef.value?.$el.click(),
    allowOnFocusedInput: true,
  },
  'Alt+KeyE': {
    action: async () => {
      onCmdResolveConversation();
    },
  },
  '$mod+Alt+KeyE': {
    action: async event => {
      const { all, activeIndex, lastIndex } = getConversationParams();
      onCmdResolveConversation();

      if (activeIndex < lastIndex) {
        all[activeIndex + 1].click();
      } else if (all.length > 1) {
        all[0].click();
        document.querySelector('.conversations-list').scrollTop = 0;
      }
      event.preventDefault();
    },
  },
};

useKeyboardEvents(keyboardEvents);

useEmitter(CMD_REOPEN_CONVERSATION, onCmdOpenConversation);
useEmitter(CMD_RESOLVE_CONVERSATION, onCmdResolveConversation);
</script>

<template>
  <div class="flex relative justify-end items-center gap-2 resolve-actions">
    <Button
      :label="t('CONVERSATION.HEADER.MOVE_TO_KANBAN')"
      icon="i-lucide-layout-grid"
      size="sm"
      color="slate"
      faded
      no-animation
      data-onboarding="conv-move-kanban"
      @click="openKanbanModal"
    />
    <Button
      :label="t('CONVERSATION.HEADER.VIEW_KANBAN')"
      icon="i-lucide-eye"
      size="sm"
      color="slate"
      faded
      no-animation
      @click="openKanbanViewerModal"
    />
    <Button
      v-if="athenasLoaded"
      :label="
        t('CONVERSATION.HEADER.ATHENAS_BALANCE', {
          balance: athenasBalanceWhole,
        })
      "
      icon="i-lucide-sparkles"
      size="sm"
      :color="athenasButtonColor"
      faded
      no-animation
      data-onboarding="conv-athenas-balance"
      @click="openAthenasTopUp('header_button')"
    />
    <div class="relative">
      <Button
        :label="
          autopilotSilenced
            ? t('CONVERSATION.AUTOPILOT.SILENCED')
            : t('CONVERSATION.HEADER.AUTOPILOT')
        "
        :icon="
          autopilotSilenced
            ? 'i-lucide-bell-off'
            : answeringHere
              ? 'i-lucide-sparkles'
              : 'i-lucide-bot'
        "
        size="sm"
        color="slate"
        :solid="answeringHere"
        :faded="!answeringHere"
        no-animation
        data-onboarding="conv-autopilot"
        @click="openAutopilotMenu"
      />
      <div
        v-if="showAutopilotMenu"
        v-on-clickaway="closeAutopilotMenu"
        class="border rounded-lg shadow-lg border-n-strong dark:border-n-strong p-2 z-10 bg-n-alpha-3 backdrop-blur-[100px] absolute right-0 top-full mt-1 min-w-[16rem] max-w-[20rem]"
      >
        <p
          class="text-[11px] uppercase tracking-wide text-n-slate-10 mb-1 px-2"
        >
          {{ t('CONVERSATION.AUTOPILOT.MENU_TITLE') }}
        </p>
        <!-- Answering here, however it was switched on: the useful action is to
             stop it in this conversation, and saying "desligar autopiloto"
             would suggest it stops everywhere. -->
        <button
          v-if="answeringHere"
          type="button"
          class="w-full text-left px-3 py-2 text-sm text-n-ruby-11 hover:bg-n-alpha-1 rounded-md"
          @click="setAutopilot({ assistantId: null, enabled: false })"
        >
          {{
            agentAutopilotOn && !autopilotEnabled
              ? t('CONVERSATION.AUTOPILOT.SILENCE')
              : t('CONVERSATION.AUTOPILOT.TURN_OFF')
          }}
        </button>
        <!-- Silenced by hand while the agent answers everywhere else. Clearing
             the flag hands the conversation back to the agent, so it is a
             separate action from picking an assistant. -->
        <button
          v-if="autopilotSilenced && agentAutopilotOn"
          type="button"
          class="w-full text-left px-3 py-2 text-sm text-n-teal-11 hover:bg-n-alpha-1 rounded-md"
          @click="
            setAutopilot({ assistantId: autopilotAssistantId, enabled: true })
          "
        >
          {{ t('CONVERSATION.AUTOPILOT.UNSILENCE') }}
        </button>
        <p
          v-if="!aiAssistants.length"
          class="text-xs text-n-slate-11 px-3 py-2"
        >
          {{ t('CONVERSATION.AUTOPILOT.NO_ASSISTANTS') }}
        </p>
        <button
          v-for="assistant in aiAssistants"
          :key="assistant.id"
          type="button"
          class="w-full text-left px-3 py-2 text-sm rounded-md flex items-center gap-2"
          :class="
            assistant.id === autopilotAssistantId
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="setAutopilot({ assistantId: assistant.id, enabled: true })"
        >
          <span class="i-lucide-bot size-3.5 flex-shrink-0" />
          <span class="truncate">{{ assistant.name }}</span>
        </button>
      </div>
    </div>
    <ButtonGroup
      class="flex-shrink-0 rounded-lg shadow outline-1 outline"
      :class="!showOpenButton ? 'outline-n-container' : 'outline-transparent'"
      data-onboarding="conv-resolve-action"
    >
      <Button
        v-if="isOpen"
        :label="t('CONVERSATION.HEADER.RESOLVE_ACTION')"
        size="sm"
        color="slate"
        no-animation
        class="ltr:rounded-r-none rtl:rounded-l-none !outline-0"
        :is-loading="isLoading"
        @click="onCmdResolveConversation"
      />
      <Button
        v-else-if="isResolved"
        :label="t('CONVERSATION.HEADER.REOPEN_ACTION')"
        size="sm"
        color="slate"
        no-animation
        class="ltr:rounded-r-none rtl:rounded-l-none !outline-0"
        :is-loading="isLoading"
        @click="onCmdOpenConversation"
      />
      <Button
        v-else-if="showOpenButton"
        :label="t('CONVERSATION.HEADER.OPEN_ACTION')"
        size="sm"
        color="slate"
        no-animation
        :is-loading="isLoading"
        @click="onCmdOpenConversation"
      />
      <Button
        v-if="showAdditionalActions"
        ref="arrowDownButtonRef"
        icon="i-lucide-chevron-down"
        :disabled="isLoading"
        size="sm"
        no-animation
        class="ltr:rounded-l-none rtl:rounded-r-none !outline-0"
        color="slate"
        trailing-icon
        @click="openDropdown"
      />
    </ButtonGroup>
    <div
      v-if="showActionsDropdown"
      v-on-clickaway="closeDropdown"
      class="border rounded-lg shadow-lg border-n-strong dark:border-n-strong box-content p-2 w-fit z-10 bg-n-alpha-3 backdrop-blur-[100px] absolute block left-auto top-full mt-0.5 start-0 xl:start-auto xl:end-0 max-w-[12.5rem] min-w-[9.75rem] [&_ul>li]:mb-0"
    >
      <WootDropdownMenu class="mb-0">
        <WootDropdownItem v-if="!isPending">
          <Button
            :label="t('CONVERSATION.RESOLVE_DROPDOWN.SNOOZE_UNTIL')"
            ghost
            slate
            sm
            start
            icon="i-lucide-alarm-clock-minus"
            class="w-full"
            @click="() => openSnoozeModal()"
          />
        </WootDropdownItem>
        <WootDropdownItem v-if="!isPending">
          <Button
            :label="t('CONVERSATION.RESOLVE_DROPDOWN.MARK_PENDING')"
            ghost
            slate
            sm
            start
            icon="i-lucide-circle-dot-dashed"
            class="w-full"
            @click="() => toggleStatus(wootConstants.STATUS_TYPE.PENDING)"
          />
        </WootDropdownItem>
        <WootDropdownItem>
          <Button
            :label="t('CONVERSATION.RESOLVE_DROPDOWN.COPY_CSAT_LINK')"
            ghost
            slate
            sm
            start
            icon="i-lucide-link"
            class="w-full"
            @click="copyCsatLink"
          />
        </WootDropdownItem>
      </WootDropdownMenu>
    </div>
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
    <ConversationKanbanAttachModal
      v-if="currentChat?.id"
      :show="showKanbanModal"
      :conversation="currentChat"
      @close="closeKanbanModal"
    />
    <ConversationKanbanViewerModal
      v-if="showKanbanViewerModal"
      :show="showKanbanViewerModal"
      @close="closeKanbanViewerModal"
    />
  </div>
</template>

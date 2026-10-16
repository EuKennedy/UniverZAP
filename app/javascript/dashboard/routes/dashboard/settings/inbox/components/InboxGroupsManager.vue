<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import {
  CUSTOM_GROUP_POSITION,
  channelGroupIcon,
  channelGroupLabel,
  groupInboxes,
  inboxKind,
  kindPosition,
} from 'dashboard/components-next/sidebar/helper/channelGroups';

// UniverZAP: the groups of "Canais". A default group (one per kind, id null)
// only becomes a row in inbox_groups when it is renamed or receives an inbox
// of another kind; deleting that row gives the kind its default back.
const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const inboxGroups = useMapGetter('inboxGroups/getInboxGroups');

const newGroupName = ref('');
const isSaving = ref(false);

const groups = computed(() =>
  groupInboxes(
    inboxes.value.slice().sort((a, b) => a.name.localeCompare(b.name)),
    inboxGroups.value,
    { includeEmpty: true }
  )
);

const save = async action => {
  isSaving.value = true;
  try {
    await action();
    useAlert(t('INBOX_MGMT.GROUPS.SAVED'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.GROUPS.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

// The saved row behind a group, creating the one of a default group.
const persistedGroupId = async group => {
  if (group.id) return group.id;
  const created = await store.dispatch('inboxGroups/create', {
    name: channelGroupLabel(group, t),
    kind: group.kind,
    position: kindPosition(group.kind),
  });
  return created.id;
};

const rename = (group, name) => {
  const trimmed = name.trim();
  if (!trimmed || trimmed === channelGroupLabel(group, t)) return;
  save(async () => {
    if (group.id) {
      await store.dispatch('inboxGroups/update', {
        id: group.id,
        name: trimmed,
      });
    } else {
      await store.dispatch('inboxGroups/create', {
        name: trimmed,
        kind: group.kind,
        position: kindPosition(group.kind),
      });
    }
  });
};

const remove = group =>
  save(() => store.dispatch('inboxGroups/delete', group.id));

const createGroup = () => {
  const name = newGroupName.value.trim();
  if (!name) return;
  save(async () => {
    await store.dispatch('inboxGroups/create', {
      name,
      position: CUSTOM_GROUP_POSITION + inboxGroups.value.length,
    });
    newGroupName.value = '';
  });
};

// Back in the group of its own kind means no explicit group at all, so the
// inbox keeps following its kind.
const move = (inbox, groupKey) => {
  const target = groups.value.find(group => group.key === groupKey);
  save(async () => {
    const inboxGroupId =
      target.kind && target.kind === inboxKind(inbox)
        ? null
        : await persistedGroupId(target);
    await store.dispatch('inboxes/updateInbox', {
      id: inbox.id,
      inbox_group_id: inboxGroupId,
      formData: false,
    });
  });
};
</script>

<template>
  <div class="grid gap-4">
    <form class="flex gap-2" @submit.prevent="createGroup">
      <input
        v-model="newGroupName"
        type="text"
        maxlength="60"
        :placeholder="t('INBOX_MGMT.GROUPS.NEW_GROUP_PLACEHOLDER')"
        class="flex-1 h-8 px-3 mb-0 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 outline outline-1 outline-n-weak"
      />
      <Button
        type="submit"
        size="sm"
        icon="i-lucide-plus"
        :label="t('INBOX_MGMT.GROUPS.CREATE')"
        :disabled="!newGroupName.trim() || isSaving"
      />
    </form>

    <ul class="grid gap-3 m-0 list-none max-h-[60vh] overflow-y-auto">
      <li
        v-for="group in groups"
        :key="group.key"
        class="grid gap-2 p-3 rounded-xl outline outline-1 outline-n-weak bg-n-alpha-1"
      >
        <div class="flex items-center gap-2">
          <Icon
            :icon="channelGroupIcon(group)"
            class="flex-shrink-0 size-4 text-n-slate-11"
          />
          <input
            :value="channelGroupLabel(group, t)"
            type="text"
            maxlength="60"
            class="flex-1 h-7 px-2 mb-0 text-sm font-medium bg-transparent rounded-lg text-n-slate-12 hover:bg-n-alpha-2 focus:bg-n-alpha-2"
            @keydown.enter.prevent="$event.target.blur()"
            @change="rename(group, $event.target.value)"
          />
          <Button
            v-if="group.id"
            v-tooltip.top="
              group.kind
                ? t('INBOX_MGMT.GROUPS.RESET')
                : t('INBOX_MGMT.GROUPS.DELETE')
            "
            :icon="group.kind ? 'i-lucide-rotate-ccw' : 'i-lucide-trash-2'"
            xs
            faded
            :ruby="!group.kind"
            :slate="!!group.kind"
            :disabled="isSaving"
            @click="remove(group)"
          />
        </div>
        <p
          v-if="!group.inboxes.length"
          class="px-2 mb-0 text-xs text-n-slate-10"
        >
          {{ t('INBOX_MGMT.GROUPS.EMPTY') }}
        </p>
        <div
          v-for="inbox in group.inboxes"
          :key="inbox.id"
          class="flex items-center gap-2 px-2"
        >
          <ChannelIcon
            :inbox="inbox"
            class="flex-shrink-0 size-4 text-n-slate-11"
          />
          <span class="flex-1 text-sm truncate text-n-slate-12">
            {{ inbox.name }}
          </span>
          <select
            :value="group.key"
            :aria-label="t('INBOX_MGMT.GROUPS.MOVE_TO')"
            :disabled="isSaving"
            class="w-40 h-7 px-2 mb-0 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11"
            @change="move(inbox, $event.target.value)"
          >
            <option
              v-for="option in groups"
              :key="option.key"
              :value="option.key"
            >
              {{ channelGroupLabel(option, t) }}
            </option>
          </select>
        </div>
      </li>
    </ul>
  </div>
</template>

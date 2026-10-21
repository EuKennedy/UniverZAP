<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import ContactListsAPI from 'dashboard/api/contactLists';

// Listas de distribuição como público. Quem saiu do grupo, quem ficou sem
// telefone e quem nunca falou com o salão sem confirmação ficam de fora no
// backend (Broadcasts::AudienceResolver).
const props = defineProps({
  modelValue: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const lists = ref([]);

const toggle = id => {
  emit(
    'update:modelValue',
    props.modelValue.includes(id)
      ? props.modelValue.filter(item => item !== id)
      : [...props.modelValue, id]
  );
};

onMounted(async () => {
  try {
    const { data } = await ContactListsAPI.get();
    lists.value = data.payload;
  } catch {
    lists.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="audience-lists">
    <div v-if="lists.length" class="flex flex-wrap gap-2">
      <button
        v-for="list in lists"
        :key="list.id"
        type="button"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium cursor-pointer transition-colors"
        :class="
          modelValue.includes(list.id)
            ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
            : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
        "
        :data-testid="`audience-list-${list.id}`"
        @click="toggle(list.id)"
      >
        <span
          class="size-3"
          :class="
            list.source === 'group' ? 'i-lucide-users-round' : 'i-lucide-list'
          "
        />
        {{ list.name }}
        <span class="tabular-nums text-n-slate-10">
          {{ list.members_count }}
        </span>
      </button>
    </div>
    <p v-else class="m-0 text-[11px] text-n-slate-10">
      {{ t('BROADCAST.AUDIENCE.LISTS_EMPTY') }}
    </p>
    <router-link
      :to="accountScopedRoute('contact_lists_index')"
      class="text-[11px] w-fit text-n-iris-11 hover:underline"
    >
      {{ t('BROADCAST.AUDIENCE.LISTS_MANAGE') }}
    </router-link>
  </div>
</template>

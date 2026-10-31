<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ContactFieldValue from './ContactFieldValue.vue';
import ContactIdentity from './ContactIdentity.vue';
import { useContactFieldLabel } from './useContactFieldLabel';

const props = defineProps({
  contacts: { type: Array, required: true },
  fields: { type: Array, required: true },
  selectedIds: { type: Set, required: true },
  labelColors: { type: Object, default: () => ({}) },
  summaries: { type: Object, default: () => ({}) },
  activeSort: { type: String, default: '' },
  activeOrdering: { type: String, default: '' },
});

const emit = defineEmits(['open', 'select', 'selectAll', 'sort']);

const { t } = useI18n();
const fieldLabel = useContactFieldLabel();

const NAME_SORT = 'name';

const allSelected = computed(
  () =>
    props.contacts.length > 0 &&
    props.contacts.every(({ id }) => props.selectedIds.has(id))
);

const nextOrder = sort =>
  props.activeSort === sort && props.activeOrdering === '' ? '-' : '';

const sortIcon = sort => {
  if (props.activeSort !== sort) return '';
  return props.activeOrdering === '-'
    ? 'i-lucide-arrow-down'
    : 'i-lucide-arrow-up';
};

const sortBy = sort => emit('sort', { sort, order: nextOrder(sort) });
</script>

<template>
  <div
    class="overflow-x-auto rounded-xl outline outline-1 -outline-offset-1 outline-n-weak bg-n-solid-2"
  >
    <table class="w-full text-sm border-separate border-spacing-0">
      <thead>
        <tr class="text-xs text-n-slate-11">
          <th
            class="sticky start-0 z-[2] px-3 py-2.5 font-medium border-b rounded-ss-xl text-start border-n-weak bg-n-solid-2"
          >
            <span class="flex items-center gap-3">
              <Checkbox
                :model-value="allSelected"
                @change="emit('selectAll', $event.target.checked)"
              />
              <button
                type="button"
                class="inline-flex items-center gap-1 text-xs font-medium hover:text-n-slate-12"
                @click="sortBy(NAME_SORT)"
              >
                {{ t('CONTACTS_LAYOUT.FIELDS.NAME') }}
                <span
                  v-if="sortIcon(NAME_SORT)"
                  class="size-3"
                  :class="sortIcon(NAME_SORT)"
                />
              </button>
            </span>
          </th>
          <th
            v-for="field in fields"
            :key="field.key"
            class="px-3 py-2.5 font-medium border-b text-start whitespace-nowrap border-n-weak"
            :class="{ 'text-n-teal-11': field.belezaki }"
          >
            <button
              v-if="field.sort"
              type="button"
              class="inline-flex items-center gap-1 text-xs font-medium hover:text-n-slate-12"
              @click="sortBy(field.sort)"
            >
              {{ fieldLabel(field) }}
              <span
                v-if="sortIcon(field.sort)"
                class="size-3"
                :class="sortIcon(field.sort)"
              />
            </button>
            <template v-else>{{ fieldLabel(field) }}</template>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="contact in contacts"
          :key="contact.id"
          class="cursor-pointer group"
          tabindex="0"
          @click="emit('open', contact)"
          @keydown.enter="emit('open', contact)"
        >
          <td
            class="sticky z-[1] px-3 py-2 border-b start-0 border-n-weak group-last:border-b-0 group-hover:bg-n-solid-3"
            :class="
              selectedIds.has(contact.id) ? 'bg-n-solid-3' : 'bg-n-solid-2'
            "
          >
            <span class="flex items-center gap-3 min-w-52 max-w-72">
              <span @click.stop>
                <Checkbox
                  :model-value="selectedIds.has(contact.id)"
                  @change="
                    emit('select', {
                      id: contact.id,
                      value: $event.target.checked,
                    })
                  "
                />
              </span>
              <ContactIdentity :contact="contact" />
            </span>
          </td>
          <td
            v-for="field in fields"
            :key="field.key"
            class="px-3 py-2 border-b border-n-weak group-last:border-b-0 group-hover:bg-n-solid-3 max-w-56 min-w-24 whitespace-nowrap"
            :class="{ 'bg-n-solid-3': selectedIds.has(contact.id) }"
          >
            <ContactFieldValue
              :field="field"
              :contact="contact"
              :label-colors="labelColors"
              :summary="summaries[contact.id]"
            />
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

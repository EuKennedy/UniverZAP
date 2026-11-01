<script setup>
import { computed } from 'vue';
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
});

const emit = defineEmits(['open', 'select']);

const fieldLabel = useContactFieldLabel();

// Phone sits under the name, tags and pills on one line; everything else is a
// label and a value, belezaki last. A card only lists what the contact has: the
// empty rows hide themselves, and the side panel still shows every field.
const BADGES = ['type', 'origin', 'labels'];
const badges = computed(() =>
  props.fields.filter(({ key }) => BADGES.includes(key))
);
const details = computed(() =>
  props.fields.filter(
    ({ key, belezaki }) => !belezaki && key !== 'phone' && !BADGES.includes(key)
  )
);
const belezakiFields = computed(() => props.fields.filter(f => f.belezaki));
const showPhone = computed(() =>
  props.fields.some(({ key }) => key === 'phone')
);
</script>

<template>
  <div
    class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3 3xl:grid-cols-4"
  >
    <article
      v-for="contact in contacts"
      :key="contact.id"
      class="relative flex flex-col gap-3 p-4 transition cursor-pointer group rounded-xl outline outline-1 -outline-offset-1 glass-panel"
      :class="
        selectedIds.has(contact.id)
          ? 'outline-n-teal-7'
          : 'outline-n-weak hover:outline-n-strong'
      "
      tabindex="0"
      @click="emit('open', contact)"
      @keydown.enter="emit('open', contact)"
    >
      <span
        class="absolute top-3 end-3 sm:opacity-0 sm:group-hover:opacity-100"
        :class="{ 'sm:opacity-100': selectedIds.has(contact.id) }"
        @click.stop
      >
        <Checkbox
          :model-value="selectedIds.has(contact.id)"
          @change="
            emit('select', { id: contact.id, value: $event.target.checked })
          "
        />
      </span>

      <div class="pe-6">
        <ContactIdentity
          :contact="contact"
          :size="44"
          :show-phone="showPhone"
        />
      </div>

      <div
        v-if="badges.length"
        class="flex flex-wrap items-center gap-1 min-h-6"
      >
        <ContactFieldValue
          v-for="field in badges"
          :key="field.key"
          :field="field"
          :contact="contact"
          :label-colors="labelColors"
          class="[&.text-n-slate-8]:hidden"
        />
      </div>

      <dl v-if="details.length" class="grid gap-1 text-xs">
        <div
          v-for="field in details"
          :key="field.key"
          class="grid grid-cols-[8.5rem_minmax(0,1fr)] gap-2 [&:has(.text-n-slate-8)]:hidden"
        >
          <dt class="truncate text-n-slate-10">{{ fieldLabel(field) }}</dt>
          <dd class="min-w-0">
            <ContactFieldValue :field="field" :contact="contact" />
          </dd>
        </div>
      </dl>

      <dl
        v-if="belezakiFields.length"
        class="grid gap-1 p-2 text-xs rounded-lg bg-brand-gradient-soft"
      >
        <div
          v-for="field in belezakiFields"
          :key="field.key"
          class="grid grid-cols-[8.5rem_minmax(0,1fr)] gap-2 [&:has(.text-n-slate-8)]:hidden"
        >
          <dt class="truncate text-n-teal-11">{{ fieldLabel(field) }}</dt>
          <dd class="min-w-0">
            <ContactFieldValue
              :field="field"
              :contact="contact"
              :summary="summaries[contact.id]"
            />
          </dd>
        </div>
      </dl>
    </article>
  </div>
</template>

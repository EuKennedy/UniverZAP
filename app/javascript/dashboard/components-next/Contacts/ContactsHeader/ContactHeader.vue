<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ContactSortMenu from './components/ContactSortMenu.vue';
import ContactMoreActions from './components/ContactMoreActions.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';

defineProps({
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, required: true },
  buttonLabel: { type: String, default: '' },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
  isSegmentsView: { type: Boolean, default: false },
  hasActiveFilters: { type: Boolean, default: false },
  subtitle: { type: String, default: '' },
  isLabelView: { type: Boolean, default: false },
  isActiveView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'search',
  'filter',
  'update:sort',
  'add',
  'import',
  'export',
  'createSegment',
  'deleteSegment',
]);
</script>

<template>
  <header class="flex items-center justify-between gap-3 px-6 pt-6 pb-4">
    <div class="flex items-center min-w-0 gap-3">
      <span
        class="flex items-center justify-center flex-shrink-0 rounded-xl size-10 bg-brand-gradient text-n-slate-1 dark:text-n-solid-1 shadow-[0_6px_18px_-6px_rgba(20,230,127,0.6)]"
      >
        <span class="i-lucide-contact size-5" />
      </span>
      <div class="min-w-0">
        <h1 class="text-xl font-semibold truncate text-n-slate-12">
          {{ headerTitle }}
        </h1>
        <p v-if="subtitle" class="text-xs truncate text-n-slate-11">
          {{ subtitle }}
        </p>
      </div>
    </div>
    <div class="flex items-center flex-shrink-0 gap-2">
      <ContactMoreActions
        @add="emit('add')"
        @import="emit('import')"
        @export="emit('export')"
      />
      <ComposeConversation>
        <template #trigger>
          <Button :label="buttonLabel" size="sm" />
        </template>
      </ComposeConversation>
    </div>
  </header>

  <slot name="stats" />

  <div
    class="sticky top-0 z-20 flex flex-wrap items-center gap-2 px-6 py-3 bg-n-surface-1/90 backdrop-blur-xl"
  >
    <Input
      v-if="showSearch"
      :model-value="searchValue"
      type="search"
      :placeholder="$t('CONTACTS_LAYOUT.HEADER.SEARCH_PLACEHOLDER')"
      :custom-input-class="[
        'h-8 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 ltr:!pl-8 !py-1 rtl:!pr-8',
      ]"
      class="w-full sm:w-56"
      @input="emit('search', $event.target.value)"
    >
      <template #prefix>
        <Icon
          icon="i-lucide-search"
          class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
        />
      </template>
    </Input>
    <slot name="quickFilters" />
    <div class="flex flex-wrap items-center gap-2 ms-auto">
      <div v-if="!isLabelView && !isActiveView" class="relative">
        <Button
          id="toggleContactsFilterButton"
          :icon="isSegmentsView ? 'i-lucide-pen-line' : 'i-lucide-list-filter'"
          :label="$t('CONTACTS_LAYOUT.HEADER.ADVANCED_FILTERS')"
          color="slate"
          size="sm"
          class="relative"
          variant="ghost"
          @click="emit('filter')"
        >
          <div
            v-if="hasActiveFilters && !isSegmentsView"
            class="absolute top-0 right-0 w-2 h-2 rounded-full bg-n-brand"
          />
        </Button>
        <slot name="filter" />
      </div>
      <Button
        v-if="
          hasActiveFilters && !isSegmentsView && !isLabelView && !isActiveView
        "
        icon="i-lucide-save"
        color="slate"
        size="sm"
        variant="ghost"
        @click="emit('createSegment')"
      />
      <Button
        v-if="isSegmentsView && !isLabelView && !isActiveView"
        icon="i-lucide-trash"
        color="slate"
        size="sm"
        variant="ghost"
        @click="emit('deleteSegment')"
      />
      <ContactSortMenu
        :active-sort="activeSort"
        :active-ordering="activeOrdering"
        @update:sort="emit('update:sort', $event)"
      />
      <slot name="viewControls" />
    </div>
  </div>
</template>

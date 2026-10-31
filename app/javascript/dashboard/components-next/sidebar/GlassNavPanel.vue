<script setup>
import { computed, ref } from 'vue';
import { useEventListener } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';

// UniverZAP: the complementary navigation beside the rail. It only draws:
// whoever uses it hands over the sections, already filtered by permission, and
// reacts to `select`. Each item is { key, name, icon, count?, to?, active?,
// risk? }; an item with `to` is a link, one without emits.
const props = defineProps({
  title: { type: String, required: true },
  sections: { type: Array, required: true },
  collapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'toggle']);

const query = ref('');
const searchInput = ref(null);

const normalize = text =>
  text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

const visibleSections = computed(() => {
  const term = normalize(query.value.trim());
  if (!term) return props.sections;
  return props.sections
    .map(section => ({
      ...section,
      items: section.items.filter(item => normalize(item.name).includes(term)),
    }))
    .filter(section => section.items.length);
});

const isTyping = target =>
  target?.isContentEditable || ['INPUT', 'TEXTAREA'].includes(target?.tagName);

useEventListener(document, 'keydown', event => {
  if (event.key !== '/' || props.collapsed || isTyping(event.target)) return;
  event.preventDefault();
  searchInput.value?.focus();
});

const openFirstMatch = () => {
  const first = visibleSections.value[0]?.items[0];
  if (first) emit('select', first);
};

const rowClass = item => [
  props.collapsed ? 'justify-center' : 'px-2.5',
  item.active
    ? 'bg-brand-gradient-soft text-n-teal-11 outline outline-1 outline-n-teal-7 shadow-[0_0_20px_-6px_rgba(20,230,127,0.65)]'
    : 'hover:bg-n-alpha-2 hover:text-n-slate-12',
  !item.active && item.risk ? 'text-n-amber-11' : '',
  !item.active && !item.risk ? 'text-n-slate-11' : '',
];
</script>

<template>
  <nav
    class="relative flex-col flex-shrink-0 hidden h-full overflow-hidden transition-[width] duration-200 md:flex border-e border-n-weak bg-n-alpha-1 backdrop-blur-xl"
    :class="collapsed ? 'w-14' : 'w-56'"
    :aria-label="title"
  >
    <span
      class="absolute rounded-full pointer-events-none -top-20 -start-16 size-56 bg-brand-gradient opacity-[0.14] blur-3xl"
    />
    <span
      class="absolute rounded-full pointer-events-none -bottom-24 -end-20 size-56 bg-brand-gradient opacity-[0.08] blur-3xl"
    />

    <header
      class="relative flex items-center gap-2 px-3 h-14 shrink-0"
      :class="{ 'justify-center': collapsed }"
    >
      <h2
        v-if="!collapsed"
        class="flex-1 min-w-0 mb-0 text-base font-semibold truncate text-n-slate-12"
      >
        {{ title }}
      </h2>
      <button
        type="button"
        class="grid transition-colors rounded-lg size-8 place-content-center text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="
          collapsed
            ? $t('CHAT_LIST.QUICK_NAV.EXPAND')
            : $t('CHAT_LIST.QUICK_NAV.COLLAPSE')
        "
        :aria-expanded="!collapsed"
        @click="emit('toggle')"
      >
        <span
          class="size-4 rtl:rotate-180"
          :class="
            collapsed ? 'i-lucide-panel-left-open' : 'i-lucide-panel-left-close'
          "
        />
      </button>
    </header>

    <div v-if="!collapsed" class="relative px-3 pb-3 shrink-0">
      <label
        class="flex items-center gap-2 px-2.5 mb-0 transition-colors border h-9 rounded-xl border-n-alpha-3 bg-n-alpha-1 focus-within:border-n-teal-7"
      >
        <span class="i-lucide-search size-4 shrink-0 text-n-slate-10" />
        <input
          ref="searchInput"
          v-model="query"
          type="search"
          class="flex-1 min-w-0 !mb-0 !p-0 !h-auto text-sm bg-transparent !border-0 !outline-none !ring-0 text-n-slate-12 placeholder:text-n-slate-10"
          :placeholder="$t('CHAT_LIST.QUICK_NAV.SEARCH')"
          :aria-label="$t('CHAT_LIST.QUICK_NAV.SEARCH')"
          @keydown.enter.prevent="openFirstMatch"
          @keydown.esc="query = ''"
        />
        <kbd
          class="px-1.5 text-xs border rounded-md shrink-0 text-n-slate-10 border-n-alpha-3"
        >
          /
        </kbd>
      </label>
    </div>

    <div
      class="relative flex flex-col flex-1 min-h-0 gap-4 px-2 pb-3 overflow-y-auto"
    >
      <section
        v-for="section in visibleSections"
        :key="section.key"
        :class="{ 'mt-auto': section.pinned }"
      >
        <h3
          v-if="section.title && !collapsed"
          class="px-2.5 pb-1 mb-0 font-medium tracking-wide uppercase text-xxs text-n-slate-10"
        >
          {{ section.title }}
        </h3>
        <ul class="flex flex-col gap-1 mb-0 list-none">
          <li v-for="item in section.items" :key="item.key">
            <component
              :is="item.to ? 'router-link' : 'button'"
              :to="item.to || undefined"
              :type="item.to ? undefined : 'button'"
              class="relative flex items-center w-full gap-2.5 h-9 text-sm transition-all rounded-xl motion-safe:active:scale-[0.98]"
              :class="rowClass(item)"
              :title="item.name"
              :aria-label="item.name"
              :aria-current="item.active ? 'page' : undefined"
              @click="item.to ? undefined : emit('select', item)"
            >
              <Icon
                v-if="item.icon"
                :icon="item.icon"
                class="size-4 shrink-0"
              />
              <template v-if="!collapsed">
                <span class="flex-1 min-w-0 truncate text-start">
                  {{ item.name }}
                </span>
                <span
                  v-if="item.count !== undefined"
                  class="text-xs tabular-nums"
                >
                  {{ item.count }}
                </span>
              </template>
              <span
                v-else-if="item.risk"
                class="absolute rounded-full top-1 end-1.5 size-1.5 bg-n-amber-9 motion-safe:animate-pulse"
              />
            </component>
          </li>
        </ul>
      </section>
      <p
        v-if="!visibleSections.length"
        class="px-2.5 mb-0 text-sm text-n-slate-10"
      >
        {{ $t('CHAT_LIST.QUICK_NAV.NO_RESULT') }}
      </p>
    </div>
  </nav>
</template>

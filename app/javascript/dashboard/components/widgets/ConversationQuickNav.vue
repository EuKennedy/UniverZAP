<script setup>
import { useI18n } from 'vue-i18n';

// UniverZAP: the extra sidebar beside the conversation list. Every queue and
// every kind of chat one click away with its live count, so nothing hides in
// the Todos dropdown or in tabs cut off by the list width. Same views and same
// numbers the list already has; it only emits what the tabs emit.
defineProps({
  views: { type: Array, required: true },
  channels: { type: Array, required: true },
  activeKey: { type: String, required: true },
  shortcuts: { type: Array, required: true },
  collapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['selectView', 'selectChannel', 'toggle']);

const { t } = useI18n();

const ICONS = {
  in_attendance: 'i-lucide-messages-square',
  waiting: 'i-lucide-hourglass',
  awaiting_customer: 'i-lucide-reply',
  me: 'i-lucide-user-round',
  unassigned: 'i-lucide-user-round-x',
  scheduled: 'i-lucide-calendar-check',
  resolved: 'i-lucide-circle-check',
  groups: 'i-lucide-users-round',
  status: 'i-lucide-circle-dot',
  team: 'i-lucide-briefcase',
};

const isRisk = item => item.key === 'waiting' && item.count > 0;

const itemClass = (item, isActive, collapsed) => [
  collapsed ? 'justify-center px-0' : 'px-2.5',
  isActive
    ? 'bg-brand-gradient-soft text-n-teal-11 shadow-[0_0_18px_-6px_rgba(20,230,127,0.6)]'
    : 'hover:bg-n-alpha-2 hover:text-n-slate-12',
  !isActive && isRisk(item) ? 'text-n-amber-11' : '',
  !isActive && !isRisk(item) ? 'text-n-slate-11' : '',
];

const select = (group, key) =>
  group === 'QUEUES' ? emit('selectView', key) : emit('selectChannel', key);

const sectionTitle = key => t(`CHAT_LIST.QUICK_NAV.${key}`);
</script>

<template>
  <nav
    class="relative flex-col flex-shrink-0 hidden h-full overflow-hidden transition-[width] duration-200 border-e lg:flex border-n-weak bg-n-alpha-1 backdrop-blur-xl"
    :class="collapsed ? 'w-12' : 'w-48'"
    :aria-label="$t('CHAT_LIST.QUICK_NAV.LABEL')"
  >
    <span
      class="absolute rounded-full pointer-events-none -top-16 -start-12 size-40 bg-brand-gradient opacity-10 blur-3xl"
    />
    <div
      class="relative flex items-center h-12 px-2 shrink-0"
      :class="collapsed ? 'justify-center' : 'justify-between'"
    >
      <span
        v-if="!collapsed"
        class="text-sm font-semibold truncate ps-1 text-n-slate-12"
      >
        {{ $t('CHAT_LIST.QUICK_NAV.TITLE') }}
      </span>
      <button
        type="button"
        class="grid transition-colors rounded-lg size-7 place-content-center text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="
          collapsed
            ? $t('CHAT_LIST.QUICK_NAV.EXPAND')
            : $t('CHAT_LIST.QUICK_NAV.COLLAPSE')
        "
        :aria-expanded="!collapsed"
        @click="emit('toggle')"
      >
        <span
          class="size-4"
          :class="
            collapsed ? 'i-lucide-panel-left-open' : 'i-lucide-panel-left-close'
          "
        />
      </button>
    </div>

    <div
      class="relative flex flex-col flex-1 min-h-0 gap-4 px-1.5 pb-3 overflow-y-auto"
    >
      <section
        v-for="group in [
          { key: 'QUEUES', items: views },
          { key: 'CHANNELS', items: channels },
        ]"
        :key="group.key"
      >
        <h3
          v-if="!collapsed"
          class="px-2.5 pb-1 mb-0 text-xxs font-medium tracking-wide uppercase text-n-slate-10"
        >
          {{ sectionTitle(group.key) }}
        </h3>
        <ul class="flex flex-col gap-0.5 mb-0 list-none">
          <li v-for="item in group.items" :key="item.key">
            <button
              type="button"
              class="relative flex items-center w-full gap-2 h-8 text-sm transition-all rounded-lg motion-safe:active:scale-[0.98]"
              :class="itemClass(item, item.key === activeKey, collapsed)"
              :title="item.name"
              :aria-label="item.name"
              :aria-current="item.key === activeKey ? 'true' : undefined"
              @click="select(group.key, item.key)"
            >
              <span class="size-4 shrink-0" :class="ICONS[item.key]" />
              <template v-if="!collapsed">
                <span class="flex-1 min-w-0 truncate text-start">
                  {{ item.name }}
                </span>
                <span class="text-xs tabular-nums">{{ item.count }}</span>
              </template>
              <span
                v-else-if="isRisk(item)"
                class="absolute rounded-full top-1 end-1.5 size-1.5 bg-n-amber-9 motion-safe:animate-pulse"
              />
            </button>
          </li>
        </ul>
      </section>

      <section class="mt-auto">
        <h3
          v-if="!collapsed"
          class="px-2.5 pb-1 mb-0 text-xxs font-medium tracking-wide uppercase text-n-slate-10"
        >
          {{ $t('CHAT_LIST.QUICK_NAV.SHORTCUTS') }}
        </h3>
        <ul class="flex flex-col gap-0.5 mb-0 list-none">
          <li v-for="link in shortcuts" :key="link.key">
            <router-link
              :to="link.to"
              class="flex items-center h-8 gap-2 text-sm transition-colors rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :class="collapsed ? 'justify-center' : 'px-2.5'"
              :title="link.name"
              :aria-label="link.name"
            >
              <span class="size-4 shrink-0" :class="link.icon" />
              <span v-if="!collapsed" class="truncate">{{ link.name }}</span>
            </router-link>
          </li>
        </ul>
      </section>
    </div>
  </nav>
</template>

<script setup>
import { computed, onMounted, onUnmounted, watch, nextTick, ref } from 'vue';
import { useSidebarContext, usePopoverState } from './provider';
import { useRoute, useRouter } from 'vue-router';
import Policy from 'dashboard/components/policy.vue';
import Icon from 'next/icon/Icon.vue';
import SidebarGroupHeader from './SidebarGroupHeader.vue';
import SidebarGroupLeaf from './SidebarGroupLeaf.vue';
import SidebarSubGroup from './SidebarSubGroup.vue';
import SidebarGroupEmptyLeaf from './SidebarGroupEmptyLeaf.vue';
import SidebarCollapsedPopover from './SidebarCollapsedPopover.vue';

const props = defineProps({
  name: { type: String, required: true },
  label: { type: String, required: true },
  icon: { type: [String, Object, Function], default: null },
  to: { type: Object, default: null },
  // An address outside the app, for a tab that lives on another product. It
  // exists so those tabs can sit in the menu and be organised like any other,
  // instead of being hardcoded beside it where nobody can move them.
  href: { type: String, default: '' },
  activeOn: { type: Array, default: () => [] },
  children: { type: Array, default: undefined },
  getterKeys: { type: Object, default: () => ({}) },
  dataOnboarding: { type: String, default: null },
  // True when a section a super admin created is holding this group. The group
  // renders itself the same either way; only the tree rail it wears changes,
  // because at that point it is somebody's child and has to read as one.
  nested: { type: Boolean, default: false },
});

const {
  expandedItem,
  setExpandedItem,
  resolvePath,
  resolvePermissions,
  resolveFeatureFlag,
  isAllowed,
  isCollapsed,
  isResizing,
} = useSidebarContext();

const {
  activePopover,
  setActivePopover,
  closeActivePopover,
  scheduleClose,
  cancelClose,
} = usePopoverState();

// What a sub-item looks like: the indent, and the colours the tree rail paints
// itself with. Copied off SidebarGroupLeaf on purpose — a section's items and a
// group's leaves are the same idea at two depths, so they read from the same
// token and land on the same vertical line.
const SUB_ITEM_CLASS =
  'sidebar-section-item relative ltr:ml-3 rtl:mr-3 ltr:pl-2 rtl:pr-2 before:bg-n-slate-4 after:bg-transparent after:border-n-slate-4 before:left-0 rtl:before:right-0';

// The rail is 56px of icons with no section heading on screen: there is nothing
// left to be a child OF, and an indent would only shove the icons off centre.
const subItemClass = computed(() =>
  props.nested && !isCollapsed.value ? SUB_ITEM_CLASS : ''
);

const navigableChildren = computed(() => {
  return props.children?.flatMap(child => child.children || child) || [];
});

const route = useRoute();
const router = useRouter();
const isExpanded = computed(() => expandedItem.value === props.name);
const isExpandable = computed(() => props.children);
const hasChildren = computed(
  () => Array.isArray(props.children) && props.children.length > 0
);

// Use shared popover state - only one popover can be open at a time
const isPopoverOpen = computed(() => activePopover.value === props.name);
const triggerRef = ref(null);
const triggerRect = ref({ top: 0, left: 0, bottom: 0, right: 0 });

const openPopover = () => {
  if (triggerRef.value) {
    const rect = triggerRef.value.getBoundingClientRect();
    triggerRect.value = {
      top: rect.top,
      left: rect.left,
      bottom: rect.bottom,
      right: rect.right,
    };
  }
  setActivePopover(props.name);
};

const closePopover = () => {
  if (activePopover.value === props.name) {
    closeActivePopover();
  }
};

const handleMouseEnter = () => {
  if (!hasChildren.value || isResizing.value) return;
  cancelClose();
  openPopover();
};

const handleMouseLeave = () => {
  if (!hasChildren.value) return;
  scheduleClose(200);
};

const handlePopoverMouseEnter = () => {
  cancelClose();
};

const handlePopoverMouseLeave = () => {
  scheduleClose(100);
};

// Close popover when mouse leaves the window
const handleWindowBlur = () => {
  closeActivePopover();
};

const accessibleItems = computed(() => {
  if (!hasChildren.value) return [];
  return props.children.filter(child => {
    // If a item has no link, it means it's just a subgroup header
    // So we don't need to check for permissions here, because there's nothing to
    // access here anyway
    return child.to && isAllowed(child.to);
  });
});

const hasAccessibleChildren = computed(() => {
  return accessibleItems.value.length > 0;
});

const isActive = computed(() => {
  if (props.to) {
    if (route.path === resolvePath(props.to)) return true;

    return props.activeOn.includes(route.name);
  }

  return false;
});

// We could use the RouterLink isActive too, but our routes are not always
// nested correctly, so we need to check the active state ourselves
// TODO: Audit the routes and fix the nesting and remove this
const activeChild = computed(() => {
  const pathSame = navigableChildren.value.find(
    child => child.to && route.path === resolvePath(child.to)
  );
  if (pathSame) return pathSame;

  // Rank the activeOn Prop higher than the path match
  // There will be cases where the path name is the same but the params are different
  // So we need to rank them based on the params
  // For example, contacts segment list in the sidebar effectively has the same name
  // But the params are different
  const activeOnPages = navigableChildren.value.filter(child =>
    child.activeOn?.includes(route.name)
  );

  if (activeOnPages.length > 0) {
    const rankedPage = activeOnPages.find(child => {
      return Object.keys(child.to.params)
        .map(key => {
          return String(child.to.params[key]) === String(route.params[key]);
        })
        .every(match => match);
    });

    // If there is no ranked page, return the first activeOn page anyway
    // Since this takes higher precedence over the path match
    // This is not perfect, ideally we should rank each route based on all the techniques
    // and then return the highest ranked one
    // But this is good enough for now
    return rankedPage ?? activeOnPages[0];
  }

  return navigableChildren.value.find(child => {
    if (!child.to) return false;
    const childPath = resolvePath(child.to);
    return route.path === childPath || route.path.startsWith(`${childPath}/`);
  });
});

const hasActiveChild = computed(() => {
  return activeChild.value !== undefined;
});

const handleCollapsedClick = () => {
  if (hasChildren.value && hasAccessibleChildren.value) {
    const firstItem = accessibleItems.value[0];
    router.push(firstItem.to);
  }
};

const toggleTrigger = () => {
  if (
    hasAccessibleChildren.value &&
    !isExpanded.value &&
    !hasActiveChild.value
  ) {
    // if not already expanded, navigate to the first child
    const firstItem = accessibleItems.value[0];
    router.push(firstItem.to);
  }
  setExpandedItem(props.name);
};

onMounted(async () => {
  await nextTick();
  if (hasActiveChild.value) {
    setExpandedItem(props.name);
  }
  window.addEventListener('blur', handleWindowBlur);
  document.addEventListener('mouseleave', handleWindowBlur);
});

onUnmounted(() => {
  window.removeEventListener('blur', handleWindowBlur);
  document.removeEventListener('mouseleave', handleWindowBlur);
});

watch(
  hasActiveChild,
  hasNewActiveChild => {
    if (hasNewActiveChild && !isExpanded.value) {
      setExpandedItem(props.name);
    }
  },
  { once: true }
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Policy
    v-if="!hasChildren || hasAccessibleChildren"
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    class="grid gap-1 text-sm cursor-pointer select-none min-w-0"
    :class="subItemClass"
  >
    <!-- Collapsed State -->
    <template v-if="isCollapsed">
      <div
        class="relative"
        @mouseenter="handleMouseEnter"
        @mouseleave="handleMouseLeave"
      >
        <component
          :is="href ? 'a' : to && !hasChildren ? 'router-link' : 'button'"
          ref="triggerRef"
          :to="!href && to && !hasChildren ? to : undefined"
          :href="href || undefined"
          :target="href ? '_blank' : undefined"
          :rel="href ? 'noopener noreferrer' : undefined"
          type="button"
          class="flex items-center justify-center size-10 rounded-lg"
          :class="{
            'text-n-slate-12 bg-n-alpha-2': isActive || hasActiveChild,
            'text-n-slate-11 hover:bg-n-alpha-2': !isActive && !hasActiveChild,
          }"
          :title="label"
          :data-onboarding="dataOnboarding || undefined"
          @click="hasChildren ? handleCollapsedClick() : undefined"
        >
          <Icon v-if="icon" :icon="icon" class="size-4" />
        </component>
        <SidebarCollapsedPopover
          v-if="hasChildren && isPopoverOpen"
          :label="label"
          :children="children"
          :active-child="activeChild"
          :trigger-rect="triggerRect"
          @close="closePopover"
          @mouseenter="handlePopoverMouseEnter"
          @mouseleave="handlePopoverMouseLeave"
        />
      </div>
    </template>
    <!-- Expanded State -->
    <template v-else>
      <SidebarGroupHeader
        :icon
        :name
        :label
        :to
        :href
        :getter-keys="getterKeys"
        :is-active="isActive"
        :has-active-child="hasActiveChild"
        :expandable="hasChildren"
        :is-expanded="isExpanded"
        :data-onboarding="dataOnboarding || undefined"
        @toggle="toggleTrigger"
      />
      <ul
        v-if="hasChildren"
        v-show="isExpanded || hasActiveChild"
        class="grid m-0 list-none sidebar-group-children min-w-0"
      >
        <template v-for="child in children" :key="child.name">
          <SidebarSubGroup
            v-if="child.children"
            :label="child.label"
            :icon="child.icon"
            :children="child.children"
            :is-expanded="isExpanded"
            :active-child="activeChild"
          />
          <SidebarGroupLeaf
            v-else-if="isAllowed(child.to)"
            v-show="isExpanded || activeChild?.name === child.name"
            v-bind="child"
            :active="activeChild?.name === child.name"
          />
        </template>
      </ul>
      <ul v-else-if="isExpandable && isExpanded">
        <SidebarGroupEmptyLeaf />
      </ul>
    </template>
  </Policy>
</template>

<style>
/*
 * The tree rail. A nested row draws a hairline down its left edge and the last
 * one stops short and turns right, so a block of children reads as a branch of
 * the row above it instead of a flat list stuck to the margin.
 *
 * Two things wear it: the leaves of a native group, and the items of a section
 * a super admin created. Same weight, same radius, same colour — the colour
 * itself never appears here, it comes from the before:/after: utilities on the
 * element, so the token stays stated in exactly one place.
 */
.sidebar-group-children .child-item::before,
.sidebar-section-children > .sidebar-section-item::before {
  content: '';
  position: absolute;
  width: 0.125rem;
  /* 0.5px */
  height: 100%;
}

.sidebar-group-children .child-item:first-child::before,
.sidebar-section-children > .sidebar-section-item:first-child::before {
  border-radius: 4px 4px 0 0;
}

/* This selects the last child in a group */
/* https://codepen.io/scmmishra/pen/yLmKNLW */
.sidebar-group-children > .child-item:last-child::before,
.sidebar-group-children
  > *:last-child
  > *:last-child
  > .child-item:last-child::before {
  height: 20%;
}

.sidebar-group-children > .child-item:last-child::after,
.sidebar-group-children
  > *:last-child
  > *:last-child
  > .child-item:last-child::after,
.sidebar-section-children > .sidebar-section-item:last-child::after {
  content: '';
  position: absolute;
  width: 10px;
  height: 12px;
  bottom: calc(50% - 2px);
  border-bottom-width: 0.125rem;
  border-left-width: 0.125rem;
  border-right-width: 0px;
  border-top-width: 0px;
  border-radius: 0 0 0 4px;
  left: 0;
}

#app[dir='rtl'] .sidebar-group-children > .child-item:last-child::after,
#app[dir='rtl']
  .sidebar-group-children
  > *:last-child
  > *:last-child
  > .child-item:last-child::after,
#app[dir='rtl']
  .sidebar-section-children
  > .sidebar-section-item:last-child::after {
  right: 0;
  border-bottom-width: 0.125rem;
  border-right-width: 0.125rem;
  border-left-width: 0px;
  border-top-width: 0px;
  border-radius: 0 0 4px 0px;
}

/*
 * A leaf is one row, so its rail can just be 100% of itself. An item of a
 * section is a whole group — a header row plus, once it is open, its own
 * children carrying their own rail one level deeper — so the rail has to be
 * measured off the HEADER instead. Left at 100% the elbow would slide to the
 * foot of the subtree and point at a grandchild rather than at the item.
 *
 * The 0.25rem is the gap the section's list puts between items; the rail
 * crosses it so it reads as one line and not a dashed one.
 */
.sidebar-section-children > .sidebar-section-item::before {
  top: 0;
  height: calc(100% + 0.25rem);
}

.sidebar-section-children > .sidebar-section-item:last-child::before {
  height: 0.5rem;
}

/* The header row is 2rem, so 0.25rem down lands the elbow's floor on its
   middle, wherever the item's own children end up. */
.sidebar-section-children > .sidebar-section-item:last-child::after {
  top: 0.25rem;
  bottom: auto;
}
</style>

import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import SidebarGroup from '../SidebarGroup.vue';
import SidebarGroupLeaf from '../SidebarGroupLeaf.vue';

const isCollapsed = ref(false);

vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/nowhere', name: 'nowhere', params: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('../provider', () => ({
  useSidebarContext: () => ({
    expandedItem: ref(null),
    setExpandedItem: vi.fn(),
    resolvePath: () => '/nowhere',
    resolvePermissions: () => [],
    resolveFeatureFlag: () => '',
    isAllowed: () => true,
    isCollapsed,
    isResizing: ref(false),
  }),
  usePopoverState: () => ({
    activePopover: ref(null),
    setActivePopover: vi.fn(),
    closeActivePopover: vi.fn(),
    scheduleClose: vi.fn(),
    cancelClose: vi.fn(),
  }),
}));

const mountGroup = (props = {}) =>
  shallowMount(SidebarGroup, {
    props: { name: 'Kanban', label: 'Kanban', ...props },
  });

// The rail is drawn by ::before/::after, which no test renderer computes. What
// a test CAN pin down is the contract those pseudo-elements read from: the
// hook class, the indent, and the token the line is painted with.
const RAIL = [
  'sidebar-section-item',
  'relative',
  'before:bg-n-slate-4',
  'after:bg-transparent',
  'after:border-n-slate-4',
  'before:left-0',
  'rtl:before:right-0',
];

const INDENT = ['ltr:ml-3', 'rtl:mr-3', 'ltr:pl-2', 'rtl:pr-2'];

describe('SidebarGroup', () => {
  beforeEach(() => {
    isCollapsed.value = false;
  });

  it('leaves a top level group flat against the margin', () => {
    const classes = mountGroup().classes();

    [...RAIL, ...INDENT].forEach(name => {
      expect(classes).not.toContain(name);
    });
  });

  // An item of a section is a whole group, not a leaf, so nothing was giving it
  // the sub-item treatment: it came out flush left and read as a sibling of the
  // heading above it rather than as something inside it.
  describe('when a section is holding it', () => {
    it('takes the indent and the tree rail', () => {
      const classes = mountGroup({ nested: true }).classes();

      [...RAIL, ...INDENT].forEach(name => {
        expect(classes).toContain(name);
      });
    });

    // Same line, same weight, same colour as a native group's children. If the
    // leaf ever moves off n-slate-4 this fails instead of quietly drifting.
    it('sits on the same line and the same token as a native leaf', () => {
      const leaf = shallowMount(SidebarGroupLeaf, {
        props: { label: 'Todas', to: { name: 'nowhere' } },
        global: { components: { RouterLink: { template: '<a><slot /></a>' } } },
      }).classes();
      const item = mountGroup({ nested: true }).classes();

      const rail = leaf.filter(
        name => name.includes('before:') || name.includes('after:')
      );

      expect(rail.length).toBeGreaterThan(0);
      rail.forEach(name => expect(item).toContain(name));
      INDENT.forEach(name => {
        expect(leaf).toContain(name);
        expect(item).toContain(name);
      });
    });

    // At 56px the heading is gone, so there is nothing left to be a child of.
    // An indent there would only push the icons off the centre of the rail.
    it('drops all of it in the rail', () => {
      isCollapsed.value = true;

      const classes = mountGroup({ nested: true }).classes();

      [...RAIL, ...INDENT].forEach(name => {
        expect(classes).not.toContain(name);
      });
    });
  });
});

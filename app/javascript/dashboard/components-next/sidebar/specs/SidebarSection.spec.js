import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import SidebarSection from '../SidebarSection.vue';

const isCollapsed = ref(false);
const uiSettings = ref({});
const updateUISettings = vi.fn(next => {
  uiSettings.value = { ...uiSettings.value, ...next };
});

vi.mock('../provider', () => ({
  useSidebarContext: () => ({ isCollapsed }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings }),
}));

// The point of this component is WHICH component draws the items, so the stub
// has to be identifiable: an item rendered by anything other than SidebarGroup
// would have lost the three levels this exists to protect.
const stubs = {
  // Typed like the real one on purpose: `nested` is passed as a bare attribute,
  // and only a Boolean prop turns that into true rather than an empty string.
  SidebarGroup: {
    props: {
      name: String,
      label: String,
      icon: [String, Object, Function],
      children: Array,
      nested: { type: Boolean, default: false },
    },
    template:
      '<li class="group-stub" :data-nested="String(nested)">{{ label }}</li>',
  },
  Icon: true,
};

const items = [
  { name: 'Conversation', label: 'Conversas', children: [{ name: 'All' }] },
  { name: 'Kanban', label: 'Kanban' },
];

const mountSection = (props = {}) =>
  mount(SidebarSection, {
    props: { name: 'g_1', label: 'Atendimento', items, ...props },
    global: { stubs },
  });

describe('SidebarSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isCollapsed.value = false;
    uiSettings.value = {};
  });

  // A section WRAPS its items instead of parenting them. Nesting SidebarGroup
  // inside SidebarGroup spends a render level that Conversas has already spent
  // on Canais, and the inboxes fall off the end — which is exactly how the live
  // menu was taken apart once.
  it('hands every item to SidebarGroup, native groups included', () => {
    const rendered = mountSection().findAll('.group-stub');

    expect(rendered.map(node => node.text())).toEqual(['Conversas', 'Kanban']);
  });

  // The items were coming out flush against the margin, so a section read as a
  // heading with a flat list beside it rather than a drawer with things inside.
  // The tree hangs off these two: the list is what the rail is scoped to, and
  // every item has to know it is somebody's child.
  it('hangs its items off the tree, like a native group does', () => {
    const wrapper = mountSection();

    expect(wrapper.find('ul').classes()).toContain('sidebar-section-children');
    expect(
      wrapper.findAll('.group-stub').map(node => node.attributes('data-nested'))
    ).toEqual(['true', 'true']);
  });

  it('shows the heading it was given', () => {
    const header = mountSection().find('button');

    expect(header.text()).toContain('Atendimento');
    expect(header.attributes('title')).toBe('Atendimento');
  });

  it('opens by default', () => {
    expect(mountSection().find('ul').isVisible()).toBe(true);
  });

  it('closes when the heading is clicked, and remembers it', async () => {
    const wrapper = mountSection();

    await wrapper.find('button').trigger('click');

    expect(updateUISettings).toHaveBeenCalledWith({
      sidebar_closed_sections: ['g_1'],
    });
    expect(wrapper.find('ul').isVisible()).toBe(false);
  });

  it('starts closed when this person had closed it', () => {
    uiSettings.value = { sidebar_closed_sections: ['g_1'] };

    expect(mountSection().find('ul').isVisible()).toBe(false);
  });

  it('reopens without disturbing the other sections', async () => {
    uiSettings.value = { sidebar_closed_sections: ['g_0', 'g_1'] };
    const wrapper = mountSection();

    await wrapper.find('button').trigger('click');

    expect(updateUISettings).toHaveBeenCalledWith({
      sidebar_closed_sections: ['g_0'],
    });
  });

  // Sections are defined per installation and stored as the CLOSED ones, so a
  // section created after somebody last touched their settings arrives open
  // rather than hidden from them forever.
  it('opens a section this person has never seen', () => {
    uiSettings.value = { sidebar_closed_sections: ['g_other'] };

    expect(mountSection().find('ul').isVisible()).toBe(true);
  });

  // The rail is 56px wide: a heading has nowhere to render and nothing to
  // collapse into, so the icons have to stand on their own.
  describe('when the sidebar is a rail', () => {
    beforeEach(() => {
      isCollapsed.value = true;
    });

    it('drops the heading', () => {
      expect(mountSection().find('button').exists()).toBe(false);
    });

    // No heading on screen means nothing left to be a child of, and an indent
    // would only shove the icons off the centre of the 56px column.
    it('drops the tree and centres the icons', () => {
      const list = mountSection().find('ul');

      expect(list.classes()).toContain('items-center');
      expect(list.classes()).not.toContain('sidebar-section-children');
    });

    it('shows the items anyway, even one that was closed', () => {
      uiSettings.value = { sidebar_closed_sections: ['g_1'] };
      const wrapper = mountSection();

      expect(wrapper.find('ul').isVisible()).toBe(true);
      expect(wrapper.findAll('.group-stub')).toHaveLength(2);
    });
  });
});

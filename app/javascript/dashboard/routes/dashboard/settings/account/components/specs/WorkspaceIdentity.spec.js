import { computed, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import WorkspaceIdentity from '../WorkspaceIdentity.vue';
import WorkspaceAPI from 'dashboard/api/workspace';

const account = ref({});
const commit = vi.fn();
const dispatch = vi.fn();

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: computed(() => account.value) }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ commit, dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/workspace', () => ({
  default: { get: vi.fn(), update: vi.fn(), removeAttachment: vi.fn() },
}));

const mountIdentity = async () => {
  const wrapper = mount(WorkspaceIdentity);
  await flushPromises();
  return wrapper;
};

describe('WorkspaceIdentity', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    account.value = {
      id: 5,
      name: 'BEAUTY CENTER BH LOURDES',
      settings: { cover_theme: 'sunset' },
      cover_url: '',
      logo_url: '',
      vertical: 'beauty_salon',
    };
    WorkspaceAPI.get.mockResolvedValue({
      data: {
        vertical: 'beauty_salon',
        verticals: [
          { key: 'beauty_salon', name: 'Salão de beleza' },
          { key: 'ecommerce', name: 'E-commerce' },
        ],
      },
    });
    WorkspaceAPI.update.mockResolvedValue({ data: { id: 5 } });
  });

  it('previews the workspace with its vertical and marks the chosen theme', async () => {
    const wrapper = await mountIdentity();

    expect(wrapper.text()).toContain('BEAUTY CENTER BH LOURDES');
    expect(wrapper.text()).toContain('Salão de beleza');
    expect(
      wrapper.find('button[aria-label="Sunset"]').attributes('aria-pressed')
    ).toBe('true');
    expect(wrapper.text()).toContain('In use');
  });

  it('saves a new theme and refreshes the account and the switcher', async () => {
    const wrapper = await mountIdentity();

    await wrapper.find('button[aria-label="Ocean"]').trigger('click');
    await flushPromises();

    expect(WorkspaceAPI.update).toHaveBeenCalledWith({ cover_theme: 'ocean' });
    expect(commit).toHaveBeenCalledWith('accounts/EDIT_ACCOUNT', { id: 5 });
    expect(dispatch).toHaveBeenCalledWith('validityCheck');
  });

  it('goes back to the automatic cover', async () => {
    const wrapper = await mountIdentity();

    await wrapper.find('button[aria-pressed="false"]').trigger('click');
    await flushPromises();

    expect(WorkspaceAPI.update).toHaveBeenCalledWith({ cover_theme: '' });
  });

  it('uploads the cover image as multipart', async () => {
    const wrapper = await mountIdentity();
    const input = wrapper.findAll('input[type="file"]')[0];
    const file = new File(['x'], 'capa.png', { type: 'image/png' });
    Object.defineProperty(input.element, 'files', { value: [file] });

    await input.trigger('change');
    await flushPromises();

    const [formData] = WorkspaceAPI.update.mock.calls[0];
    expect(formData.get('cover')).toBe(file);
  });

  it('applies another vertical after the admin picks it', async () => {
    const wrapper = await mountIdentity();

    await wrapper.find('select').setValue('ecommerce');
    expect(wrapper.text()).toContain('Applying “E-commerce”');

    const applyButton = wrapper
      .findAll('button')
      .find(button => button.attributes('icon') === 'i-lucide-wand-sparkles');
    await applyButton.trigger('click');
    await flushPromises();

    expect(WorkspaceAPI.update).toHaveBeenCalledWith({ vertical: 'ecommerce' });
  });
});

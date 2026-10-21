import { mount, flushPromises } from '@vue/test-utils';
import CampaignFolders from '../CampaignFolders.vue';

const folders = vi.fn();
const createFolder = vi.fn();
const removeFolder = vi.fn();

vi.mock('dashboard/api/whatsappStatusCampaigns', () => ({
  default: {
    folders: (...a) => folders(...a),
    createFolder: (...a) => createFolder(...a),
    updateFolder: vi.fn(),
    removeFolder: (...a) => removeFolder(...a),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
};

describe('CampaignFolders.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    folders.mockResolvedValue({
      data: {
        payload: [
          { id: 3, name: 'Promoções', color: '#B03A2E', campaigns_count: 2 },
        ],
        meta: { unfiled_count: 1, total_count: 3 },
      },
    });
  });

  it('lists all, unfiled and each folder with its count', async () => {
    const wrapper = mount(CampaignFolders, { global: { stubs } });
    await flushPromises();

    expect(wrapper.find('[data-testid="folder-all"]').text()).toContain('3');
    expect(wrapper.find('[data-testid="folder-none"]').text()).toContain('1');
    expect(wrapper.find('[data-testid="folder-item"]').text()).toContain(
      'Promoções'
    );

    await wrapper.find('[data-testid="folder-item"] button').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([3]);
  });

  // Criar pasta é escrever o nome e dar Enter, sem modal.
  it('creates a folder in place and selects it', async () => {
    createFolder.mockResolvedValue({ data: { id: 9 } });
    const wrapper = mount(CampaignFolders, { global: { stubs } });
    await flushPromises();

    await wrapper.find('[data-testid="folder-new"]').trigger('click');
    await wrapper.find('[data-testid="folder-name"]').setValue('Feriados');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(createFolder).toHaveBeenCalledWith({
      name: 'Feriados',
      color: expect.any(String),
    });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([9]);
  });
});

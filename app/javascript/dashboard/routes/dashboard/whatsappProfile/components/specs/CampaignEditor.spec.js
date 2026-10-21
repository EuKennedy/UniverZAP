import { mount, flushPromises } from '@vue/test-utils';
import CampaignEditor from '../CampaignEditor.vue';

const save = vi.fn();
const activate = vi.fn();
const preview = vi.fn();
const find = vi.fn();

vi.mock('dashboard/api/whatsappStatusCampaigns', () => ({
  default: {
    save: (...a) => save(...a),
    activate: (...a) => activate(...a),
    pause: vi.fn(),
    remove: vi.fn(),
    preview: (...a) => preview(...a),
    find: (...a) => find(...a),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stepFormOpen = vi.fn();

const stubs = {
  Button: {
    props: ['label'],
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Input: {
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template:
      '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
  Select: true,
  Checkbox: true,
  StatusPreview: true,
  // O diálogo do passo tem spec próprio; aqui interessa o contrato.
  CampaignStepForm: {
    emits: ['save'],
    methods: {
      open(...args) {
        stepFormOpen(...args);
      },
    },
    template: '<div data-testid="step-form" />',
  },
};

const INBOXES = [{ id: 5, name: 'Loja' }];

const apiCampaign = overrides => ({
  id: 7,
  name: 'Semana da escova',
  status: 'draft',
  inbox_ids: [5],
  starts_on: '2099-01-05',
  cycle_days: 7,
  time_zone: 'America/Sao_Paulo',
  steps: [
    {
      id: 1,
      kind: 'text',
      body: 'Última chamada',
      day_offset: 2,
      time_of_day: '18:00',
      repost_count: 0,
      repost_interval_hours: 24,
    },
    {
      id: 2,
      kind: 'text',
      body: 'Agenda aberta',
      day_offset: 0,
      time_of_day: '09:00',
      repost_count: 2,
      repost_interval_hours: 24,
    },
  ],
  ...overrides,
});

const mountEditor = props =>
  mount(CampaignEditor, {
    props: { inboxes: INBOXES, folders: [], ...props },
    global: { stubs },
  });

describe('CampaignEditor.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    preview.mockResolvedValue({
      data: {
        payload: [
          {
            at: '2099-01-05T12:00:00Z',
            step_id: 2,
            body: 'Agenda aberta',
            repost: 0,
          },
        ],
      },
    });
  });

  // A linha do tempo segue a ordem de saída, não a de criação.
  it('shows the flow in the order it goes out, with the reposts', async () => {
    find.mockResolvedValue({ data: apiCampaign() });
    const wrapper = mountEditor({ campaignId: 7 });
    await flushPromises();

    const steps = wrapper
      .findAll('[data-testid="flow-step"]')
      .map(node => node.text());
    expect(steps[0]).toContain('Agenda aberta');
    expect(steps[1]).toContain('Última chamada');
    expect(wrapper.findAll('[data-testid="step-repost-info"]')).toHaveLength(1);
    expect(wrapper.findAll('[data-testid="preview-item"]')).toHaveLength(1);
  });

  it('refuses to save without a name', async () => {
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper.find('[data-testid="editor-save"]').trigger('click');

    expect(save).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="editor-error"]').text()).toBe(
      'WHATSAPP_PROFILE.CAMPAIGNS.EDITOR.NAME_REQUIRED'
    );
  });

  // Ativar salva antes, para ninguém precisar de dois cliques.
  it('saves the steps and activates in one click', async () => {
    save.mockResolvedValue({ data: apiCampaign() });
    activate.mockResolvedValue({ data: apiCampaign({ status: 'active' }) });
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper
      .find('[data-testid="editor-name"]')
      .setValue('Semana da escova');
    wrapper.findComponent(stubs.CampaignStepForm).vm.$emit(
      'save',
      {
        kind: 'text',
        body: 'Agenda aberta',
        dayOffset: 0,
        timeOfDay: '09:00',
        repostCount: 1,
        repostIntervalHours: 24,
      },
      null
    );
    await wrapper.find('[data-testid="editor-activate"]').trigger('click');
    await flushPromises();

    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Semana da escova',
        inboxIds: [5],
        steps: [
          expect.objectContaining({ body: 'Agenda aberta', repostCount: 1 }),
        ],
      })
    );
    expect(activate).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="editor-pause"]').exists()).toBe(true);
  });

  it('opens the step form to add and to edit', async () => {
    find.mockResolvedValue({ data: apiCampaign() });
    const wrapper = mountEditor({ campaignId: 7 });
    await flushPromises();

    await wrapper.find('[data-testid="add-step"]').trigger('click');
    expect(stepFormOpen).toHaveBeenLastCalledWith(null, null);

    await wrapper.find('[data-testid="step-edit"]').trigger('click');
    expect(stepFormOpen).toHaveBeenLastCalledWith(
      expect.objectContaining({ body: 'Agenda aberta' }),
      1
    );
  });
});

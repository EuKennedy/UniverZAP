import { mount, flushPromises } from '@vue/test-utils';
import WhatsAppStatusHistory from '../WhatsAppStatusHistory.vue';

const list = vi.fn();
const retry = vi.fn();
const remove = vi.fn();
const publishNow = vi.fn();
const duplicate = vi.fn();

vi.mock('dashboard/api/whatsappStatus', () => ({
  default: {
    list: (...a) => list(...a),
    retry: (...a) => retry(...a),
    remove: (...a) => remove(...a),
    publishNow: (...a) => publishNow(...a),
    duplicate: (...a) => duplicate(...a),
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
  Spinner: true,
  StatusPreview: true,
  StatusAgenda: {
    template: '<div data-testid="agenda-stub" />',
  },
  Dialog: {
    emits: ['confirm'],
    data: () => ({ isOpen: false }),
    methods: {
      open() {
        this.isOpen = true;
      },
      close() {
        this.isOpen = false;
      },
    },
    template:
      '<div v-if="isOpen" data-testid="confirm-dialog"><slot />' +
      '<button data-testid="confirm-publish" @click="$emit(\'confirm\')">confirm</button></div>',
  },
};

const post = attrs => ({
  id: 1,
  kind: 'text',
  body: 'Agenda aberta',
  font: 0,
  status: 'published',
  created_at: '2026-10-20T12:00:00Z',
  published_at: '2026-10-20T12:00:05Z',
  deliveries: [],
  ...attrs,
});

const mountHistory = () => mount(WhatsAppStatusHistory, { global: { stubs } });

describe('WhatsAppStatusHistory.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // Publicar em várias conexões pode falhar em uma só, e é ela que o operador
  // precisa ver para reenviar.
  it('shows the result and the WhatsApp error on each connection', async () => {
    list.mockResolvedValue({
      data: {
        payload: [
          post({
            status: 'partially_published',
            deliveries: [
              { id: 1, inbox_name: 'Loja', status: 'sent' },
              {
                id: 2,
                inbox_name: 'Filial',
                status: 'failed',
                error_message: 'session status is not WORKING',
              },
            ],
          }),
        ],
        meta: { has_more: false },
      },
    });

    const wrapper = mountHistory();
    await flushPromises();

    expect(wrapper.find('[data-testid="history-status"]').text()).toBe(
      'WHATSAPP_PROFILE.HISTORY.STATUS.PARTIALLY_PUBLISHED'
    );
    const deliveries = wrapper
      .findAll('[data-testid="history-delivery"]')
      .map(n => n.text());
    expect(deliveries[1]).toContain('session status is not WORKING');
  });

  it('retries only from a status with failures', async () => {
    list.mockResolvedValue({
      data: {
        payload: [
          post({
            id: 3,
            status: 'failed',
            deliveries: [{ id: 9, inbox_name: 'Loja', status: 'failed' }],
          }),
          post({ id: 4 }),
        ],
        meta: {},
      },
    });
    retry.mockResolvedValue({});

    const wrapper = mountHistory();
    await flushPromises();
    const buttons = wrapper.findAll('[data-testid="history-retry"]');
    expect(buttons).toHaveLength(1);

    await buttons[0].trigger('click');
    await flushPromises();
    expect(retry).toHaveBeenCalledWith(3);
  });

  it('asks before posting a draft from the history', async () => {
    list.mockResolvedValue({
      data: { payload: [post({ id: 6, status: 'draft' })], meta: {} },
    });
    publishNow.mockResolvedValue({});

    const wrapper = mountHistory();
    await flushPromises();
    await wrapper.find('[data-testid="history-publish"]').trigger('click');
    expect(publishNow).not.toHaveBeenCalled();

    await wrapper.find('[data-testid="confirm-publish"]').trigger('click');
    await flushPromises();
    expect(publishNow).toHaveBeenCalledWith(6);
  });

  // A busca e os filtros vão para o servidor: valem para o histórico inteiro,
  // e não só para a página que está aberta.
  it('sends search and filters to the server and starts again on page 1', async () => {
    vi.useFakeTimers();
    list.mockResolvedValue({
      data: { payload: [post()], meta: { total_count: 25, total_pages: 3 } },
    });

    const wrapper = mountHistory();
    await flushPromises();
    await wrapper.find('[data-testid="page-2"]').trigger('click');
    await flushPromises();
    expect(list).toHaveBeenLastCalledWith(expect.objectContaining({ page: 2 }));

    await wrapper
      .find('[data-testid="filter-status"] select')
      .setValue('failed');
    await flushPromises();
    expect(list).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 1, status: 'failed' })
    );

    await wrapper.find('[data-testid="history-search"]').setValue('terça');
    await vi.advanceTimersByTimeAsync(350);
    await flushPromises();
    expect(list).toHaveBeenLastCalledWith(
      expect.objectContaining({ q: 'terça', status: 'failed' })
    );
    vi.useRealTimers();
  });

  it('offers to clear the filters when nothing matches', async () => {
    list.mockResolvedValue({ data: { payload: [], meta: { total_count: 0 } } });

    const wrapper = mountHistory();
    await flushPromises();
    expect(wrapper.find('[data-testid="create-first"]').exists()).toBe(true);

    await wrapper.find('[data-testid="filter-kind"] select').setValue('video');
    await flushPromises();
    expect(wrapper.find('[data-testid="create-first"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="history-empty"]').text()).toContain(
      'WHATSAPP_PROFILE.HISTORY.EMPTY_FILTERED'
    );
  });

  // Duplicar já abre a cópia no compositor para ajustar antes de mandar.
  it('duplicates any status and opens the copy for editing', async () => {
    list.mockResolvedValue({ data: { payload: [post({ id: 3 })], meta: {} } });
    duplicate.mockResolvedValue({ data: { id: 30, status: 'draft' } });

    const wrapper = mountHistory();
    await flushPromises();
    await wrapper.find('[data-testid="history-duplicate"]').trigger('click');
    await flushPromises();

    expect(duplicate).toHaveBeenCalledWith(3);
    expect(wrapper.emitted('edit')[0][0]).toEqual({ id: 30, status: 'draft' });
    expect(wrapper.emitted('changed')).toBeTruthy();
  });

  it('switches to the week view', async () => {
    list.mockResolvedValue({ data: { payload: [post()], meta: {} } });

    const wrapper = mountHistory();
    await flushPromises();
    await wrapper.find('[data-testid="view-agenda"]').trigger('click');

    expect(wrapper.find('[data-testid="agenda-stub"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="history-toolbar"]').exists()).toBe(
      false
    );
  });

  // Enquanto algo está saindo, a tela tem que mostrar quando terminar sem o
  // operador recarregar.
  it('keeps refreshing while a status is being posted', async () => {
    vi.useFakeTimers();
    list.mockResolvedValueOnce({
      data: { payload: [post({ status: 'publishing' })], meta: {} },
    });
    list.mockResolvedValue({ data: { payload: [post()], meta: {} } });

    mountHistory();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();

    expect(list).toHaveBeenCalledTimes(2);
    vi.useRealTimers();
  });
});

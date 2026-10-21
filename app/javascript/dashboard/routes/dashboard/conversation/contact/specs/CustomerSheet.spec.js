import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CustomerSheet from '../CustomerSheet.vue';
import ScheduleDialog from '../ScheduleDialog.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: {
    pt_BR: {
      CONTACT_PANEL: {
        COPY_SUCCESSFUL: 'Copiado',
        CLICK_TO_EDIT: 'Clique para editar',
        SHEET: {
          NO_PHONE: 'sem número',
          COPY_PHONE: 'Copiar número',
          STAGE: 'Estágio',
          ORIGIN: 'Origem',
          ORIGIN_AD: 'Anúncio',
          ORIGIN_ORGANIC: 'Orgânico',
          TYPE: 'Tipo',
          TYPE_NEW: 'Nova',
          TYPE_RECURRING: 'Recorrente',
          SERVICE: 'Serviço',
          PROFESSIONAL: 'Profissional',
          APPOINTMENT: 'Agendamento',
          REPURCHASE: 'Recompra',
          REPURCHASE_EVERY: 'a cada {count} semana | a cada {count} semanas',
          EMPTY: '—',
          SAVE: 'Salvar',
          SCHEDULE: {
            BUTTON: 'Agendar',
            TITLE: 'Agendar atendimento',
            DESCRIPTION: 'Grava e muda o estágio.',
            DATE: 'Data e hora',
            SERVICE_PLACEHOLDER: 'Escolha o serviço',
            REPURCHASE_WEEKS: 'Recompra (semanas)',
            CONFIRM: 'Agendar',
          },
        },
      },
    },
  },
});

const stages = [
  { title: 'novo-contato', color: '#94A3B8', closes_conversation: false },
  { title: 'agendado', color: '#14B8A6', closes_conversation: false },
  { title: 'cancelado', color: '#EF4444', closes_conversation: true },
];

const attributeDefinitions = [
  {
    attribute_key: 'servico',
    attribute_display_type: 'list',
    attribute_values: ['Corte', 'Coloração'],
  },
];

// Stored values are ISO 8601 (UTC); the sheet shows them in the agent's zone,
// so the fixtures are built from local Dates to hold in any TZ.
const appointmentAt = new Date(2026, 9, 25, 14, 0).toISOString();
const rescheduledAt = new Date(2026, 9, 26, 9, 30).toISOString();

const mountSheet = (props = {}) =>
  mount(CustomerSheet, {
    props: { stages, attributeDefinitions, ...props },
    global: {
      plugins: [i18n],
      stubs: {
        ScheduleDialog: true,
        ScheduleMessageDialog: true,
        NextButton: { template: '<button><slot/></button>' },
      },
    },
  });

describe('CustomerSheet', () => {
  it('shows the formatted WhatsApp number, stage with its color, ad origin and recurring type', () => {
    const wrapper = mountSheet({
      contact: { id: 1, phone_number: '+5531999998888', custom_attributes: {} },
      conversation: {
        id: 10,
        labels: ['lead-anuncio', 'agendado'],
        custom_attributes: {
          origem_lead: 'anuncio_facebook',
          anuncio_titulo: 'Corte masculino sem fila',
          anuncio_url: 'https://fb.me/corte',
          servico: 'Corte',
          profissional: 'Ana',
          data_agendamento: appointmentAt,
          ciclo_recompra_semanas: 4,
        },
      },
      previousConversations: [{ id: 9, status: 'resolved' }],
    });

    expect(wrapper.find('[data-testid="sheet-phone"]').text()).toContain(
      '+55 31 99999 8888'
    );

    const stage = wrapper.find('[data-testid="sheet-row-stage"]');
    expect(stage.text()).toContain('agendado');
    expect(stage.find('span[style]').attributes('style')).toContain(
      'rgb(20, 184, 166)'
    );

    const origin = wrapper.find('[data-testid="sheet-row-origin"]');
    expect(origin.text()).toContain('Anúncio');
    expect(origin.find('a').attributes('href')).toBe('https://fb.me/corte');
    expect(origin.text()).toContain('Corte masculino sem fila');

    expect(wrapper.find('[data-testid="sheet-row-type"]').text()).toContain(
      'Recorrente'
    );
    expect(wrapper.find('[data-testid="sheet-row-servico"]').text()).toContain(
      'Corte'
    );
    expect(
      wrapper.find('[data-testid="sheet-row-profissional"]').text()
    ).toContain('Ana');
    expect(
      wrapper.find('[data-testid="sheet-row-data_agendamento"]').text()
    ).toContain('25/10');
    expect(
      wrapper.find('[data-testid="sheet-row-ciclo_recompra_semanas"]').text()
    ).toContain('a cada 4 semanas');
  });

  it('says "no number" for a LID-only contact and shows dashes for what is missing', () => {
    const wrapper = mountSheet({
      contact: {
        id: 2,
        name: '159519548166205@lid',
        identifier: '159519548166205@lid',
      },
      conversation: { id: 11, labels: [], custom_attributes: {} },
    });

    expect(wrapper.find('[data-testid="sheet-phone"]').text()).toContain(
      'sem número'
    );
    expect(wrapper.text()).not.toContain('@lid');
    expect(wrapper.find('[data-testid="sheet-row-stage"]').text()).toMatch(
      /^Estágio\s*—$/
    );
    expect(wrapper.find('[data-testid="sheet-row-origin"]').text()).toContain(
      'Orgânico'
    );
    expect(wrapper.find('[data-testid="sheet-row-type"]').text()).toContain(
      'Nova'
    );
    expect(wrapper.find('[data-testid="sheet-row-servico"]').text()).toMatch(
      /^Serviço\s*—$/
    );
    expect(
      wrapper.find('[data-testid="sheet-row-data_agendamento"]').text()
    ).toMatch(/^Agendamento\s*—$/);
  });

  it('edits a field inline and emits the new value', async () => {
    const wrapper = mountSheet({
      contact: { id: 1, phone_number: '+5531999998888' },
      conversation: {
        id: 10,
        labels: [],
        custom_attributes: { profissional: 'Ana' },
      },
    });

    await wrapper
      .find('[data-testid="sheet-edit-profissional"]')
      .trigger('click');
    const input = wrapper.find('[data-testid="sheet-row-profissional"] input');
    await input.setValue('Bia');
    await input.trigger('keydown.enter');

    expect(wrapper.emitted('update')).toEqual([['profissional', 'Bia']]);
  });

  it('picks the service from the template list and stores numbers as numbers', async () => {
    const wrapper = mountSheet({
      contact: { id: 1, phone_number: '+5531999998888' },
      conversation: { id: 10, labels: [], custom_attributes: {} },
    });

    await wrapper.find('[data-testid="sheet-edit-servico"]').trigger('click');
    const select = wrapper.find('[data-testid="sheet-row-servico"] select');
    expect(select.findAll('option').map(o => o.text())).toEqual([
      '—',
      'Corte',
      'Coloração',
    ]);
    await select.setValue('Coloração');

    await wrapper
      .find('[data-testid="sheet-edit-ciclo_recompra_semanas"]')
      .trigger('click');
    const number = wrapper.find(
      '[data-testid="sheet-row-ciclo_recompra_semanas"] input'
    );
    await number.setValue('6');
    await number.trigger('keydown.enter');

    expect(wrapper.emitted('update')).toEqual([
      ['servico', 'Coloração'],
      ['ciclo_recompra_semanas', 6],
    ]);
  });
});

describe('ScheduleDialog', () => {
  const mountDialog = (props = {}) =>
    mount(ScheduleDialog, {
      props: { serviceOptions: ['Corte', 'Escova'], ...props },
      global: {
        plugins: [i18n],
        stubs: {
          Dialog: {
            template:
              '<div><slot /><button data-testid="confirm" @click="$emit(\'confirm\')" /></div>',
            methods: { open() {}, close() {} },
          },
        },
      },
    });

  it('prefills from the conversation and emits the appointment with an ISO date', async () => {
    const wrapper = mountDialog({
      initialValues: {
        servico: 'Corte',
        profissional: 'Ana',
        data_agendamento: appointmentAt,
        ciclo_recompra_semanas: 4,
      },
    });
    wrapper.vm.open();
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-testid="schedule-service"]').element.value).toBe(
      'Corte'
    );
    expect(wrapper.find('[data-testid="schedule-date"]').element.value).toBe(
      '2026-10-25T14:00'
    );

    await wrapper.find('[data-testid="schedule-professional"]').setValue('Bia');
    await wrapper
      .find('[data-testid="schedule-date"]')
      .setValue('2026-10-26T09:30');
    await wrapper.find('[data-testid="confirm"]').trigger('click');

    expect(wrapper.emitted('confirm')).toEqual([
      [
        {
          servico: 'Corte',
          profissional: 'Bia',
          data_agendamento: rescheduledAt,
          ciclo_recompra_semanas: 4,
        },
      ],
    ]);
  });

  it('does not confirm without a date', async () => {
    const wrapper = mountDialog();
    wrapper.vm.open();
    await wrapper.vm.$nextTick();

    await wrapper.find('[data-testid="confirm"]').trigger('click');

    expect(wrapper.emitted('confirm')).toBeUndefined();
  });
});

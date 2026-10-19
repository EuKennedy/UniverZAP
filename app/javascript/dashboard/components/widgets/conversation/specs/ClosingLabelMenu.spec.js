import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ClosingLabelMenu from '../ClosingLabelMenu.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      CONVERSATION: {
        CLOSING_LABEL: {
          TITLE: 'How did this conversation end?',
          DESCRIPTION: 'Pick the status that closes it.',
        },
      },
    },
  },
});

const labels = [
  {
    id: 1,
    title: 'cancelado',
    color: '#EF4444',
    description: 'Cliente desistiu do horário',
    closes_conversation: true,
  },
  {
    id: 2,
    title: 'atendimento-encerrado',
    color: '#94A3B8',
    description: 'Serviço concluído',
    closes_conversation: true,
  },
];

const mountMenu = (props = {}) =>
  mount(ClosingLabelMenu, {
    props: { labels, ...props },
    global: { plugins: [i18n] },
  });

describe('ClosingLabelMenu', () => {
  it('lists every closing status with its description', () => {
    const wrapper = mountMenu();

    expect(wrapper.text()).toContain('How did this conversation end?');
    expect(wrapper.text()).toContain('cancelado');
    expect(wrapper.text()).toContain('Cliente desistiu do horário');
    expect(wrapper.text()).toContain('atendimento-encerrado');
    expect(wrapper.findAll('button')).toHaveLength(2);
  });

  it('emits the chosen label', async () => {
    const wrapper = mountMenu();

    await wrapper
      .find('[data-testid="closing-label-atendimento-encerrado"]')
      .trigger('click');

    expect(wrapper.emitted('select')).toHaveLength(1);
    expect(wrapper.emitted('select')[0][0]).toEqual(labels[1]);
  });

  it('disables the choices while a resolve is in flight', () => {
    const wrapper = mountMenu({ isLoading: true });

    expect(
      wrapper.findAll('button').every(button => button.element.disabled)
    ).toBe(true);
  });
});

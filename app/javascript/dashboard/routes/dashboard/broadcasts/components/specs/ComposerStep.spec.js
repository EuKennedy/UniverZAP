import { mount } from '@vue/test-utils';
import ComposerStep from '../ComposerStep.vue';

const mountStep = props =>
  mount(ComposerStep, {
    props: { id: 'audience', number: 4, title: 'Público', ...props },
    slots: { default: '<p data-testid="body">conteúdo</p>' },
  });

describe('ComposerStep', () => {
  it('mostra o número e o selo "Falta" quando a etapa não está pronta', () => {
    const wrapper = mountStep({ state: 'missing', stateLabel: 'Falta' });

    expect(wrapper.attributes('id')).toBe('audience');
    expect(wrapper.text()).toContain('4');
    expect(wrapper.text()).toContain('Falta');
    expect(wrapper.find('[data-testid="body"]').exists()).toBe(true);
  });

  it('troca o número pelo check quando está pronta', () => {
    const wrapper = mountStep({ state: 'done', stateLabel: 'Pronto' });

    expect(wrapper.find('.i-lucide-check').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('4');
  });
});

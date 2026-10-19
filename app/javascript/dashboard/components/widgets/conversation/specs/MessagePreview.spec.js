import { mount } from '@vue/test-utils';
import MessagePreview from '../MessagePreview.vue';

const AD_CONTENT =
  '📢 **ANÚNCIO DO FACEBOOK**\n**Título:** api.whatsapp.com\n**ID do Anúncio:** 120251719556440201\n---\n💬 **MENSAGEM DO CLIENTE:**\nOlá! Posso ter mais informações sobre isso?';

const buildMessage = (overrides = {}) => ({
  id: 1,
  content: AD_CONTENT,
  message_type: 0,
  private: false,
  content_attributes: {},
  attachments: [],
  ...overrides,
});

const mountPreview = message =>
  mount(MessagePreview, {
    props: { message: buildMessage(message) },
    global: { stubs: { 'fluent-icon': true } },
  });

describe('Legacy conversation list MessagePreview', () => {
  it('shows the message content when there is no ad_referral', () => {
    const wrapper = mountPreview({ content: 'Oi, quero agendar' });

    expect(wrapper.text()).toContain('Oi, quero agendar');
  });

  it('shows the customer message when the message came from an ad', () => {
    const wrapper = mountPreview({
      content_attributes: {
        ad_referral: {
          ad_id: '120251719556440201',
          customer_message: 'Olá! Posso ter mais informações sobre isso?',
        },
      },
    });

    expect(wrapper.text()).toContain(
      'Olá! Posso ter mais informações sobre isso?'
    );
    expect(wrapper.text()).not.toContain('ANÚNCIO DO FACEBOOK');
  });
});

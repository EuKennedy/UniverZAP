import { mount } from '@vue/test-utils';
import { ref, computed } from 'vue';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import TextBubble from '../Index.vue';

let messageContext = {};

vi.mock('dashboard/components-next/message/provider.js', () => ({
  useMessageContext: () => messageContext,
}));

vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: ref(false),
    translationContent: ref(null),
  }),
}));

vi.mock(
  'dashboard/components/widgets/conversation/components/GalleryView.vue',
  () => ({ default: { template: '<div />' } })
);

const AD_CONTENT = [
  '📢 **ANÚNCIO DO FACEBOOK**',
  '**Título:** api.whatsapp.com',
  '**Descrição:**',
  '**Link do Anúncio:** [Ver no Facebook](https://www.instagram.com/p/abc/)',
  '**ID do Anúncio:** 120251719556440201',
  '---',
  '💬 **MENSAGEM DO CLIENTE:**',
  'Olá! Posso ter mais informações sobre isso?',
].join('\n');

const imageAttachment = {
  id: 7,
  fileType: 'image',
  dataUrl: 'https://cdn.example.com/criativo.jpg',
  thumbUrl: 'https://cdn.example.com/criativo.jpg',
};

const buildContext = ({
  content = AD_CONTENT,
  contentAttributes = {},
  attachments = [],
} = {}) => ({
  content: ref(content),
  attachments: ref(attachments),
  contentAttributes: ref(contentAttributes),
  messageType: ref(0),
  variant: ref('user'),
  orientation: ref('left'),
  inReplyTo: ref(null),
  shouldGroupWithNext: ref(true),
  filteredCurrentChatAttachments: computed(() => []),
});

const mountBubble = context => {
  messageContext = buildContext(context);
  return mount(TextBubble, {
    global: { plugins: [VueDOMPurifyHTML] },
  });
};

describe('Text bubble', () => {
  describe('without ad_referral', () => {
    it('renders the raw content and attachments as before', () => {
      const wrapper = mountBubble({
        content: 'Oi, quero agendar',
        attachments: [imageAttachment],
      });

      expect(wrapper.text()).toContain('Oi, quero agendar');
      expect(wrapper.find('[data-test-id="ad-referral-card"]').exists()).toBe(
        false
      );
      expect(wrapper.findAll('img')).toHaveLength(1);
    });
  });

  describe('with ad_referral', () => {
    const adReferral = {
      source: 'facebook',
      adId: '120251719556440201',
      title: null,
      body: null,
      url: 'https://www.instagram.com/p/abc/',
      customerMessage: 'Olá! Posso ter mais informações sobre isso?',
    };

    it('shows the customer message as the main text instead of the ad markdown', () => {
      const wrapper = mountBubble({ contentAttributes: { adReferral } });

      expect(wrapper.text()).toContain(
        'Olá! Posso ter mais informações sobre isso?'
      );
      expect(wrapper.text()).not.toContain('ANÚNCIO DO FACEBOOK');
      expect(wrapper.text()).not.toContain('MENSAGEM DO CLIENTE');
    });

    it('renders a compact card with the ad id and a link to the ad', () => {
      const wrapper = mountBubble({ contentAttributes: { adReferral } });
      const card = wrapper.find('[data-test-id="ad-referral-card"]');

      expect(card.exists()).toBe(true);
      expect(card.text()).toContain('Ad');
      expect(card.text()).toContain('120251719556440201');
      expect(
        card.find('[data-test-id="ad-referral-link"]').attributes('href')
      ).toBe('https://www.instagram.com/p/abc/');
      expect(card.find('[data-test-id="ad-referral-title"]').exists()).toBe(
        false
      );
    });

    it('shows the ad title when there is one', () => {
      const wrapper = mountBubble({
        contentAttributes: {
          adReferral: { ...adReferral, title: 'Progressiva com 30% off' },
        },
      });

      expect(
        wrapper.find('[data-test-id="ad-referral-title"]').text()
      ).toContain('Progressiva com 30% off');
    });

    it('omits the link when the ad has no url', () => {
      const wrapper = mountBubble({
        contentAttributes: { adReferral: { ...adReferral, url: null } },
      });

      expect(wrapper.find('[data-test-id="ad-referral-link"]').exists()).toBe(
        false
      );
    });

    it('moves the creative thumbnail into the card instead of the bubble footer', () => {
      const wrapper = mountBubble({
        contentAttributes: { adReferral },
        attachments: [imageAttachment],
      });
      const card = wrapper.find('[data-test-id="ad-referral-card"]');

      expect(wrapper.findAll('img')).toHaveLength(1);
      expect(card.findAll('img')).toHaveLength(1);
      expect(card.find('img').attributes('src')).toBe(imageAttachment.dataUrl);
    });
  });
});

import { computed } from 'vue';
import { isVoiceCallEnabled } from 'dashboard/helper/inbox';

export function useChannelIcon(inbox) {
  const channelTypeIconMap = {
    'Channel::Api': 'i-woot-api',
    'Channel::Email': 'i-woot-mail',
    'Channel::FacebookPage': 'i-woot-messenger',
    'Channel::Line': 'i-woot-line',
    'Channel::Sms': 'i-woot-sms',
    'Channel::Telegram': 'i-woot-telegram',
    'Channel::TwilioSms': 'i-woot-sms',
    'Channel::TwitterProfile': 'i-woot-x',
    'Channel::WebWidget': 'i-woot-website',
    'Channel::Whatsapp': 'i-woot-whatsapp',
    'Channel::Instagram': 'i-woot-instagram',
    'Channel::Tiktok': 'i-woot-tiktok',
  };

  const providerIconMap = {
    microsoft: 'i-woot-outlook',
    google: 'i-woot-gmail',
  };

  const channelIcon = computed(() => {
    const inboxDetails = inbox.value || inbox;
    const type = inboxDetails.channel_type;
    let icon = channelTypeIconMap[type];

    if (type === 'Channel::Email' && inboxDetails.provider) {
      if (Object.keys(providerIconMap).includes(inboxDetails.provider)) {
        icon = providerIconMap[inboxDetails.provider];
      }
    }

    // Special case for Twilio whatsapp
    if (type === 'Channel::TwilioSms' && inboxDetails.medium === 'whatsapp') {
      icon = 'i-woot-whatsapp';
    }

    // Channel::Api inboxes provisioned through the WAHA wizard / migration
    // are surfaced as WhatsApp in the UI. Match either medium='whatsapp'
    // (set by serializer) or additional_attributes.source='waha' (raw DB)
    // so caller-supplied lightweight inbox objects still render correctly.
    if (type === 'Channel::Api') {
      const medium = inboxDetails.medium;
      const additionalAttrs =
        inboxDetails.additional_attributes ||
        inboxDetails.additionalAttributes ||
        {};
      if (medium === 'whatsapp' || additionalAttrs.source === 'waha') {
        icon = 'i-woot-whatsapp';
      }
    }

    // Special case for voice-enabled inboxes (Twilio, WhatsApp, etc.)
    if (isVoiceCallEnabled(inboxDetails)) {
      icon = 'i-woot-voice';
    }

    return icon ?? 'i-ri-global-fill';
  });

  return channelIcon;
}

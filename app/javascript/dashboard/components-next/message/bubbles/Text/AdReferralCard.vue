<script setup>
import Icon from 'next/icon/Icon.vue';
import ImageChip from 'next/message/chips/Image.vue';

defineProps({
  adReferral: {
    type: Object,
    required: true,
  },
  attachments: {
    type: Array,
    default: () => [],
  },
});
</script>

<template>
  <div
    data-test-id="ad-referral-card"
    class="flex flex-col gap-2 p-2 -mx-1 rounded-lg bg-n-alpha-black1"
  >
    <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
      <Icon icon="i-lucide-megaphone" class="flex-shrink-0 size-3.5" />
      <span class="font-medium">
        {{ $t('CONVERSATION.AD_REFERRAL.LABEL') }}
      </span>
      <span class="truncate">{{ adReferral.adId }}</span>
    </div>
    <p
      v-if="adReferral.title"
      data-test-id="ad-referral-title"
      class="mb-0 text-sm font-medium text-n-slate-12 line-clamp-2"
    >
      {{ adReferral.title }}
    </p>
    <div v-if="attachments.length" class="flex flex-wrap gap-2">
      <ImageChip
        v-for="attachment in attachments"
        :key="attachment.id"
        :attachment="attachment"
      />
    </div>
    <a
      v-if="adReferral.url"
      data-test-id="ad-referral-link"
      :href="adReferral.url"
      target="_blank"
      rel="noopener noreferrer nofollow"
      class="self-start text-xs font-medium text-n-slate-11 hover:underline"
    >
      {{ $t('CONVERSATION.AD_REFERRAL.VIEW_AD') }}
    </a>
  </div>
</template>

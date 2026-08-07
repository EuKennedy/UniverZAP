<script setup>
import { ref, nextTick, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistantId: { type: Number, required: true },
});

const { t } = useI18n();

const messages = ref([]);
const draft = ref('');
const isSending = ref(false);
const errorMessage = ref('');
const scroller = ref(null);

const canSend = computed(
  () => draft.value.trim().length > 0 && !isSending.value
);

const latencyLabel = ms => `${Math.round(ms / 100) / 10}s`;

// Claude's own 0..1 self-assessment, stripped from the reply before it is
// shown. Surfaced here because the sandbox exists to expose exactly this.
const confidencePercent = value =>
  value === null || value === undefined ? null : Math.round(value * 100);

const scrollToEnd = async () => {
  await nextTick();
  if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
};

const loadTranscript = async () => {
  try {
    const { data } = await AthenasAPI.getPlayground(props.assistantId);
    messages.value = (data.transcript || []).map(m => ({ ...m }));
    scrollToEnd();
  } catch {
    // An empty sandbox is the normal first-run state, not an error worth showing.
  }
};

// A turn takes 20-40s — longer than a web request is allowed to live — so the
// backend queues it and the reply shows up in the transcript. We wait for it
// here instead of holding a request open.
const REPLY_POLL_INTERVAL_MS = 2000;
const REPLY_TIMEOUT_MS = 180000;

const waitForReply = async previousCount => {
  const deadline = Date.now() + REPLY_TIMEOUT_MS;
  while (Date.now() < deadline) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, REPLY_POLL_INTERVAL_MS);
    });
    // eslint-disable-next-line no-await-in-loop
    const { data } = await AthenasAPI.getPlayground(props.assistantId);
    const transcript = data.transcript || [];
    if (transcript.length > previousCount) {
      messages.value = transcript.map(m => ({ ...m }));
      scrollToEnd();
      return true;
    }
  }
  return false;
};

const send = async () => {
  if (!canSend.value) return;
  const text = draft.value.trim();
  draft.value = '';
  errorMessage.value = '';
  // The queued turn writes the customer message too; count it so the poll knows
  // what "a new message arrived" means.
  const expectedCount = messages.value.length + 2;
  messages.value.push({ role: 'user', content: text });
  isSending.value = true;
  scrollToEnd();

  try {
    await AthenasAPI.sendPlaygroundMessage(props.assistantId, text);
    const arrived = await waitForReply(expectedCount - 1);
    if (!arrived) errorMessage.value = t('ATHENAS.PLAYGROUND.TIMEOUT');
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.error || t('ATHENAS.PLAYGROUND.ERROR');
  } finally {
    isSending.value = false;
    scrollToEnd();
  }
};

const reset = async () => {
  try {
    await AthenasAPI.resetPlayground(props.assistantId);
    messages.value = [];
    errorMessage.value = '';
  } catch {
    errorMessage.value = t('ATHENAS.PLAYGROUND.ERROR');
  }
};

onMounted(loadTranscript);
</script>

<template>
  <section class="flex flex-col gap-4">
    <header class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-semibold text-n-slate-12 tracking-tight">
          {{ t('ATHENAS.PLAYGROUND.TITLE') }}
        </h2>
        <p class="text-[13px] text-n-slate-11 leading-relaxed max-w-xl">
          {{ t('ATHENAS.PLAYGROUND.HINT') }}
        </p>
      </div>
      <Button
        v-if="messages.length"
        variant="ghost"
        size="sm"
        icon="i-lucide-rotate-ccw"
        :label="t('ATHENAS.PLAYGROUND.RESET')"
        @click="reset"
      />
    </header>

    <div
      ref="scroller"
      class="flex flex-col gap-3 h-[26rem] overflow-y-auto p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
    >
      <div
        v-if="!messages.length"
        class="flex flex-col items-center justify-center gap-2 h-full text-center"
      >
        <span
          class="size-12 rounded-2xl bg-gradient-to-br from-n-teal-3 to-transparent ring-1 ring-n-weak grid place-content-center"
        >
          <span class="i-lucide-message-circle size-6 text-n-teal-11" />
        </span>
        <p class="text-[13px] text-n-slate-11 max-w-xs">
          {{ t('ATHENAS.PLAYGROUND.EMPTY') }}
        </p>
      </div>

      <div
        v-for="(message, index) in messages"
        :key="index"
        class="flex"
        :class="message.role === 'user' ? 'justify-end' : 'justify-start'"
      >
        <div class="flex flex-col gap-1.5 max-w-[80%]">
          <div
            class="px-3.5 py-2.5 rounded-2xl text-[13px] leading-relaxed whitespace-pre-wrap"
            :class="
              message.role === 'user'
                ? 'bg-n-teal-9 text-white rounded-br-md'
                : 'bg-n-alpha-2 text-n-slate-12 ring-1 ring-n-weak rounded-bl-md'
            "
          >
            <template v-if="message.content">{{ message.content }}</template>
            <span v-else class="italic text-n-slate-11">
              {{ t(`ATHENAS.PLAYGROUND.STATUS.${message.status}`) }}
            </span>
          </div>

          <!-- Diagnostics are the point of the sandbox: they answer "where did
               that answer come from, and did the guardrails step in?" -->
          <div
            v-if="message.diagnostics"
            class="flex flex-wrap items-center gap-1.5 px-1"
          >
            <span
              v-for="title in message.diagnostics.knowledge_titles"
              :key="title"
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-n-alpha-2 ring-1 ring-n-weak text-[11px] text-n-slate-11"
            >
              <span class="i-lucide-book-open size-3" />
              {{ title }}
            </span>
            <span
              v-if="message.diagnostics.regenerated_for_grounding"
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-n-amber-3 ring-1 ring-n-amber-6 text-[11px] text-n-amber-11"
            >
              <span class="i-lucide-shield-alert size-3" />
              {{ t('ATHENAS.PLAYGROUND.CORRECTED') }}
            </span>
            <span
              v-for="flag in message.diagnostics.auto_flags || []"
              :key="flag"
              class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-n-amber-3 ring-1 ring-n-amber-6 text-[11px] text-n-amber-11"
            >
              <span class="i-lucide-flag size-3" />
              {{ t(`ATHENAS.ANALYTICS.FLAGS.${flag.toUpperCase()}`) }}
            </span>
            <span
              v-if="confidencePercent(message.diagnostics.confidence) !== null"
              class="text-[11px] text-n-slate-10 tabular-nums"
            >
              {{
                t('ATHENAS.ANALYTICS.CONFIDENCE', {
                  n: confidencePercent(message.diagnostics.confidence),
                })
              }}
            </span>
            <span
              v-if="message.diagnostics.latency_ms"
              class="text-[11px] text-n-slate-10 tabular-nums"
            >
              {{ latencyLabel(message.diagnostics.latency_ms) }}
            </span>
          </div>
        </div>
      </div>

      <div v-if="isSending" class="flex justify-start">
        <div
          class="px-3.5 py-2.5 rounded-2xl rounded-bl-md bg-n-alpha-2 ring-1 ring-n-weak"
        >
          <span class="i-lucide-loader-2 size-4 animate-spin text-n-slate-11" />
        </div>
      </div>
    </div>

    <p v-if="errorMessage" class="text-[12px] text-n-ruby-11">
      {{ errorMessage }}
    </p>

    <div class="flex items-end gap-2">
      <textarea
        v-model="draft"
        rows="2"
        :placeholder="t('ATHENAS.PLAYGROUND.PLACEHOLDER')"
        class="flex-1 resize-none px-3.5 py-2.5 rounded-xl bg-n-alpha-2 ring-1 ring-n-weak text-[13px] text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-n-teal-8"
        @keydown.enter.exact.prevent="send"
      />
      <Button
        :disabled="!canSend"
        :is-loading="isSending"
        icon="i-lucide-send"
        :label="t('ATHENAS.PLAYGROUND.SEND')"
        @click="send"
      />
    </div>
  </section>
</template>

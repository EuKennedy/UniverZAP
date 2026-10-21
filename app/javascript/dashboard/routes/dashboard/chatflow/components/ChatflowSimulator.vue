<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChatflowsAPI from 'dashboard/api/chatflows';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { EVENT_ICONS, newSeed } from '../helpers/simulator';

// Simulador: conversa com o fluxo como se fosse a cliente. O servidor roda o
// motor de verdade numa transação desfeita — nada é gravado, nada sai para o
// WhatsApp. Sem estado no servidor: cada resposta reenvia todas as falas.
const props = defineProps({
  chatflowId: { type: [String, Number], required: true },
});

const emit = defineEmits(['highlight', 'close']);

const { t } = useI18n();

const seed = ref(newSeed());
const inputs = ref([]);
const result = ref(null);
const draft = ref('');
const isLoading = ref(false);
const error = ref(null);
const scroller = ref(null);

const transcript = computed(() => result.value?.transcript || []);
const answers = computed(() => Object.entries(result.value?.answers || {}));
const finished = computed(() => Boolean(result.value?.finished));

const scrollToEnd = async () => {
  await nextTick();
  if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
};

const run = async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await ChatflowsAPI.simulate(props.chatflowId, {
      inputs: inputs.value,
      seed: seed.value,
    });
    result.value = data;
    if (data.error) {
      error.value = t(`CHATFLOW.SIMULATOR.ERRORS.${data.error.toUpperCase()}`);
    }
    emit('highlight', {
      visited: (data.visited_node_ids || []).map(String),
      current: data.current_node_id ? String(data.current_node_id) : null,
    });
    scrollToEnd();
  } catch {
    error.value = t('CHATFLOW.SIMULATOR.ERRORS.GENERIC');
  } finally {
    isLoading.value = false;
  }
};

const restart = () => {
  seed.value = newSeed();
  inputs.value = [];
  draft.value = '';
  run();
};

const send = () => {
  const text = draft.value.trim();
  if (!text || isLoading.value || finished.value) return;
  inputs.value = [...inputs.value, text];
  draft.value = '';
  run();
};

const close = () => {
  emit('highlight', { visited: [], current: null });
  emit('close');
};

onMounted(run);
</script>

<template>
  <aside
    class="flex flex-col w-[360px] h-full shrink-0 bg-n-solid-1 border-l border-n-weak"
    data-testid="chatflow-simulator"
  >
    <header
      class="flex items-center justify-between gap-2 px-4 h-14 border-b border-n-weak"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="flex items-center justify-center size-7 rounded-lg bg-brand-gradient text-[#06131C]"
        >
          <Icon icon="i-lucide-smartphone" class="size-3.5" />
        </span>
        <div class="flex flex-col min-w-0">
          <h3 class="text-sm font-semibold text-n-slate-12 m-0">
            {{ t('CHATFLOW.SIMULATOR.TITLE') }}
          </h3>
          <span class="text-[11px] text-n-teal-11">
            {{ t('CHATFLOW.SIMULATOR.SAFE') }}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-1">
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-rotate-ccw"
          :title="t('CHATFLOW.SIMULATOR.RESTART')"
          data-testid="simulator-restart"
          @click="restart"
        />
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-x"
          @click="close"
        />
      </div>
    </header>

    <div
      ref="scroller"
      class="flex-1 overflow-auto px-3 py-4 flex flex-col gap-2 bg-n-background"
    >
      <p
        v-if="error"
        class="p-3 rounded-xl bg-n-ruby-3 text-n-ruby-11 text-xs m-0"
        data-testid="simulator-error"
      >
        {{ error }}
      </p>
      <template v-for="(line, index) in transcript" :key="index">
        <div
          v-if="line.type === 'bot'"
          class="self-start max-w-[85%] px-3 py-2 rounded-2xl rounded-tl-md bg-n-solid-2 border border-n-weak text-sm text-n-slate-12 whitespace-pre-line"
          data-testid="simulator-bot"
        >
          <span
            v-if="line.attachment"
            class="flex items-center gap-1 mb-1 text-[11px] text-n-slate-10"
          >
            <Icon icon="i-lucide-paperclip" class="size-3" />
            {{ t('CHATFLOW.SIMULATOR.ATTACHMENT') }}
          </span>
          {{ line.text }}
        </div>
        <div
          v-else-if="line.type === 'user'"
          class="self-end max-w-[85%] px-3 py-2 rounded-2xl rounded-tr-md bg-n-teal-9 text-sm text-white whitespace-pre-line"
          data-testid="simulator-user"
        >
          {{ line.text }}
        </div>
        <div
          v-else
          class="self-center flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-n-alpha-2 text-[11px] text-n-slate-11"
          data-testid="simulator-event"
        >
          <Icon
            :icon="EVENT_ICONS[line.event] || 'i-lucide-info'"
            class="size-3"
          />
          {{ t(`CHATFLOW.SIMULATOR.EVENTS.${line.event.toUpperCase()}`) }}
        </div>
      </template>
      <div
        v-if="isLoading"
        class="self-start flex gap-1 px-3 py-2.5 rounded-2xl bg-n-solid-2 border border-n-weak"
      >
        <span
          class="size-1.5 rounded-full bg-n-slate-9 motion-safe:animate-bounce"
        />
        <span
          class="size-1.5 rounded-full bg-n-slate-9 motion-safe:animate-bounce [animation-delay:120ms]"
        />
        <span
          class="size-1.5 rounded-full bg-n-slate-9 motion-safe:animate-bounce [animation-delay:240ms]"
        />
      </div>
      <p
        v-if="finished && !isLoading && !error"
        class="self-center text-[11px] text-n-slate-10 m-0"
        data-testid="simulator-finished"
      >
        {{ t('CHATFLOW.SIMULATOR.FINISHED') }}
      </p>
    </div>

    <div
      v-if="answers.length"
      class="flex flex-wrap gap-1.5 px-3 py-2 border-t border-n-weak"
      data-testid="simulator-answers"
    >
      <span
        class="text-[10px] font-semibold uppercase tracking-wider text-n-slate-10 w-full"
      >
        {{ t('CHATFLOW.SIMULATOR.CAPTURED') }}
      </span>
      <span
        v-for="[key, value] in answers"
        :key="key"
        class="px-2 py-0.5 rounded-md bg-n-teal-3 text-n-teal-12 text-[11px]"
      >
        {{ key }}: {{ value }}
      </span>
    </div>

    <form
      class="flex items-center gap-2 px-3 py-3 border-t border-n-weak"
      @submit.prevent="send"
    >
      <input
        v-model="draft"
        type="text"
        :disabled="finished"
        :placeholder="
          finished
            ? t('CHATFLOW.SIMULATOR.ENDED_PLACEHOLDER')
            : t('CHATFLOW.SIMULATOR.PLACEHOLDER')
        "
        class="flex-1 h-10 px-3 rounded-full bg-n-alpha-1 border border-n-weak text-sm text-n-slate-12 focus:outline-none focus:border-n-teal-8 disabled:opacity-60"
        data-testid="simulator-input"
      />
      <Button
        type="submit"
        icon="i-lucide-send-horizontal"
        :disabled="finished || !draft.trim()"
        :is-loading="isLoading"
        data-testid="simulator-send"
      />
    </form>
  </aside>
</template>

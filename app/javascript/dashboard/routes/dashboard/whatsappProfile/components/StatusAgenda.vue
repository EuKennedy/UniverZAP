<script setup>
/**
 * A semana de status num olhar: o que sai em cada um dos próximos 7 dias.
 * Serve para ver buraco ("quinta está vazia") e excesso ("três no sábado")
 * antes de o cliente ver. Clicar num item abre ele no compositor.
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import WhatsAppStatusAPI from 'dashboard/api/whatsappStatus';
import { dateLocale, isSameDay, nextDays } from '../helpers';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusPreview from './StatusPreview.vue';

const props = defineProps({
  refreshKey: { type: Number, default: 0 },
  inboxId: { type: Number, default: null },
});

const emit = defineEmits(['edit']);

const { t, locale } = useI18n();
const label = key => t(`WHATSAPP_PROFILE.AGENDA.${key}`);

const DAYS = 7;
const posts = ref([]);
const isLoading = ref(false);

const days = computed(() =>
  nextDays(DAYS).map(day => ({
    day,
    isToday: isSameDay(day, new Date()),
    posts: posts.value.filter(post =>
      isSameDay(new Date(post.scheduled_at), day)
    ),
  }))
);

const weekday = day =>
  day.toLocaleDateString(dateLocale(locale), { weekday: 'short' });
const dayNumber = day =>
  day.toLocaleDateString(dateLocale(locale), {
    day: '2-digit',
    month: '2-digit',
  });
const time = value =>
  new Date(value).toLocaleTimeString(dateLocale(locale), {
    hour: '2-digit',
    minute: '2-digit',
  });

const fetchAgenda = async () => {
  isLoading.value = true;
  const until = nextDays(DAYS + 1).at(-1);
  try {
    const { data } = await WhatsAppStatusAPI.list({
      status: 'scheduled',
      per: 50,
      until: until.toISOString(),
      inboxId: props.inboxId,
    });
    posts.value = data.payload || [];
  } catch {
    posts.value = [];
  } finally {
    isLoading.value = false;
  }
};

watch(() => [props.refreshKey, props.inboxId], fetchAgenda);
onMounted(fetchAgenda);
</script>

<template>
  <div v-if="isLoading" class="flex justify-center py-8">
    <Spinner :size="20" />
  </div>
  <div
    v-else
    class="grid gap-2 grid-cols-1 sm:grid-cols-[repeat(auto-fit,minmax(8.5rem,1fr))]"
    data-testid="agenda"
  >
    <div
      v-for="entry in days"
      :key="entry.day.toISOString()"
      class="flex flex-col gap-2 p-2.5 rounded-xl border min-h-32"
      :class="
        entry.isToday ? 'border-n-brand/50 bg-n-alpha-1' : 'border-n-weak'
      "
      data-testid="agenda-day"
    >
      <div class="flex justify-between items-baseline">
        <span
          class="text-[11px] font-semibold tracking-wide uppercase text-n-slate-11"
        >
          {{ entry.isToday ? label('TODAY') : weekday(entry.day) }}
        </span>
        <span class="text-[11px] text-n-slate-10">
          {{ dayNumber(entry.day) }}
        </span>
      </div>
      <p
        v-if="!entry.posts.length"
        class="m-auto text-[11px] text-center text-n-slate-10"
      >
        {{ label('EMPTY_DAY') }}
      </p>
      <button
        v-for="post in entry.posts"
        :key="post.id"
        type="button"
        class="flex gap-2 items-center p-1.5 rounded-lg text-start hover:bg-n-alpha-2"
        data-testid="agenda-item"
        @click="emit('edit', post)"
      >
        <StatusPreview
          compact
          class="!w-8"
          :kind="post.kind"
          :body="post.body || ''"
          :background-color="post.background_color || ''"
          :font="post.font"
          :media-url="post.media?.url || ''"
        />
        <span class="flex flex-col min-w-0">
          <span class="text-[12px] font-semibold text-n-slate-12">
            {{ time(post.scheduled_at) }}
            <span
              v-if="post.recurrence !== 'none'"
              class="align-middle i-lucide-repeat size-3 text-n-slate-10"
            />
          </span>
          <span class="text-[11px] truncate text-n-slate-11">
            {{
              post.body ||
              t(`WHATSAPP_PROFILE.HISTORY.NO_TEXT.${post.kind.toUpperCase()}`)
            }}
          </span>
        </span>
      </button>
    </div>
  </div>
</template>

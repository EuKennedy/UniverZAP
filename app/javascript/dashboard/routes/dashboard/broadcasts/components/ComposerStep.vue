<script setup>
// Uma etapa do editor de campanha: cartão com número, título, dica e o
// estado (pronta / falta / opcional). A barra de etapas do topo rola até o
// `id` daqui.
defineProps({
  id: { type: String, required: true },
  number: { type: Number, required: true },
  title: { type: String, required: true },
  hint: { type: String, default: '' },
  // 'done' | 'missing' | 'optional'
  state: { type: String, default: 'done' },
  stateLabel: { type: String, default: '' },
});
</script>

<template>
  <section
    :id="id"
    class="flex flex-col gap-4 p-6 rounded-2xl border scroll-mt-20 border-n-weak bg-n-solid-1"
    :data-testid="`composer-step-${id}`"
  >
    <div class="flex items-start gap-3">
      <span
        class="flex items-center justify-center text-xs font-bold rounded-lg size-7 shrink-0"
        :class="
          state === 'done'
            ? 'bg-brand-gradient text-[#06131C]'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
      >
        <span v-if="state === 'done'" class="i-lucide-check size-3.5" />
        <template v-else>{{ number }}</template>
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-0.5">
        <h2 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ title }}
        </h2>
        <p v-if="hint" class="m-0 text-xs text-n-slate-11">{{ hint }}</p>
      </div>
      <span
        v-if="stateLabel"
        class="px-2 py-0.5 rounded-full text-[11px] font-medium shrink-0"
        :class="{
          'bg-n-teal-3 text-n-teal-11': state === 'done',
          'bg-n-amber-3 text-n-amber-11': state === 'missing',
          'bg-n-alpha-2 text-n-slate-11': state === 'optional',
        }"
      >
        {{ stateLabel }}
      </span>
    </div>
    <slot />
  </section>
</template>

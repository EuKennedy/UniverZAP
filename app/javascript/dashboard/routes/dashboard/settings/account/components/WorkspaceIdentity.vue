<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import WorkspaceAPI from 'dashboard/api/workspace';
import {
  COVER_THEMES,
  GRADIENT_THEMES,
  SOLID_THEMES,
  autoCoverTheme,
} from 'dashboard/helper/workspaceCover';
import SectionLayout from './SectionLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import WorkspaceCover from 'next/workspace/WorkspaceCover.vue';
import WorkspaceAvatar from 'next/workspace/WorkspaceAvatar.vue';

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const verticals = ref([]);
const chosenVertical = ref('');
const savingKey = ref('');
const coverInput = useTemplateRef('coverInput');
const logoInput = useTemplateRef('logoInput');

const coverTheme = computed(() => currentAccount.value.settings?.cover_theme);
const currentVertical = computed(() => currentAccount.value.vertical);
const verticalName = computed(
  () => verticals.value.find(v => v.key === currentVertical.value)?.name
);
const chosenVerticalName = computed(
  () => verticals.value.find(v => v.key === chosenVertical.value)?.name
);

// What the shared cover components expect, built from the account record.
const preview = computed(() => ({
  name: currentAccount.value.name,
  cover_theme: coverTheme.value,
  cover_url: currentAccount.value.cover_url,
  logo_url: currentAccount.value.logo_url,
}));
const autoClass = computed(
  () => COVER_THEMES[autoCoverTheme(currentAccount.value.name)]
);

const fetchWorkspace = async () => {
  const { data } = await WorkspaceAPI.get();
  verticals.value = data.verticals;
  chosenVertical.value = data.vertical || '';
};

// The switcher reads the accounts from the signed-in user, so refresh both.
const applyResponse = async data => {
  store.commit('accounts/EDIT_ACCOUNT', data);
  await store.dispatch('validityCheck');
};

const save = async (key, request, successMessage) => {
  savingKey.value = key;
  try {
    const { data } = await request();
    await applyResponse(data);
    useAlert(successMessage || t('WORKSPACE_SETTINGS.API.SUCCESS'));
  } catch {
    useAlert(t('WORKSPACE_SETTINGS.API.ERROR'));
  } finally {
    savingKey.value = '';
  }
};

const chooseTheme = theme => {
  if ((theme || null) === (coverTheme.value || null)) return;
  save(`theme-${theme}`, () =>
    WorkspaceAPI.update({ cover_theme: theme || '' })
  );
};

const upload = (field, event) => {
  const [file] = event.target.files;
  event.target.value = '';
  if (!file) return;
  const formData = new FormData();
  formData.append(field, file);
  save(field, () => WorkspaceAPI.update(formData));
};

const remove = field =>
  save(`remove-${field}`, () => WorkspaceAPI.removeAttachment(field));

const applyVertical = () =>
  save(
    'vertical',
    () => WorkspaceAPI.update({ vertical: chosenVertical.value }),
    t('WORKSPACE_SETTINGS.API.VERTICAL_SUCCESS')
  );

const THEME_LABELS = computed(() => ({
  brand: t('WORKSPACE_SETTINGS.THEMES.BRAND'),
  aurora: t('WORKSPACE_SETTINGS.THEMES.AURORA'),
  sunset: t('WORKSPACE_SETTINGS.THEMES.SUNSET'),
  ocean: t('WORKSPACE_SETTINGS.THEMES.OCEAN'),
  berry: t('WORKSPACE_SETTINGS.THEMES.BERRY'),
  ember: t('WORKSPACE_SETTINGS.THEMES.EMBER'),
  orchid: t('WORKSPACE_SETTINGS.THEMES.ORCHID'),
  graphite: t('WORKSPACE_SETTINGS.THEMES.GRAPHITE'),
  solid_teal: t('WORKSPACE_SETTINGS.THEMES.SOLID_TEAL'),
  solid_iris: t('WORKSPACE_SETTINGS.THEMES.SOLID_IRIS'),
  solid_ruby: t('WORKSPACE_SETTINGS.THEMES.SOLID_RUBY'),
  solid_amber: t('WORKSPACE_SETTINGS.THEMES.SOLID_AMBER'),
  solid_violet: t('WORKSPACE_SETTINGS.THEMES.SOLID_VIOLET'),
  solid_slate: t('WORKSPACE_SETTINGS.THEMES.SOLID_SLATE'),
}));

const swatchClass = selected =>
  selected
    ? 'ring-2 ring-offset-2 ring-offset-n-background ring-n-brand'
    : 'ring-1 ring-n-weak hover:ring-n-strong';

onMounted(fetchWorkspace);
</script>

<template>
  <SectionLayout
    :title="t('WORKSPACE_SETTINGS.TITLE')"
    :description="t('WORKSPACE_SETTINGS.NOTE')"
    with-border
  >
    <div class="grid gap-8">
      <div
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
        :aria-label="t('WORKSPACE_SETTINGS.PREVIEW')"
      >
        <WorkspaceCover :account="preview" class="h-32" />
        <div class="flex items-end gap-4 px-5 pb-5">
          <WorkspaceAvatar
            :account="preview"
            size="lg"
            class="-mt-8 ring-4 ring-n-solid-1 shadow-md"
          />
          <div class="min-w-0 flex-1">
            <p
              class="text-base font-semibold leading-6 text-n-slate-12 break-words"
            >
              {{ currentAccount.name }}
            </p>
            <p class="flex items-center gap-1 text-xs text-n-slate-11">
              <Icon icon="i-lucide-briefcase" class="size-3.5" />
              {{ verticalName || t('WORKSPACE_SETTINGS.VERTICAL.NONE') }}
            </p>
          </div>
        </div>
      </div>

      <div class="grid gap-3">
        <h5 class="text-sm font-medium text-n-slate-12">
          {{ t('WORKSPACE_SETTINGS.COVER.TITLE') }}
        </h5>
        <div class="flex flex-wrap items-center gap-3">
          <button
            type="button"
            class="flex items-center gap-2 rounded-xl px-2 py-1.5 transition"
            :class="swatchClass(!coverTheme)"
            :aria-pressed="!coverTheme"
            :title="t('WORKSPACE_SETTINGS.COVER.AUTO_HINT')"
            @click="chooseTheme(null)"
          >
            <span
              class="grid size-7 place-content-center rounded-lg"
              :class="autoClass"
            >
              <Icon icon="i-lucide-sparkles" class="size-4 text-white" />
            </span>
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('WORKSPACE_SETTINGS.COVER.AUTO') }}
            </span>
          </button>
        </div>
        <p class="text-xs text-n-slate-11">
          {{ t('WORKSPACE_SETTINGS.COVER.GRADIENTS') }}
        </p>
        <div class="flex flex-wrap gap-3">
          <button
            v-for="theme in GRADIENT_THEMES"
            :key="theme"
            type="button"
            class="grid h-10 w-16 place-content-center rounded-xl transition"
            :class="[COVER_THEMES[theme], swatchClass(coverTheme === theme)]"
            :aria-pressed="coverTheme === theme"
            :aria-label="THEME_LABELS[theme]"
            :title="THEME_LABELS[theme]"
            @click="chooseTheme(theme)"
          >
            <Icon
              v-if="coverTheme === theme"
              icon="i-lucide-check"
              class="size-4 text-white drop-shadow"
            />
          </button>
        </div>
        <p class="text-xs text-n-slate-11">
          {{ t('WORKSPACE_SETTINGS.COVER.SOLIDS') }}
        </p>
        <div class="flex flex-wrap gap-3">
          <button
            v-for="theme in SOLID_THEMES"
            :key="theme"
            type="button"
            class="grid size-10 place-content-center rounded-full transition"
            :class="[COVER_THEMES[theme], swatchClass(coverTheme === theme)]"
            :aria-pressed="coverTheme === theme"
            :aria-label="THEME_LABELS[theme]"
            :title="THEME_LABELS[theme]"
            @click="chooseTheme(theme)"
          >
            <Icon
              v-if="coverTheme === theme"
              icon="i-lucide-check"
              class="size-4 text-white drop-shadow"
            />
          </button>
        </div>
        <div class="flex flex-wrap items-center gap-2 pt-1">
          <NextButton
            faded
            slate
            sm
            icon="i-lucide-image-up"
            :is-loading="savingKey === 'cover'"
            :label="
              currentAccount.cover_url
                ? t('WORKSPACE_SETTINGS.COVER.REPLACE')
                : t('WORKSPACE_SETTINGS.COVER.UPLOAD')
            "
            @click="coverInput.click()"
          />
          <NextButton
            v-if="currentAccount.cover_url"
            ghost
            ruby
            sm
            icon="i-lucide-trash-2"
            :is-loading="savingKey === 'remove-cover'"
            :label="t('WORKSPACE_SETTINGS.COVER.REMOVE')"
            @click="remove('cover')"
          />
          <input
            ref="coverInput"
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            class="hidden"
            @change="upload('cover', $event)"
          />
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t('WORKSPACE_SETTINGS.COVER.IMAGE_HINT') }}
        </p>
      </div>

      <div class="grid gap-3">
        <h5 class="text-sm font-medium text-n-slate-12">
          {{ t('WORKSPACE_SETTINGS.LOGO.TITLE') }}
        </h5>
        <div class="flex flex-wrap items-center gap-3">
          <WorkspaceAvatar :account="preview" />
          <NextButton
            faded
            slate
            sm
            icon="i-lucide-upload"
            :is-loading="savingKey === 'logo'"
            :label="t('WORKSPACE_SETTINGS.LOGO.UPLOAD')"
            @click="logoInput.click()"
          />
          <NextButton
            v-if="currentAccount.logo_url"
            ghost
            ruby
            sm
            icon="i-lucide-trash-2"
            :is-loading="savingKey === 'remove-logo'"
            :label="t('WORKSPACE_SETTINGS.LOGO.REMOVE')"
            @click="remove('logo')"
          />
          <input
            ref="logoInput"
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            class="hidden"
            @change="upload('logo', $event)"
          />
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t('WORKSPACE_SETTINGS.LOGO.HINT') }}
        </p>
      </div>

      <div class="grid gap-3">
        <div>
          <h5 class="text-sm font-medium text-n-slate-12">
            {{ t('WORKSPACE_SETTINGS.VERTICAL.TITLE') }}
          </h5>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ t('WORKSPACE_SETTINGS.VERTICAL.NOTE') }}
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <select
            v-model="chosenVertical"
            class="!mb-0 text-sm max-w-xs"
            :aria-label="t('WORKSPACE_SETTINGS.VERTICAL.TITLE')"
          >
            <option value="" disabled>
              {{ t('WORKSPACE_SETTINGS.VERTICAL.PLACEHOLDER') }}
            </option>
            <option
              v-for="vertical in verticals"
              :key="vertical.key"
              :value="vertical.key"
            >
              {{ vertical.name }}
            </option>
          </select>
          <span
            v-if="chosenVertical && chosenVertical === currentVertical"
            class="inline-flex items-center gap-1 rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
          >
            <Icon icon="i-lucide-check" class="size-3.5" />
            {{ t('WORKSPACE_SETTINGS.VERTICAL.APPLIED') }}
          </span>
          <NextButton
            v-else-if="chosenVertical"
            sm
            icon="i-lucide-wand-sparkles"
            :is-loading="savingKey === 'vertical'"
            :label="t('WORKSPACE_SETTINGS.VERTICAL.APPLY')"
            @click="applyVertical"
          />
        </div>
        <p
          v-if="chosenVertical && chosenVertical !== currentVertical"
          class="text-xs text-n-amber-11"
        >
          {{
            t('WORKSPACE_SETTINGS.VERTICAL.CONFIRM', {
              name: chosenVerticalName,
            })
          }}
        </p>
      </div>
    </div>
  </SectionLayout>
</template>

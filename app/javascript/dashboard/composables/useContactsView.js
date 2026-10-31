import { computed } from 'vue';
import { useBreakpoints } from '@vueuse/core';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';

const LIST = 'list';
const CARDS = 'cards';

// How this user likes the contacts page, kept in ui_settings. The fields are
// stored as what was hidden, so an attribute created later shows up by itself.
export function useContactsView() {
  const { uiSettings, updateUISettings } = useUISettings();
  const { currentAccount } = useAccount();

  const settings = computed(() => uiSettings.value?.contacts_view || {});
  const save = change =>
    updateUISettings({ contacts_view: { ...settings.value, ...change } });

  // A wide table does not fit a phone, whatever was picked on the desktop.
  const isPhone = useBreakpoints({ sm: 640 }).smaller('sm');
  const viewMode = computed(() =>
    isPhone.value ? CARDS : settings.value.mode || LIST
  );

  const hiddenFields = computed(() => settings.value.hidden || []);
  const belezakiAvailable = computed(
    () => !!currentAccount.value?.vertical_profile?.belezaki
  );
  const belezakiEnabled = computed(
    () => belezakiAvailable.value && !!settings.value.belezaki
  );

  const isFieldVisible = field =>
    !hiddenFields.value.includes(field.key) &&
    (!field.belezaki || belezakiEnabled.value);

  const toggleField = ({ key }) => {
    const hidden = hiddenFields.value.includes(key)
      ? hiddenFields.value.filter(item => item !== key)
      : [...hiddenFields.value, key];
    save({ hidden });
  };

  return {
    viewMode,
    isPhone,
    hiddenFields,
    belezakiAvailable,
    belezakiEnabled,
    isFieldVisible,
    toggleField,
    setViewMode: mode => save({ mode }),
    setBelezakiEnabled: belezaki => save({ belezaki }),
    showAllFields: () => save({ hidden: [] }),
  };
}

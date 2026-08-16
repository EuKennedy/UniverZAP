<script setup>
/**
 * O perfil público do número: foto, nome e recado.
 *
 * Cada campo salva sozinho e mostra o erro que a API devolveu no próprio
 * campo. Um formulário com um botão único esconderia qual das três chamadas à
 * WAHA falhou, e o operador ficaria sem saber o que refazer.
 */
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import WhatsAppProfileAPI from 'dashboard/api/whatsappProfile';
import { apiErrorMessage } from '../helpers';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  inboxId: { type: Number, required: true },
});

const { t } = useI18n();

const isLoading = ref(false);
const loadError = ref('');
const picture = ref('');
const name = ref('');
const about = ref('');
const savingField = ref('');
const fieldError = ref({ name: '', about: '', picture: '' });
const fileInput = ref(null);

const label = key => t(`WHATSAPP_PROFILE.PROFILE.${key}`);
const fallback = () => t('WHATSAPP_PROFILE.ERRORS.GENERIC');

const fetchProfile = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await WhatsAppProfileAPI.profile(props.inboxId);
    picture.value = data.picture || '';
    name.value = data.name || '';
    // A WAHA não devolve o recado no GET do perfil, então o campo começa vazio
    // e serve para escrever um novo. Ver o atual continua sendo no celular.
    about.value = '';
  } catch (error) {
    loadError.value = apiErrorMessage(error, fallback());
  } finally {
    isLoading.value = false;
  }
};

const save = async (field, request, successKey) => {
  savingField.value = field;
  fieldError.value = { ...fieldError.value, [field]: '' };
  try {
    await request();
    useAlert(label(successKey));
  } catch (error) {
    fieldError.value = {
      ...fieldError.value,
      [field]: apiErrorMessage(error, fallback()),
    };
  } finally {
    savingField.value = '';
  }
};

const saveName = () =>
  save(
    'name',
    () => WhatsAppProfileAPI.updateName(props.inboxId, name.value.trim()),
    'NAME_SAVED'
  );

const saveAbout = () =>
  save(
    'about',
    () => WhatsAppProfileAPI.updateAbout(props.inboxId, about.value.trim()),
    'ABOUT_SAVED'
  );

const removePicture = () =>
  save(
    'picture',
    async () => {
      await WhatsAppProfileAPI.deletePicture(props.inboxId);
      picture.value = '';
    },
    'PICTURE_REMOVED'
  );

const openFileDialog = () => fileInput.value?.click();

const handleFileChange = async () => {
  const file = fileInput.value?.files?.[0];
  if (!file) return;

  await save(
    'picture',
    async () => {
      const { blobId } = await uploadFile(file);
      await WhatsAppProfileAPI.updatePicture(props.inboxId, blobId);
      await fetchProfile();
    },
    'PICTURE_SAVED'
  );

  if (fileInput.value) fileInput.value.value = null;
};

watch(() => props.inboxId, fetchProfile, { immediate: true });
</script>

<template>
  <section
    class="flex flex-col gap-6 p-6 rounded-xl border border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-base font-medium text-n-slate-12">
        {{ label('TITLE') }}
      </h2>
      <p class="m-0 text-[13px] text-n-slate-11">
        {{ label('DESCRIPTION') }}
      </p>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <Spinner :size="20" />
    </div>

    <p
      v-else-if="loadError"
      class="m-0 text-[13px] text-n-ruby-11"
      data-testid="profile-load-error"
    >
      {{ loadError }}
    </p>

    <template v-else>
      <div class="flex gap-4 items-center">
        <img
          v-if="picture"
          :src="picture"
          :alt="label('PICTURE')"
          class="object-cover rounded-full size-16 border border-n-weak"
        />
        <span
          v-else
          class="flex justify-center items-center rounded-full size-16 bg-n-alpha-2 text-n-slate-11"
        >
          <span class="i-lucide-user-round size-6" />
        </span>

        <div class="flex flex-col gap-2 items-start">
          <div class="flex gap-2">
            <Button
              slate
              faded
              size="sm"
              :label="label('CHANGE_PICTURE')"
              :is-loading="savingField === 'picture'"
              @click="openFileDialog"
            />
            <Button
              v-if="picture"
              ghost
              slate
              size="sm"
              :label="label('REMOVE_PICTURE')"
              @click="removePicture"
            />
          </div>
          <p
            v-if="fieldError.picture"
            class="m-0 text-[12px] text-n-ruby-11"
            data-testid="picture-error"
          >
            {{ fieldError.picture }}
          </p>
        </div>

        <input
          ref="fileInput"
          type="file"
          accept="image/jpeg,image/png,image/webp"
          class="hidden"
          @change="handleFileChange"
        />
      </div>

      <div class="flex flex-col gap-2">
        <Input
          v-model="name"
          :label="label('NAME')"
          :placeholder="label('NAME_PLACEHOLDER')"
          :message="fieldError.name"
          :message-type="fieldError.name ? 'error' : 'info'"
        />
        <Button
          class="self-end"
          size="sm"
          :label="label('SAVE')"
          :is-loading="savingField === 'name'"
          :disabled="!name.trim()"
          @click="saveName"
        />
      </div>

      <div class="flex flex-col gap-2">
        <TextArea
          v-model="about"
          :label="label('ABOUT')"
          :placeholder="label('ABOUT_PLACEHOLDER')"
          :max-length="139"
          show-character-count
          :message="fieldError.about"
          :message-type="fieldError.about ? 'error' : 'info'"
        />
        <p class="m-0 text-[12px] leading-relaxed text-n-slate-11">
          {{ label('ABOUT_HINT') }}
        </p>
        <Button
          class="self-end"
          size="sm"
          :label="label('SAVE')"
          :is-loading="savingField === 'about'"
          :disabled="!about.trim()"
          @click="saveAbout"
        />
      </div>
    </template>
  </section>
</template>

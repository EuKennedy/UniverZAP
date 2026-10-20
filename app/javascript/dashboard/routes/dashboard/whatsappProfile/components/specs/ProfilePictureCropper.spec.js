import { mount, flushPromises } from '@vue/test-utils';
import ProfilePictureCropper from '../ProfilePictureCropper.vue';

const cropToSquareFile = vi.fn();

vi.mock('../../helpers', async importOriginal => ({
  ...(await importOriginal()),
  cropToSquareFile: (...a) => cropToSquareFile(...a),
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Dialog: {
    props: ['disableConfirmButton'],
    emits: ['confirm'],
    data: () => ({ isOpen: false }),
    methods: {
      open() {
        this.isOpen = true;
      },
      close() {
        this.isOpen = false;
      },
    },
    template:
      '<div v-if="isOpen" data-testid="cropper-dialog"><slot />' +
      '<button data-testid="confirm" :disabled="disableConfirmButton" @click="$emit(\'confirm\')">ok</button></div>',
  },
};

// jsdom não decodifica imagens: a Image falsa "carrega" na hora com um
// tamanho conhecido, que é o que o recorte precisa.
class FakeImage {
  naturalWidth = 1200;

  naturalHeight = 800;

  set src(_value) {
    setTimeout(() => this.onload?.());
  }
}

describe('ProfilePictureCropper.vue', () => {
  beforeEach(() => {
    vi.stubGlobal('Image', FakeImage);
    window.URL.createObjectURL = vi.fn(() => 'blob:preview');
    cropToSquareFile.mockResolvedValue(new File(['x'], 'foto.jpg'));
  });

  afterEach(() => vi.unstubAllGlobals());

  it('starts on the centred square and hands back the cropped file', async () => {
    const wrapper = mount(ProfilePictureCropper, { global: { stubs } });

    wrapper.vm.open(new File(['y'], 'foto.png', { type: 'image/png' }));
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    await flushPromises();

    await wrapper.find('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    expect(cropToSquareFile).toHaveBeenCalledWith(
      expect.any(FakeImage),
      { size: 800, x: 200, y: 0 },
      'foto.jpg'
    );
    expect(wrapper.emitted('confirm')[0][0].name).toBe('foto.jpg');
  });

  it('zooms into the picture', async () => {
    const wrapper = mount(ProfilePictureCropper, { global: { stubs } });
    wrapper.vm.open(new File(['y'], 'foto.png', { type: 'image/png' }));
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    await flushPromises();

    await wrapper.find('[data-testid="cropper-zoom"]').setValue('2');
    await wrapper.find('[data-testid="confirm"]').trigger('click');
    await flushPromises();

    expect(cropToSquareFile.mock.calls.at(-1)[1]).toEqual({
      size: 400,
      x: 400,
      y: 200,
    });
  });
});

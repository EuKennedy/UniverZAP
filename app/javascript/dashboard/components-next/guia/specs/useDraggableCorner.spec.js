import { createApp } from 'vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { useDraggableCorner } from '../useDraggableCorner';

vi.mock('shared/helpers/localStorage', () => {
  const store = new Map();
  return {
    LocalStorage: {
      get: key => (store.has(key) ? store.get(key) : null),
      set: (key, value) => store.set(key, value),
      reset: () => store.clear(),
    },
  };
});

// A composable lê window e localStorage direto; montar um componente só para
// exercitá-la esconderia justamente o que interessa testar.
const withSetup = composable => {
  let result;
  const app = createApp({
    setup() {
      result = composable();
      return () => null;
    },
  });
  app.mount(document.createElement('div'));
  return [result, app];
};

const press = (x, y) =>
  new PointerEvent('pointerdown', { clientX: x, clientY: y, button: 0 });
const move = (x, y) =>
  window.dispatchEvent(
    new PointerEvent('pointermove', { clientX: x, clientY: y })
  );
const release = () => window.dispatchEvent(new PointerEvent('pointerup'));

describe('useDraggableCorner', () => {
  beforeEach(() => {
    LocalStorage.reset();
    window.innerWidth = 1200;
    window.innerHeight = 800;
  });

  it('nasce no canto de fábrica', () => {
    const [{ offsetStyle }] = withSetup(useDraggableCorner);

    expect(offsetStyle.value.transform).toBe('translate(0px, 0px)');
  });

  // Arrastar para a esquerda e para cima afasta do canto: o botão está ancorado
  // em bottom/right, então o deslocamento anda ao contrário do ponteiro.
  it('move a estrela na direção em que o ponteiro foi', () => {
    const [{ offsetStyle, onPointerDown }] = withSetup(useDraggableCorner);

    onPointerDown(press(1000, 700));
    move(900, 600);

    expect(offsetStyle.value.transform).toBe('translate(-100px, -100px)');
  });

  // Sem o piso, o clique de abrir o painel viraria um arrasto de dois pixels.
  it('ignora tremida de mão em cima do botão', () => {
    const [{ offsetStyle, isDragging, onPointerDown }] =
      withSetup(useDraggableCorner);

    onPointerDown(press(1000, 700));
    move(998, 699);

    expect(isDragging.value).toBe(false);
    expect(offsetStyle.value.transform).toBe('translate(0px, 0px)');
  });

  // Uma estrela arrastada para fora da tela é uma ajuda que ninguém alcança de
  // volta sem limpar o navegador.
  it('não deixa a estrela sair da tela', () => {
    const [{ offsetStyle, onPointerDown }] = withSetup(useDraggableCorner);

    onPointerDown(press(1000, 700));
    move(-5000, -5000);

    expect(offsetStyle.value.transform).toBe('translate(-1144px, -744px)');
  });

  it('lembra a posição no navegador depois de soltar', () => {
    const [{ onPointerDown }] = withSetup(useDraggableCorner);

    onPointerDown(press(1000, 700));
    move(900, 650);
    release();

    expect(LocalStorage.get('guia-launcher-offset')).toEqual({ x: 100, y: 50 });
  });

  it('abre na posição que foi guardada', () => {
    LocalStorage.set('guia-launcher-offset', { x: 120, y: 60 });

    const [{ offsetStyle }] = withSetup(useDraggableCorner);

    expect(offsetStyle.value.transform).toBe('translate(-120px, -60px)');
  });
});

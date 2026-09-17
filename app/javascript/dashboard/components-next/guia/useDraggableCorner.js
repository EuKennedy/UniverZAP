import { ref, computed, onBeforeUnmount } from 'vue';
import { LocalStorage } from 'shared/helpers/localStorage';

/**
 * Arrastar a estrela para fora do caminho.
 *
 * Ela fica no canto inferior direito, que é onde muita tela põe botão de ação,
 * e uma ajuda que tapa o clique de quem estava trabalhando é estorvo. Segurar e
 * arrastar tira ela dali.
 *
 * O deslocamento é guardado por NAVEGADOR e não no servidor: a posição boa num
 * monitor de 27" tapa outra coisa num notebook, e sincronizar entre aparelhos
 * levaria o estorvo junto. É conveniência de quem está ali, não configuração.
 */
const STORAGE_KEY = 'guia-launcher-offset';
// Abaixo disto é tremida de mão em cima do botão, não intenção de mover — e sem
// esse piso o clique de abrir o painel vira um arrasto de dois pixels que não
// abre nada.
const DRAG_THRESHOLD_PX = 4;
// A estrela nunca pode sair da tela: sem isto uma janela redimensionada depois
// do arrasto deixa a ajuda num canto que ninguém alcança, e não há como trazê-la
// de volta a não ser limpando o navegador.
const EDGE_MARGIN_PX = 8;
const BUTTON_SIZE_PX = 48;

const readStored = () => {
  // Navegador anônimo, armazenamento bloqueado, valor de uma versão anterior: em
  // qualquer um deles a estrela volta para o canto de fábrica, que é um lugar
  // perfeitamente utilizável.
  const raw = LocalStorage.get(STORAGE_KEY);
  const valid = raw && Number.isFinite(raw.x) && Number.isFinite(raw.y);
  return valid ? { x: raw.x, y: raw.y } : { x: 0, y: 0 };
};

export const useDraggableCorner = () => {
  const offset = ref(readStored());
  const isDragging = ref(false);

  let origin = null;

  // Limites medidos a partir do canto de origem: `x` só cresce para a esquerda
  // e `y` só para cima, porque o botão está ancorado em bottom/right.
  const clamp = ({ x, y }) => ({
    x: Math.min(
      Math.max(x, 0),
      Math.max(window.innerWidth - BUTTON_SIZE_PX - EDGE_MARGIN_PX, 0)
    ),
    y: Math.min(
      Math.max(y, 0),
      Math.max(window.innerHeight - BUTTON_SIZE_PX - EDGE_MARGIN_PX, 0)
    ),
  });

  const onPointerMove = event => {
    if (!origin) return;
    const next = clamp({
      x: origin.x + (origin.pointerX - event.clientX),
      y: origin.y + (origin.pointerY - event.clientY),
    });
    if (
      !isDragging.value &&
      Math.abs(next.x - origin.x) < DRAG_THRESHOLD_PX &&
      Math.abs(next.y - origin.y) < DRAG_THRESHOLD_PX
    ) {
      return;
    }
    isDragging.value = true;
    offset.value = next;
  };

  const stop = () => {
    window.removeEventListener('pointermove', onPointerMove);
    window.removeEventListener('pointerup', stop);
    window.removeEventListener('pointercancel', stop);
    origin = null;
    // Não poder lembrar a posição não é motivo para não deixar mover agora.
    if (isDragging.value) LocalStorage.set(STORAGE_KEY, offset.value);
    // Um quadro depois, para o clique que fecha o arrasto não abrir o painel.
    requestAnimationFrame(() => {
      isDragging.value = false;
    });
  };

  const onPointerDown = event => {
    // Só botão principal: o direito abre menu de contexto e o do meio cola.
    if (event.button !== 0) return;
    origin = {
      ...offset.value,
      pointerX: event.clientX,
      pointerY: event.clientY,
    };
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', stop);
    window.addEventListener('pointercancel', stop);
  };

  onBeforeUnmount(stop);

  const offsetStyle = computed(() => ({
    transform: `translate(${-offset.value.x}px, ${-offset.value.y}px)`,
  }));

  return { offsetStyle, isDragging, onPointerDown };
};

export default useDraggableCorner;

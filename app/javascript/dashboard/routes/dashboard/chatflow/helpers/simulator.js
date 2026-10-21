// O simulador não guarda estado no servidor: a cada resposta o editor manda
// todas as falas da cliente desde o começo e recebe o roteiro inteiro.
export const newSeed = () => Math.floor(Math.random() * 1_000_000_000);

export const userInputs = transcript =>
  (transcript || [])
    .filter(line => line.type === 'user')
    .map(line => line.text);

// Eventos do roteiro que viram uma linha discreta no chat simulado.
export const EVENT_ICONS = {
  waited: 'i-lucide-hourglass',
  typed: 'i-lucide-ellipsis',
  skipped_webhook: 'i-lucide-webhook',
  skipped_flow: 'i-lucide-clipboard-list',
  ended: 'i-lucide-flag',
};

export const isFinished = result => Boolean(result?.finished);

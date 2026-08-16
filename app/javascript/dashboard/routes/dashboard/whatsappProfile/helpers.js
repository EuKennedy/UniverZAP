/**
 * A mensagem de erro na ordem em que ela é útil para quem está na tela: o que
 * o WhatsApp respondeu vem primeiro, depois a falha de rede, e só no fim um
 * texto genérico. Nunca "algo deu errado" quando existe um motivo real para
 * mostrar, porque é o motivo que diz de quem é a próxima ação.
 */
export const apiErrorMessage = (error, fallback = '') =>
  error?.response?.data?.error || error?.message || fallback;

/**
 * As cores de fundo que o WhatsApp usa no status de texto. A WAHA aceita
 * qualquer hexadecimal, mas oferecer a paleta certa evita status com cara de
 * coisa feita por engano.
 */
export const STATUS_BACKGROUNDS = [
  '#0A5F55',
  '#1F7A3D',
  '#B03A2E',
  '#8E44AD',
  '#1B4F72',
  '#B9770E',
  '#2C3E50',
];

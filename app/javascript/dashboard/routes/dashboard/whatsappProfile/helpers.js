/**
 * A mensagem de erro na ordem em que ela é útil para quem está na tela: o que
 * o WhatsApp respondeu vem primeiro, depois a validação do servidor, depois a
 * falha de rede, e só no fim um texto genérico. Nunca "algo deu errado" quando
 * existe um motivo real para mostrar, porque é o motivo que diz de quem é a
 * próxima ação.
 */
export const apiErrorMessage = (error, fallback = '') =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallback;

/**
 * As cores de fundo que o WhatsApp usa no status de texto. A WAHA aceita
 * qualquer hexadecimal, mas oferecer a paleta certa evita status com cara de
 * coisa feita por engano.
 */
//
// A classe vem escrita por extenso para o Tailwind enxergar no build; é ela
// que pinta a prévia sem estilo inline.
export const STATUS_BACKGROUNDS = [
  { value: '#0A5F55', className: 'bg-[#0A5F55]' },
  { value: '#1F7A3D', className: 'bg-[#1F7A3D]' },
  { value: '#B03A2E', className: 'bg-[#B03A2E]' },
  { value: '#8E44AD', className: 'bg-[#8E44AD]' },
  { value: '#1B4F72', className: 'bg-[#1B4F72]' },
  { value: '#B9770E', className: 'bg-[#B9770E]' },
  { value: '#2C3E50', className: 'bg-[#2C3E50]' },
];

export const backgroundClass = value =>
  (
    STATUS_BACKGROUNDS.find(
      color => color.value.toLowerCase() === String(value).toLowerCase()
    ) || STATUS_BACKGROUNDS[0]
  ).className;

/**
 * As fontes do status de texto, pelo número que a WAHA repassa ao WhatsApp. O
 * painel não tem as fontes do aplicativo, então a pré-visualização usa a
 * família Tailwind mais próxima: serve para escolher, não é pixel a pixel.
 */
export const STATUS_FONTS = [
  { value: 0, key: 'SANS', previewClass: 'font-sans' },
  { value: 1, key: 'SERIF', previewClass: 'font-serif' },
  { value: 2, key: 'SCRIPT', previewClass: 'font-serif italic' },
  { value: 3, key: 'HANDWRITTEN', previewClass: 'font-sans italic' },
  {
    value: 4,
    key: 'CONDENSED',
    previewClass: 'font-sans uppercase tracking-wide',
  },
  { value: 5, key: 'HEAVY', previewClass: 'font-sans font-black uppercase' },
];

export const fontPreviewClass = value =>
  (STATUS_FONTS.find(font => font.value === value) || STATUS_FONTS[0])
    .previewClass;

export const STATUS_TEXT_LIMIT = 700;

/** Valor de <input type="datetime-local"> no fuso do navegador. */
export const toLocalInputValue = date => {
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

/**
 * Recorta o quadrado escolhido e devolve um JPEG pronto para a foto de perfil.
 * O WhatsApp corta a foto em círculo a partir do centro; mandar já quadrada
 * garante que sai exatamente o enquadramento que o operador viu.
 *
 * `crop` está em pixels da imagem original: { x, y, size }.
 */
export const PROFILE_PICTURE_SIZE = 640;

export const cropToSquareFile = (image, crop, filename = 'profile.jpg') =>
  new Promise((resolve, reject) => {
    const canvas = document.createElement('canvas');
    canvas.width = PROFILE_PICTURE_SIZE;
    canvas.height = PROFILE_PICTURE_SIZE;
    const context = canvas.getContext('2d');
    context.drawImage(
      image,
      crop.x,
      crop.y,
      crop.size,
      crop.size,
      0,
      0,
      PROFILE_PICTURE_SIZE,
      PROFILE_PICTURE_SIZE
    );
    canvas.toBlob(
      blob =>
        blob
          ? resolve(new File([blob], filename, { type: 'image/jpeg' }))
          : reject(new Error('crop failed')),
      'image/jpeg',
      0.9
    );
  });

/**
 * O quadrado de recorte para um zoom (1 = o maior quadrado que cabe) e um
 * deslocamento do centro em fração (-1..1) da folga disponível em cada eixo.
 */
export const squareCrop = (
  { width, height },
  zoom = 1,
  offset = { x: 0, y: 0 }
) => {
  const size = Math.min(width, height) / zoom;
  const slackX = (width - size) / 2;
  const slackY = (height - size) / 2;
  return {
    size,
    x: slackX + offset.x * slackX,
    y: slackY + offset.y * slackY,
  };
};

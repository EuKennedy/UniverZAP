/**
 * O vocabulário visual do moderador: gravidade, relógio e dinheiro.
 *
 * Separado de managerFormat.js de propósito. Os dois painéis moram na mesma
 * tela mas medem coisas diferentes: lá a gravidade é de um HÁBITO do agente e
 * varia entre dois estados, aqui é de uma PESSOA esperando e varia com o
 * relógio. Juntar os dois num arquivo só faria a próxima mudança em um deles
 * mexer sem querer no outro.
 */

export const SEVERITIES = ['critical', 'high', 'medium', 'low'];

/**
 * Cor, ícone e barra lateral de cada gravidade.
 *
 * O ícone muda junto com a cor, e não é enfeite: quem não separa vermelho de
 * âmbar precisa ver a diferença de outro jeito, e a barra na lateral esquerda
 * dá a terceira pista para quem varre a lista com o olho.
 */
const SEVERITY_STYLES = {
  critical: {
    rail: 'border-l-n-ruby-9',
    chip: 'bg-n-ruby-3 text-n-ruby-11 ring-n-ruby-6',
    icon: 'i-lucide-alert-triangle',
  },
  high: {
    rail: 'border-l-n-amber-9',
    chip: 'bg-n-amber-3 text-n-amber-11 ring-n-amber-6',
    icon: 'i-lucide-alert-circle',
  },
  medium: {
    rail: 'border-l-n-slate-8',
    chip: 'bg-n-alpha-2 text-n-slate-11 ring-n-weak',
    icon: 'i-lucide-circle-dot',
  },
  low: {
    rail: 'border-l-n-slate-6',
    chip: 'bg-n-alpha-2 text-n-slate-11 ring-n-weak',
    icon: 'i-lucide-circle',
  },
};

export const severityStyle = severity =>
  SEVERITY_STYLES[severity] || SEVERITY_STYLES.medium;

/**
 * "há 31 horas", "há 3 dias".
 *
 * Em horas até dois dias porque é assim que o operador pensa nesta tela: saber
 * se a pessoa está esperando desde antes do almoço ou desde ontem muda o que
 * ele faz agora, e "há 1,3 dias" obriga a fazer a conta de cabeça.
 */
export const timeAgo = value => {
  if (!value) return '';
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return '';

  const minutes = Math.round((Date.now() - then) / 60000);
  if (minutes < 60) return `há ${Math.max(minutes, 1)} min`;

  const hours = Math.round(minutes / 60);
  if (hours < 48) return `há ${hours}h`;

  return `há ${Math.round(hours / 24)} dias`;
};

const currency = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

export const money = value => currency.format(Number(value) || 0);

/**
 * Quantos centavos a leitura custou, em reais.
 *
 * Mostrado sempre, inclusive quando é zero: um botão que gasta e não diz
 * quanto gastou é um botão que o operador clica uma vez e nunca mais.
 */
export const centsToBRL = cents => money((Number(cents) || 0) / 100);

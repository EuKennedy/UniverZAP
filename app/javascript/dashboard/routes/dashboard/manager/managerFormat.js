/**
 * O que os números e os campos do Gerente viram na tela, em um lugar só.
 *
 * A formatação e a regra de cor da variação vêm de Relatórios e não são
 * reescritas aqui: as três notas do topo desta tela são irmãs das do painel de
 * IA, e duas cópias da mesma regra divergiriam na primeira mudança.
 */
import {
  formatNumber,
  formatBrlFromCents,
  buildTrend,
  RISING_IS_GOOD,
  RISING_MEANS_NOTHING,
} from 'dashboard/routes/dashboard/settings/reports/components/athenas/summaryFormat';

const isBlank = value => value === null || value === undefined;

export const SEVERITY_CRITICAL = 'critical';
export const TARGET_TRAINING = 'training';
export const TARGET_PROMPT = 'prompt_version';

// Uma casa decimal, com vírgula. 92,4% é uma nota; 92.41379% é ruído com
// aparência de precisão, escrito ainda por cima como ninguém escreve em
// português. formatNumber já resolve as duas coisas e devolve travessão para
// ausente, que é o que a ausência de nota deve parecer.
const percent = value =>
  isBlank(value)
    ? formatNumber(null)
    : `${formatNumber(Math.round(value * 10) / 10)}%`;

/**
 * As três notas do topo, sempre nesta ordem e sempre as três.
 *
 * Uma média das três esconderia qual metade se mexeu: um agente que ficou mais
 * barato porque parou de responder subiria a nota única enquanto perde
 * dinheiro. Separadas, o operador vê a troca acontecendo.
 *
 * Custo fica sem cor de propósito, pela mesma razão que o painel de IA já
 * assume: gastar mais não é piorar se o agente também trabalhou mais, e pintar
 * de vermelho um custo que acompanhou a receita seria mentir com cor.
 */
const SCORE_SHAPE = {
  reliability: { format: percent, direction: RISING_IS_GOOD },
  conversion: { format: percent, direction: RISING_IS_GOOD },
  // Centavos, como todo dinheiro que este backend devolve.
  cost: { format: formatBrlFromCents, direction: RISING_MEANS_NOTHING },
};

export const SCORE_KEYS = Object.keys(SCORE_SHAPE);

export const buildScores = scores =>
  SCORE_KEYS.map(key => ({
    key,
    value: SCORE_SHAPE[key].format(scores?.[key]?.value),
    trend: buildTrend(scores, key, SCORE_SHAPE[key].direction),
  }));

const dateTime = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
});

/**
 * Uma data do backend virando texto, aceitando epoch em segundos ou ISO.
 *
 * As duas formas circulam neste produto (a fila de supervisão fala epoch, o
 * resto do painel fala ISO) e uma data ilegível na linha "última análise" é
 * pior que nenhuma: null some da tela, "Invalid Date" fica.
 */
export const formatMoment = value => {
  if (isBlank(value)) return null;
  const date =
    typeof value === 'number' ? new Date(value * 1000) : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return dateTime.format(date);
};

/**
 * O que exatamente vai mudar, em texto.
 *
 * Quando o backend manda um objeto que não conhecemos, o JSON cru aparece.
 * Feio, e ainda assim melhor que o operador clicar em aprovar sem ver o que
 * está aprovando: esconder o payload seria pedir um voto de confiança que a
 * tela inteira existe para não precisar pedir.
 */
export const proposedText = proposed => {
  if (isBlank(proposed)) return null;
  if (typeof proposed === 'string') return proposed;

  const known =
    proposed.content || proposed.text || proposed.instruction || proposed.body;
  if (typeof known === 'string') return known;

  return JSON.stringify(proposed, null, 2);
};

// Chave de métrica do backend virando algo que se lê em voz alta. Não traduz,
// só desfaz o snake_case: inventar tradução para chave que ainda não existe
// daria rótulo errado com cara de certo.
export const humanizeMetric = metric =>
  isBlank(metric) ? null : String(metric).replace(/_/g, ' ');

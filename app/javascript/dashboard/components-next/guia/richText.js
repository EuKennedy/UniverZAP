/**
 * O `**negrito**` que o modelo escreve, virando negrito de verdade.
 *
 * O Guia marca ênfase em markdown por hábito — é como todo modelo escreve — e
 * o painel mostrava os asteriscos crus, o que faz a resposta parecer quebrada
 * logo na primeira pergunta.
 *
 * Devolve PEDAÇOS e não HTML de propósito. O texto vem do modelo, e modelo
 * repete o que leu: uma resposta que cite o conteúdo de um treino pode trazer
 * `<script>` dentro, e `v-html` transformaria a base de conhecimento de um
 * tenant em execução de código na tela de quem perguntou. Com pedaços, o Vue
 * escapa cada um como texto e o `<strong>` é nosso, não do modelo.
 */
// `split` com grupo de captura em vez de laço sobre os casamentos: o corte já
// devolve os pedaços alternados — índice par é texto comum, ímpar é o que
// estava entre asteriscos — e não sobra estado de regex entre uma mensagem e a
// seguinte, que é como o negrito sairia deslocado na segunda resposta.
const BOLD = /\*\*([\s\S]+?)\*\*/;

export const toRichParts = content => {
  const text = String(content ?? '');
  const parts = text
    .split(BOLD)
    .map((piece, index) => ({ text: piece, bold: index % 2 === 1 }))
    // Um negrito colado no começo ou no fim deixa pedaço vazio dos dois lados.
    .filter(part => part.text !== '');

  // Sem marcação nenhuma a resposta continua sendo um pedaço só, e o template
  // não precisa saber a diferença.
  return parts.length ? parts : [{ text, bold: false }];
};

export default toRichParts;

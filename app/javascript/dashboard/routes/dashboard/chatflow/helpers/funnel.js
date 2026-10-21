// Funil por bloco: transforma a resposta de GET chatflows/:id/funnel num mapa
// por etapa com a taxa de quem seguiu adiante.
export const funnelByNode = report => {
  const rows = report?.nodes || [];
  return rows.reduce((acc, row) => {
    const entered = Number(row.entered) || 0;
    const passed = (Number(row.advanced) || 0) + (Number(row.completed) || 0);
    acc[String(row.node_id)] = {
      ...row,
      rate: entered ? Math.round((passed / entered) * 100) : null,
    };
    return acc;
  }, {});
};

// Cor da taxa: verde quando quase todo mundo passa, âmbar no meio, vermelho
// quando a etapa é um buraco no fluxo.
export const rateTone = rate => {
  if (rate === null || rate === undefined) return 'text-n-slate-10';
  if (rate >= 70) return 'text-n-teal-11';
  if (rate >= 40) return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

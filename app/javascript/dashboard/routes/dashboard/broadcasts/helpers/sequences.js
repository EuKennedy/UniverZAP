// Conversão entre o passo da tela ("1 dia antes") e o que o backend guarda
// (offset_minutes negativo = antes do horário agendado).
const MINUTES = { hours: 60, days: 24 * 60 };

export const stepToOffset = step => ({
  offset_minutes:
    Number(step.amount) *
    MINUTES[step.unit] *
    (step.direction === 'before' ? -1 : 1),
  text: step.text.trim(),
  cancel_if_reply: step.cancelIfReply,
});

export const offsetToStep = step => {
  const minutes = Math.abs(Number(step.offset_minutes) || 0);
  const unit = minutes % MINUTES.days === 0 ? 'days' : 'hours';
  return {
    amount: Math.max(1, Math.round(minutes / MINUTES[unit])),
    unit,
    direction: Number(step.offset_minutes) < 0 ? 'before' : 'after',
    text: step.text || '',
    cancelIfReply: step.cancel_if_reply !== false,
  };
};

// "1 dia antes", "2 h depois" — para o cartão da lista.
export const describeOffset = (step, t) => {
  const { amount, unit, direction } = offsetToStep(step);
  return t(
    `BROADCAST.SEQUENCES.OFFSET.${unit.toUpperCase()}_${direction.toUpperCase()}`,
    {
      count: amount,
    }
  );
};

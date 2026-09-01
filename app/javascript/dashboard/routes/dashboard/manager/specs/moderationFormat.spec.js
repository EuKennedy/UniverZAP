import { severityStyle, timeAgo, money, centsToBRL } from '../moderationFormat';

describe('timeAgo', () => {
  const ago = hours => new Date(Date.now() - hours * 3600 * 1000).toISOString();

  // Em horas até dois dias porque é assim que o operador pensa nesta tela:
  // saber se a pessoa espera desde antes do almoço ou desde ontem muda o que
  // ele faz agora, e "há 1,3 dias" obriga a fazer a conta de cabeça.
  it('fala em horas dentro de dois dias', () => {
    expect(timeAgo(ago(31))).toBe('há 31h');
  });

  it('vira dias só depois de dois dias', () => {
    expect(timeAgo(ago(72))).toBe('há 3 dias');
  });

  it('fala em minutos na primeira hora', () => {
    expect(timeAgo(ago(0.5))).toBe('há 30 min');
  });

  // Nunca "há 0 min": o achado recém-gravado tem que parecer recente, não
  // parecer um bug de arredondamento.
  it('nunca mostra zero', () => {
    expect(timeAgo(new Date().toISOString())).toBe('há 1 min');
  });

  it('não escreve nada quando não há data, em vez de mostrar Invalid Date', () => {
    expect(timeAgo(null)).toBe('');
    expect(timeAgo('nada disso')).toBe('');
  });
});

describe('money', () => {
  it('escreve em real, que é a moeda da tela inteira', () => {
    expect(money(900)).toContain('900,00');
    expect(money(900)).toContain('R$');
  });

  it('converte centavos sem perder o troco', () => {
    expect(centsToBRL(74)).toContain('0,74');
  });

  // Zero aparece, e não some. Um botão que gasta e não diz quanto gastou é um
  // botão que o operador clica uma vez e nunca mais.
  it('mostra zero em vez de vazio', () => {
    expect(centsToBRL(0)).toContain('0,00');
    expect(centsToBRL(undefined)).toContain('0,00');
  });
});

describe('severityStyle', () => {
  it('dá barra, cor e ícone diferentes para cada gravidade', () => {
    expect(severityStyle('critical').icon).toBe('i-lucide-alert-triangle');
    expect(severityStyle('high').icon).toBe('i-lucide-alert-circle');
    expect(severityStyle('critical').rail).not.toBe(severityStyle('high').rail);
  });

  // Gravidade desconhecida vinda do servidor não pode apagar o cartão da tela.
  it('cai num estilo neutro quando a gravidade é desconhecida', () => {
    expect(severityStyle('inventada')).toEqual(severityStyle('medium'));
  });
});

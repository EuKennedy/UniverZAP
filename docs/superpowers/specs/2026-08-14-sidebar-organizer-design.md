# Organizador do menu lateral — design

**Data:** 2026-08-14
**Status:** aprovado em conversa, pronto para o plano de implementação

## O problema

A barra lateral cresceu. Chatwoot já vinha grande e o UniverZAP somou Athenas,
Kanban, Funis e o resto. Um cliente novo abre o painel e não sabe onde clicar, e
nós não temos como arrumar isso sem editar código e subir deploy.

## O que estamos construindo

Uma tela no fim das **Configurações**, visível apenas para super admins, onde se
monta a barra lateral do produto: cria grupo, dá nome, coloca os itens dentro,
reordena, esconde o que não serve e renomeia o que precisa.

O layout é **global**: vale para todos os tenants da instalação. Não existe
layout por conta nem por usuário. Um super admin organiza, todo mundo vê.

## Decisões fechadas

**Escopo: global.** Guardado em `InstallationConfig`, que é onde a configuração
da instalação já mora. Sem tabela nova, sem coluna nova.

**Quem edita: super admin.** `SuperAdmin` é STI de `User` e `type` já viaja no
JSON do usuário, então a aba se esconde sozinha no front. O backend valida de
novo — front escondido não é autorização.

**Poderes: totais.** Reordenar, criar e nomear grupos, mover itens entre grupos,
esconder e renomear.

**Onde a tela mora: nas Configurações**, não no painel do Super Admin. É uma
incoerência assumida: uma tela que muda todos os tenants morando dentro de uma
conta. Vale porque o painel do Super Admin é Rails/ERB e o dashboard é Vue com o
design system pronto — o acabamento que queremos sai muito mais barato ali.

**Itens soltos continuam existindo.** A barra segue misturando item de topo e
grupo com dropdown. A Caixa de entrada é o item mais clicado do produto;
enterrá-la num dropdown cobra um clique por vez, o dia inteiro, de todo
atendente.

## A arquitetura: sobreposição, não substituição

O que fica salvo **não é o menu**. É a intenção do super admin sobre ele.

O código continua montando `menuItems` como monta hoje, com todas as condições
de permissão, plano e feature flag já aplicadas. Sobre esse resultado, aplica-se
a sobreposição salva.

```
menuItems (como hoje)  →  applyLayout(menu, layout)  →  o que a pessoa vê
```

A sobreposição é indexada pelo `name` estável que cada item já tem (`Inbox`,
`Conversation`, `Report`…), e diz três coisas por item: em qual grupo ele está,
em que posição, e como aparece (rótulo próprio, oculto ou não).

### Por que assim

O mesmo layout global é lido por milhares de pessoas com permissões diferentes.
Essa não é uma exceção a remendar; é a característica central da feature depois
que ela virou global. A sobreposição trata isso como o caso normal:

- Item que existe e não está na sobreposição **fica onde estava**. Uma aba nova
  que lançarmos e esquecermos de posicionar continua aparecendo — não some sem
  erro, sem log e sem ninguém descobrir.
- Item na sobreposição que **não existe para aquele usuário** é ignorado em
  silêncio. Um agente sem permissão de relatórios não vê buraco no menu.
- Um `name` que mudar no código não quebra a tela: vira um item desconhecido no
  layout, que a tela lista como "item que não existe mais" para o admin remover.

O custo assumido: o JSON salvo é menos legível a olho nu do que uma árvore
pronta, e a pré-visualização precisa rodar exatamente a mesma função que a
sidebar roda — senão ela mente. Resolvido extraindo `applyLayout` para um módulo
próprio, sem dependência de Vue, usado pelos dois e testado sozinho.

### O formato salvo

```json
{
  "version": 1,
  "groups": [
    { "id": "g_atendimento", "label": "Atendimento", "order": 0 },
    { "id": "g_gestao", "label": "Gestão", "order": 1 }
  ],
  "items": {
    "Inbox":        { "group": null, "order": 0 },
    "Conversation": { "group": "g_atendimento", "order": 0 },
    "Report":       { "group": "g_gestao", "order": 1, "hidden": true },
    "Athenas":      { "group": "g_gestao", "order": 0, "label": "Agente de IA" }
  }
}
```

`group: null` é item de topo. `id` de grupo é gerado por nós e nunca reaproveita
o `name` de um item, para que apagar um grupo jamais derrube um item junto.

`version` existe para o dia em que o formato mudar: o leitor sabe o que está
lendo e pode migrar em vez de adivinhar.

## As peças

**`applyLayout(menu, layout)`** — função pura, sem Vue, sem store. Recebe o menu
montado e a sobreposição, devolve o menu final. É onde mora toda a regra: item
desconhecido no fim do grupo de origem, item inexistente ignorado, oculto
removido, rótulo trocado. Testada isoladamente, e é o único lugar onde essa
lógica existe.

**`Sidebar.vue`** — passa a chamar `applyLayout` sobre o `menuItems` que já
computa. Mudança pequena e localizada; o arquivo já tem 962 linhas e não é hora
de reescrevê-lo.

**A tela do organizador** — construtor de grupos: cria, nomeia, adiciona itens
dentro, arrasta para reordenar. Ao lado, a pré-visualização rodando o mesmo
`applyLayout`.

**API** — `GET` e `PUT` de um recurso só, com o JSON inteiro. Não há edição
parcial: a tela sempre manda o layout completo. Salvar é uma operação, não seis.

**Autorização** — o controller exige super admin. A aba escondida no front é
conveniência, não segurança.

## Erros e casos de borda

**Layout inválido ou corrompido** → a sidebar renderiza o menu padrão. Um layout
quebrado não pode tirar o produto do ar; no pior caso o cliente vê o menu de
fábrica e o super admin conserta.

**Grupo vazio** (todos os itens escondidos ou indisponíveis para aquele usuário)
→ não renderiza. Grupo vazio no menu é um clique que não leva a lugar nenhum.

**Item renomeado** → o rótulo salvo substitui a tradução. Consequência aceita:
quem usa o painel em inglês lerá o texto em português. Registrado aqui porque é
uma escolha, não um descuido.

**Salvar concorrente** (dois super admins) → o último a salvar vence. Não vale
construir bloqueio para uma tela que dois humanos raramente abrem juntos.

## Testes

`applyLayout` carrega o peso: ordem respeitada, item desconhecido no fim do grupo
certo, item do layout que não existe ignorado, oculto removido, rótulo trocado,
grupo vazio suprimido, layout corrompido caindo no padrão.

Na tela, os casos que o usuário sente: criar grupo, mover item entre grupos,
esconder e ver sumir da prévia, e a aba não aparecendo para quem não é super
admin.

No backend, request specs: super admin salva, admin comum recebe 401, e o
layout volta igual ao que entrou.

## Fora de escopo

Layout por conta ou por usuário. Ícone customizado. Reordenar itens dentro de um
subgrupo de terceiro nível. Link externo no menu.

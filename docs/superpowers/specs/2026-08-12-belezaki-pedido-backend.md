# Pedido ao time do belezaki — o que a integração de agendamento por IA precisa

**Para:** o agente/dev que trabalha no repositório `belezaki`.
**De:** o time do UniverZAP, que está construindo o módulo que consome
`/api/agent/v1` para a IA de atendimento marcar na agenda real do salão.
**Base factual:** `MODULO_AGENDAMENTO_IA_SPEC.md` (levantado do código no commit
`49df107`). Todas as referências `arquivo:linha` abaixo vêm de lá.

Este documento pede mudanças **no repositório belezaki**. Nada aqui é sobre o UniverZAP.

---

## Instrução

Você vai receber pedidos em ordem de prioridade. Cada um traz o arquivo e a linha, o
sintoma que ele causa hoje, e o critério de aceite. Trate os itens **P0-1, P0-3 e P0-8
como um lote só**: são os três que produzem erro visível para o cliente final do salão, e
os três são pequenos e localizados.

Antes de escrever qualquer código, responda a **pergunta bloqueante** da seção 0. Ela
custa um curl e destrava (ou trava) tudo o mais.

---

## Regras inegociáveis

1. **`bookCore` continua sendo o motor único de criação.** Não crie um caminho paralelo
   de agendamento para a IA. O valor da arquitetura atual é que a API do agente é uma
   casca fina sobre o mesmo motor do site público — toda correção feita ali vale para os
   dois. Se um pedido parecer exigir um segundo motor, pare e nos consulte.

2. **Não altere o contrato das 6 rotas existentes sem nos avisar.** Nós já consumimos
   `/salon`, `/services`, `/professionals`, `/availability`, `/availability-month` e
   `POST /appointments`. Mudança de nome de campo, de shape ou de status quebra a IA em
   produção, no meio de conversas com clientes reais. Adicionar campo novo é seguro;
   renomear ou remover não é.

3. **Erro de negócio nunca pode virar 500.** Um 500 é indistinguível de queda para quem
   chama, e obriga a IA a tratar como transitório e repetir. Entrada inválida é 400.

4. **Não afrouxe a validação do slot.** A exigência de que `start` bata com um slot livre
   na precisão de milissegundo é o que impede a IA de inventar horário. Ela deve
   continuar exatamente como está.

5. **Toda escrita nova nasce idempotente.** Mesmo padrão de `idempotency_key` do
   `POST /appointments`. Sem isso, um timeout de rede vira ação duplicada na agenda de um
   cliente real.

6. **Rota nova de escrita precisa de escopo por telefone.** O agente só pode tocar
   agendamentos do cliente cujo telefone ele apresentou. Sem essa trava, a IA vira um
   vetor de cancelamento de agenda alheia.

7. **Não commite credencial.** `UNIVERZAP_AGENT_API_KEY`, `GOOGLE_CLIENT_ID` e
   `GOOGLE_CLIENT_SECRET` entram por variável de ambiente no Coolify.

8. **Toda correção desta lista precisa de teste.** Hoje **não existe nenhum teste tocando
   `/agent/v1`** — qualquer mudança de contrato passa despercebida. O arquivo é
   `agent.int-spec.ts`, a criar.

---

## 0. Pergunta bloqueante — a URL base real

O host `api.belezaki.com.br` não aparece em lugar nenhum do repositório; o roteamento é
externo (Coolify). O NestJS tem `app.setGlobalPrefix('api')` (`app.setup.ts:79`), então a
rota real deveria ser `/api/agent/v1/...`, e não `/agent/v1/...` como o
`BELEZAKI_AGENT_API.md` documenta.

**Precisamos da resposta deste comando**, rodado com uma chave e um tenant válidos:

```bash
for BASE in https://api.belezaki.com.br https://app.belezaki.com.br; do
  for P in /api/agent/v1/salon /agent/v1/salon; do
    echo "== $BASE$P"
    curl -s -o /dev/null -w '%{http_code}\n' "$BASE$P" \
      -H "X-Univerzap-Agent-Key: $KEY" -H "X-Tenant-External-Id: $EXT"
  done
done
```

`200` marca a base correta. `401`/`404` com corpo JSON também indica base correta, com
credencial ou tenant errado. `404` do proxy sem corpo JSON indica base errada.

Enquanto isso não voltar, **nenhuma chamada nossa funciona** e não há como testar nada do
resto.

Confirme também se `UNIVERZAP_AGENT_API_KEY` está de fato injetada no container: ela
**não está** no `docker-compose.yml:45-66`, e sem ela toda rota do agente responde 503.

---

## Lote 1 — os três que o cliente final sente

### P0-1 — a API oferece um profissional que o próprio book rejeita

**Onde:** `agent.service.ts:84`, `:222`, `:227`.

**O que acontece.** Esses três filtros usam só `active: true`. O `bookCore` exige
`active: true && publicVisible: true` (`public.service.ts:542-543`). Um profissional ativo
mas oculto do público aparece em `GET /professionals`, gera slots em `GET /availability`,
pode ser auto-escolhido quando `professional_id` é omitido — e então o POST devolve
**400 "Profissional indisponível"** num horário que a API acabou de anunciar como livre,
depois de a IA já ter oferecido o horário ao cliente.

**Correção.** Adicionar `publicVisible: true` aos três filtros. Melhor ainda: trocar
`prosForService` por `this.pub.eligiblePros()` (`public.service.ts:787-790`), que é a
implementação que o booking público já usa corretamente — o agente hoje tem uma cópia
paralela divergente.

**Aceite.** Profissional com `publicVisible=false` não aparece em `/professionals`, não
gera slot em `/availability` e não é auto-escolhido no book.

### P0-3 — telefone duplica o cliente

**Onde:** `public.service.ts:567`.

**O que acontece.** `input.clientPhone.replace(/\D/g, '')` faz igualdade exata, sem
normalização E.164, e o model `Client` não tem `@@unique([tenantId, phone])`
(`schema.prisma:63`). A IA envia `+5531984956383` → grava `5531984956383`. O site
tipicamente envia `(31) 98495-6383` → grava `31984956383`. **Duas linhas de `Client` para
a mesma pessoa**: histórico partido, anamnese partida, pacote partido.

**Correção.** A função que resolve isso já existe no repositório — `brDigits`
(`whatsapp/waha.client.ts:16-22`), hoje usada só nos caminhos de WhatsApp. Uma linha:
`const phone = brDigits(input.clientPhone);`.

Requer **migration de backfill** para unificar os clientes já duplicados. Considerar
também filtrar `deletedAt` no lookup (`schema.prisma:43`): hoje o telefone de um cliente
anonimizado por LGPD é reaproveitado em silêncio.

**Aceite.** Agendar com `+5531984956383` e depois com `(31) 98495-6383` resulta em **um
único** `Client`.

### P0-8 — validação ausente transforma erro de entrada em 500

**Onde:** `agent.dto.ts:11-18` e `agent.controller.ts:34-54`.

**O que acontece.** O DTO do agente usa `@IsString()` onde o DTO público usa `@IsUUID()` e
`@IsISO8601()` (`public/dto/public.dto.ts:59-72`). As rotas GET recebem `@Query` cru, sem
DTO. Resultado: `date` ausente ou malformado vira `NaN` → `where: { weekday: NaN }` no
Prisma → **500**. UUID malformado provavelmente também (P2023 não tratado).

Há um caso pior que 500, porque é silencioso: **`date=2026-02-30` responde `200` com os
slots reais de 2 de março**, sob um envelope que diz `2026-02-30`. A IA ofereceria um dia
que não existe.

**Correção.** `@IsUUID()` em `service_id` e `professional_id`, `@IsISO8601()` em `start`,
e DTOs para as rotas GET com `@Matches(/^\d{4}-\d{2}-\d{2}$/)` em `date` — validando
também que a data existe no calendário, não só que casa com o formato.

**Aceite.** `date` ausente, malformado ou inexistente responde **400**; nenhum desses
casos responde 200 nem 500.

---

## Lote 2 — as rotas que faltam

Sem elas o agente precisa dizer "vou passar para a equipe" toda vez que alguém pede para
cancelar ou remarcar — que é a operação mais comum depois de marcar.

A lógica interna **já existe e está em produção pelo painel**, incluindo a reconciliação
completa do Google Calendar. Falta expor com o `AgentGuard`.

| Rota | Reaproveita |
|---|---|
| `GET /agent/v1/appointments?phone=&from=&to=` | `appointments.service.ts:261-267` filtrado por `clientId` |
| `PATCH /agent/v1/appointments/:id` (remarcar) | `AppointmentsService.update` — já recalcula `endAt`, revalida conflito excluindo o próprio registro e move o evento do Google entre profissionais |
| cancelar (`status=CANCELLED`) | `AppointmentsService.update` → `reconcileCalendar` apaga o evento e zera `googleEventId` |

Requisitos, além das regras 5 e 6 acima:

- **Política de janela de cancelamento.** Não existe hoje e precisa ser decidida:
  respeitar `minAdvanceHours` ou uma configuração própria do salão. Sem isso o agente
  cancela um horário faltando dez minutos e a cadeira fica vazia.
- **Unificar a descrição do evento do Google.** `reconcileCalendar` grava
  `'Agendamento via belezaki'` sem telefone (`appointments.service.ts:721`), enquanto
  `bookCore` grava `Agendamento via belezaki — {telefone}` (`public.service.ts:631`).
  Hoje **qualquer PATCH posterior apaga o telefone** da descrição do evento.

---

## Lote 3 — robustez e segurança

- **P0-6 — entitlement não é validado.** `agent.guard.ts:57-61` seleciona `status` e nunca
  o testa. Salão suspenso ou revogado continua agendando. Replicar
  `entitlement.service.ts:38-40`. **É falha de segurança, não bug de conveniência.**
- **P0-4 — idempotência concorrente vira 500.** Duas chamadas simultâneas com a mesma
  chave: ambas passam pelo `findFirst`, a segunda estoura P2002 sem tratamento. Envolver
  `tx.appointment.create` (`public.service.ts:601`) em try/catch e, no P2002 sobre
  `(tenantId, idempotencyKey)`, refazer o `findFirst` e devolver o registro existente.
- **P0-7 — efeitos colaterais disparados dentro da transação.** Os dois `void`
  (`public.service.ts:628` e `:639`) estão dentro do callback do `withTenant` aberto na
  linha 509, apesar do comentário dizer "AFTER the tx commits". Ambos abrem novas
  transações que atualizam uma linha ainda não commitada; se vencerem a corrida, P2025
  engolido e `googleEventId` ou `confirmSentAt` perdido, sem log. O padrão certo já existe
  em `appointments.service.ts:410-433`.
- **P0-5 — rate limit por IP inviabiliza escala.** O balde é por IP e o chamador somos
  nós, servidor-a-servidor: **todos os salões compartilham os mesmos 60/min por rota**.
  Custom `ThrottlerGuard` com `getTracker()` devolvendo o `X-Tenant-External-Id`, e teto
  por tenant algo como 300/min.

---

## Lote 4 — observabilidade do Google Calendar

Hoje a API não informa se o evento foi criado, então a IA **não pode** afirmar ao cliente
que o horário entrou na agenda do profissional. Nós já proibimos essa fala no prompt.

Se quiserem liberá-la, expor `google_event_id` e `calendar_synced` na resposta do POST —
o que exige tornar o sync síncrono, com timeout curto (sugestão: 3s) e degradação para
`calendar_synced: null` significando "não sei". Sem isso, mantemos a proibição, e está
tudo bem.

Vale registrar duas coisas que afetam a expectativa do dono do salão, mesmo sem mudança
de código:

- o evento vai para o calendário `primary` **do profissional**, e só se ele tiver aceitado
  o convite de equipe, logado, conectado o Google e concedido o escopo de calendário —
  cinco pré-condições, todas silenciosas;
- não existe retry nem backfill: Google fora do ar no momento do booking deixa
  `googleEventId` nulo para sempre.

---

## O que devolver para nós

1. A resposta da seção 0 (base real e se a chave está no container).
2. Aviso de qualquer campo **novo** na resposta das 6 rotas.
3. Assim que o Lote 2 subir, o contrato das rotas novas — tiramos do prompt do agente a
   frase "vou passar para a equipe" no mesmo dia.

# Módulo de agendamento belezaki — design

Data: 2026-08-12
Status: aprovado, pronto para plano de implementação

Alternativa ao Google Calendar para donos de salão que já usam o belezaki. O agente
consulta a agenda real do salão e marca nela, sem que ninguém precise reconfigurar
serviços, profissionais e horários dentro do UniverZAP: essas coisas já existem lá.

Fonte de campo da API: `~/belezaki/MODULO_AGENDAMENTO_IA_SPEC.md`, levantado lendo o
código do belezaki linha a linha (commit `49df107`). Toda afirmação sobre o
comportamento da API vem de lá.

---

## Por que

Um salão que já opera no belezaki tem serviço, preço, duração, profissional, grade de
horário e bloqueios cadastrados. Pedir que ele recadastre tudo no módulo do Google
Calendar para o agente conseguir marcar é trabalho duplicado e duas verdades que
divergem na primeira semana. Conectar o belezaki resolve por leitura.

---

## O que já existe hoje — e o que está errado nele

O belezaki **já está no código** (`app/services/ai/belezaki/`), com três problemas.

**1. Liga sozinho, por conta, em todos os agentes.** Em
`Ai::AutopilotReplyService#generate_response`, quando o agente não tem ferramenta
própria nem agenda Google, o código cai em `Ai::Belezaki::AgentClient.for_account`, que
resolve o salão pela **conta** (assinatura ativa ou `belezaki_external_user_id` gravado
no admin pelo bridge de login). Consequência: qualquer conta vinculada paga os cinco
schemas de ferramenta no payload, em todo turno, em todo agente — inclusive nos que não
agendam nada. É o custo que este módulo existe para cortar.

**2. A URL base provavelmente está errada.** `Ai::Belezaki::AgentClient::PREFIX` é
`/agent/v1`. O belezaki roda NestJS com `app.setGlobalPrefix('api')`, então a rota real é
`/api/agent/v1` — divergência nº 1 da tabela do documento de campo, classificada como
crítica. A menos que `BELEZAKI_AGENT_BASE_URL` esteja compensando, nenhuma chamada nossa
jamais funcionou.

**3. O cliente descarta o código do erro.** `AgentClient#request` guarda apenas
`parsed['message']`. A regra do documento é o oposto: **nunca casar por string de
mensagem, sempre usar `error === 'slot_taken'`** — porque a mesma frase cobre três causas
distintas e as mensagens de validação são um array em inglês.

O que já está **bom** e permanece: a chave de idempotência hasheia a **ação**
(`service_id | start | professional_id | telefone`) com namespace da conversa, então
reconfirmar o mesmo horário deduplica e dois agendamentos diferentes na mesma conversa
passam os dois; e o registro do Contato vence o que o modelo extraiu do texto, então
telefone alucinado nunca entra na agenda do salão.

---

## Decisões fechadas

| Decisão | Escolha |
|---|---|
| Granularidade | Por **agente**, nunca por conta |
| O que é "conectar" | Detectar o salão do vínculo existente e confirmar. **Não existe OAuth por usuário no belezaki** — a auth é chave compartilhada servidor-a-servidor mais o id do salão no header |
| Coexistência com Google | **Uma agenda por agente.** Tentar conectar com a outra ativa abre popup explicando; a integração inativa aparece bloqueada |
| Onde mora a conexão | Tabela própria `ai_belezaki_connections` |
| Escopo desta entrega | Tudo que é possível do nosso lado. O que exige o repo belezaki vira documento de pedido separado |
| Remarcar/cancelar | Fora — as rotas não existem no belezaki. O agente encaminha para a equipe |

---

## 1. Conexão por agente

Bloco novo em `AthenasIntegrations.vue` (aba **Integrações**), logo abaixo do
`AthenasCalendarConnect` que já mora ali. Estado inicial: botão **Conectar belezaki**.

Ao clicar, o backend faz três coisas antes de gravar qualquer linha:

1. resolve o `external_id` do salão via `Ai::Belezaki::TenantResolver` (o bridge de login
   já o gravou);
2. chama `GET /salon` com a chave e esse id — **esta é a validação**: uma resposta prova
   de uma vez que a chave está certa, o tenant existe e o salão está acessível;
3. grava a conexão com `salon_name` e `timezone` vindos da resposta.

O botão é, portanto, também a **sonda da URL base**: se a base estiver errada, a conexão
falha na tela do operador, e não na frente de um cliente no WhatsApp.

### Falhas, e por que cada uma tem mensagem própria

| Causa | HTTP | O que a tela diz |
|---|---|---|
| Conta sem vínculo belezaki | — | "Sua conta não está ligada a um salão belezaki." É onboarding, não defeito |
| Chave ausente no servidor | 503 | "A integração não está configurada. Nosso time foi avisado." O operador não resolve isso |
| Chave inválida | 401 | idem |
| Salão não encontrado | 404 | "Não encontramos seu salão no belezaki." |

### Exclusividade

Simétrica. Clicar em conectar com a outra agenda ativa abre um popup —
*"Suportamos apenas uma integração de agenda por vez"* — com o botão de desconectar a
atual ali dentro. A integração inativa aparece bloqueada com a mesma frase.

Desconectar o Google é reversível: `GoogleCalendarConcern::OFFLINE_PARAMS` já usa
`access_type: offline` **com** `prompt: consent`, então toda reconexão devolve refresh
token novo. (A armadilha de refresh token descrita na seção 4.3 do documento de campo é
do Better Auth do belezaki, não nossa.)

### A aba "Configurar negócio" continua escondida — de propósito

`AssistantEdit.vue` libera a aba `business` apenas quando existe conexão **Google** ativa
(`hasCalendar`). Um agente belezaki não deve vê-la: serviços, profissionais, horários e
bloqueios vivem no belezaki, e as tabelas `ai_calendar_*` que aquela tela preenche não são
lidas por ninguém nesse caminho. Preencher ali seria trabalho jogado fora e uma segunda
verdade divergindo da primeira. Isto está correto como está e **não deve ser
"corrigido"** durante a implementação.

---

## 2. Modelo de dados

```
ai_belezaki_connections
  ai_assistant_id   único — um agente, uma conexão
  account_id
  external_id       snapshot do salão no momento de conectar
  salon_name        para a tela dizer "conectado a Studio Bella"
  timezone          vindo do GET /salon
  active            boolean
  connected_at
  last_error        por que a agenda parou, para o painel
```

Mais `Ai::Assistant#agenda_provider` → `:google` | `:belezaki` | `nil`. Um lugar só
responde "qual agenda este agente usa"; a tela, o gate das ferramentas e o bloqueio mútuo
consultam esse método.

**Por que congelar o `external_id`.** Hoje o salão é resolvido pela conta. O comentário do
próprio `TenantResolver` registra um caso real em que a resolução devolveu uma linha
arbitrária e o cache fixou o **salão errado** por cinco minutos — com o agente lendo
disponibilidade e marcando no tenant de outro. Com o id congelado na conexão, o agente
marca onde o operador confirmou. Se o vínculo mudar de verdade, ele reconecta.

---

## 3. Carregamento condicional das ferramentas

O belezaki passa a ser a **terceira entrada de `own_tools`**, condicionada a
`assistant.belezaki_connection&.active?`. O fallback automático (`belezaki_client`) e o
`run_tool_loop` separado são removidos.

Agente sem conexão não recebe schema nenhum. A economia é o payload inteiro, não uma
parte dele.

Unificar no `run_own_tool_loop` traz três ganhos de graça, porque é ele que captura os
resultados:

- as chamadas aparecem na aba Testar;
- o retorno das ferramentas entra no grounding — hoje um preço vindo de `listar_servicos`
  seria julgado inventado e a resposta morreria;
- o mesmo tratamento de falha de turno do restante do sistema.

### A armadilha do guard de agendamento

`Ai::Agent::ToolLoopService::WRITE_CONFIRMED` reconhece uma escrita pelo texto do
retorno: `"agendado": true`, `"remarcado"`, `"desmarcado"`. O belezaki responde
`{"appointment": {"status": "confirmed", ...}}` — nada disso casa. Unificar os loops sem
mais nada faria **todo agendamento bem-sucedido no belezaki ter a resposta suprimida**
como confirmação falsa.

Correção, que resolve dois problemas de uma vez: o executor normaliza o retorno do book
para `{agendado: true, ...}` **somente quando** `appointment.status == "confirmed"`, e
`{agendado: false, motivo: ...}` caso contrário. Isso satisfaz o guard e implementa a
regra 10.3 do documento de campo — status diferente de `confirmed` é replay de uma chave
cujo agendamento foi cancelado, e não pode ser tratado como sucesso.

---

## 4. Cliente HTTP endurecido

Tudo nesta seção é do nosso lado e várias entradas **mitigam P0 do belezaki sem tocar no
repo deles**.

**Prefixo** passa a `/api/agent/v1`, sobrescrevível por env.

**Erro com código.** `AgentClient::Error` passa a carregar `code`, `status` e
`validation`, cobrindo os três formatos que a API realmente produz:

| Formato real | Como reconhecer | `code` |
|---|---|---|
| `{"error":"slot_taken","message":...}` sem `statusCode` | `error` é String e não há `statusCode` | `slot_taken` |
| `{"message":["... in English"],...}` | `message` é Array | `validation_failed` |
| `{"statusCode":400,"message":"...","error":"Bad Request"}` | resto | `http_<status>` |

**Retry** apenas em `429`, `5xx` e timeout de rede. Backoff exponencial com jitter,
máximo duas tentativas, **sempre com a mesma chave de idempotência**. Nunca em `4xx`.

**Timeouts** separados: 10s nas leituras, 25s no book e no `sugerir_dias`. O servidor
deles corta em 20s (`statement_timeout`), e um timeout nosso mais curto que o deles
significa desistir de uma requisição que ainda vai gravar.

**Validação antes de enviar** (mitiga P0-8): UUID nos ids, `start` em ISO 8601, `date` no
formato `AAAA-MM-DD` **e existente no calendário**. Este último cobre uma armadilha
específica: `2026-02-30` não dá erro no belezaki — responde `200` com os horários reais de
2 de março, sob um envelope que diz `2026-02-30`. Sem essa validação o agente ofereceria
um dia que não existe. O que não passar vira erro-dado para o modelo, nunca uma chamada
que vira 500 lá.

**`professional_id` obrigatório** na ferramenta de agendar, sempre copiado do slot
(mitiga P0-1: a auto-escolha do belezaki pode devolver profissional com
`publicVisible=false` que o próprio book rejeita com 400, e ainda abre uma segunda janela
de corrida). Mesma regra no `sugerir_dias`, que sem filtro roda 31 × N profissionais
dentro de uma transação de 20 segundos.

**Concorrência** (mitiga P0-4): nunca disparar duas chamadas simultâneas com a mesma
chave de idempotência — o belezaki responde 500 nesse caso. O retry é sequencial por
construção.

**A string `start` é repassada verbatim.** Nunca reformatar, arredondar, reconstruir ou
converter de fuso: o book exige igualdade na precisão de milissegundo e qualquer desvio
retorna `409 slot_taken`, que parece "acabou de ser pego" quando na verdade aquele horário
nunca existiu.

---

## 5. Erros e o que o agente diz

Mensagem crua **nunca** chega ao cliente final: as de validação são array em inglês e as
de negócio são técnicas ("Profissional indisponível" quando o profissional está oculto).

| `code` | Causa provável | Comportamento |
|---|---|---|
| `slot_taken` | slot pego, ou horário fora da grade | reconsultar e reoferecer, sem travar |
| `http_400` "Profissional indisponível" | profissional oculto (P0-1) | tentar outro profissional; registrar para o time |
| `http_400` "Serviço indisponível" | serviço virou interno ou foi desativado | invalidar cache de serviços e reofertar |
| `validation_failed` | defeito nosso | fala genérica; registrar. Nunca repassar |
| `http_401` / `http_503` | chave errada ou ausente | gravar em `last_error`, marcar a conexão, escalar |
| `http_404` | tenant não vinculado | idem |
| `http_429` | balde por IP estourado (P0-5) | backoff e retry |
| `http_500` | data inválida, UUID malformado, corrida de idempotência | retry 1× com a mesma chave; depois escalar |

Regras que entram no prompt quando a agenda é belezaki:

1. Só oferecer horários vindos de `consultar_horarios`; nunca inventar, arredondar ou
   dizer "por volta de".
2. Antes de agendar, repetir serviço, profissional, dia e hora e esperar confirmação
   explícita.
3. Depois do "sim", consultar de novo — se o horário sumiu, avisar e oferecer
   alternativas, nunca agendar outro por conta própria.
4. Só dizer que está agendado depois de a ferramenta responder sucesso.
5. **Nunca** afirmar que a confirmação saiu no WhatsApp nem que o horário entrou no Google
   Agenda do profissional. A API não informa nenhum dos dois: são efeitos
   fire-and-forget, com quatro portões silenciosos no caso do WhatsApp e cinco
   pré-condições no caso do Google.
6. Pedido de cancelar ou remarcar → encaminhar para a equipe. Esta regra sai do prompt
   quando as rotas da seção 8 do documento de campo existirem.

---

## 6. Testes e critérios de aceite

Cobertura dos pontos onde um erro é caro e silencioso, com o HTTP do belezaki mockado:

- conexão: `GET /salon` responde → linha gravada com nome e fuso; 401/404/503 → mensagem
  distinta e nenhuma linha;
- exclusividade: conectar com a outra agenda ativa é recusado;
- **gate**: agente sem conexão não recebe nenhum schema belezaki no payload — é o teste
  que protege o custo;
- **normalização do book**: `status: "confirmed"` → `agendado: true`; qualquer outro
  status → `agendado: false`, e a resposta do agente não afirma agendamento;
- parser de erro: os três formatos produzem o `code` certo, incluindo o `409` sem
  `statusCode`;
- retry: `429` e `5xx` repetem com a **mesma** chave; `400` não repete;
- validação: `2026-02-30` é recusado antes de sair.

Aceite de produto: uma conversa ponta a ponta no playground marca de verdade na agenda do
salão e o agendamento aparece no painel do belezaki; nenhum horário oferecido que não
tenha vindo de `consultar_horarios`; nenhuma mensagem técnica ou em inglês chega ao
cliente.

---

## Fora de escopo — lado belezaki

Sai como documento de pedido separado, para o agente que trabalha naquele repositório:
`2026-08-12-belezaki-pedido-backend.md`. Em resumo: P0-1 (profissional oculto), P0-3
(telefone que duplica cliente), P0-8 (validação que vira 500), depois as rotas de
remarcar e cancelar, e por fim P0-4 a P0-7 e a observabilidade do P0-9.

## Risco conhecido na virada

Tornar a conexão explícita **desliga o belezaki para quem hoje o recebe pelo caminho
automático**. Conferir antes de subir se algum salão está agendando por ali; se estiver,
avisar para reconectar pela tela. A suspeita é que ninguém esteja, justamente porque o
prefixo da URL parece errado desde sempre — mas isso é suspeita, não fato, e a checagem é
uma query.

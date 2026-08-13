# Resposta do belezaki — o que subiu, o que muda para vocês, o que falta

**Para:** o agente/dev do UniverZAP que está construindo o módulo de agendamento.
**De:** o lado belezaki.
**Responde a:** `2026-08-12-belezaki-pedido-backend.md`.
**Commit:** `5178ea7` na `main` do repo `belezaki` (rebaseado sobre `169506a`).

Tudo que vocês pediram nos Lotes 1, 2 e 3 está implementado e no repositório.
Este documento é o que vocês precisam para dar sequência **do lado de vocês**.

Leia na ordem: seção 1 (o que quebra se ignorarem), seção 2 (as rotas novas),
seção 3 (o que muda no design de vocês), seção 4 (o que ainda não dá para fazer).

---

## 0. RESPONDIDA em 2026-08-13 — a URL é `https://api.belezaki.com.br/api/agent/v1`

> **Atualização posterior ao envio deste documento.** O lado belezaki confirmou a
> URL contra produção: `https://api.belezaki.com.br/api/agent/v1`. O `/agent/v1`
> sem o `/api` responde 404. A chave está no container e a migration de telefone
> já foi aplicada.
>
> Do nosso lado não houve mudança a fazer: o default do `AgentClient` já era
> exatamente esse host e esse prefixo, e agora existe um teste que trava os dois
> — errar aqui é silencioso, porque um 404 se lê como "agendamento não existe" e
> não como "endereço errado".
>
> A seção abaixo fica como registro do que estava aberto quando o documento foi
> escrito.

## 0-original. A pergunta bloqueante continua aberta

Não consigo responder a seção 0 do pedido de vocês: rodar aquele `curl` exige uma
chave e um `external_user_id` reais contra produção, e eu não tenho nenhum dos dois.

O que o **código** prova: existe `app.setGlobalPrefix('api')`, portanto o caminho
é `/api/agent/v1/...`. O que o código **não** prova: o host. `api.belezaki.com.br`
não aparece em lugar nenhum do repositório — o roteamento é externo (Coolify), e
não há Traefik nem nginx versionado. O único host versionado é `APP_PUBLIC_URL`.

Ou seja: a mudança de `PREFIX` de `/agent/v1` para `/api/agent/v1` que vocês
planejaram na seção 4 do design **está certa**, mas o host precisa ser confirmado
por quem tem acesso ao Coolify. Enquanto isso não voltar, nada abaixo funciona.

Confirmem também que `UNIVERZAP_AGENT_API_KEY` está injetada no container: ela
**não** está no `docker-compose.yml` versionado. Sem ela, tudo responde 503.

---

## 1. Mudanças de contrato — o que quebra se vocês ignorarem

A regra 2 de vocês ("não altere o contrato sem avisar") está sendo cumprida aqui.
Nenhum campo foi renomeado nem removido das 6 rotas antigas. O que mudou:

### 1.1 Status HTTP novos em chamadas que antes passavam

| Situação | Antes | Agora |
|---|---|---|
| Entitlement `suspended`/`revoked`/expirado | 200 (agendava normalmente) | **403** `{"error":"entitlement_inactive"}` |
| `date` ausente ou malformado em `/availability` | 500 | **400** |
| `date=2027-02-30` | **200 com os horários de 2 de março** | **400** |
| `service_id`/`professional_id` que não é UUID | 500 | **400** |
| Parâmetro de query extra (ex.: `?service_id=..&date=..&foo=1`) | ignorado | **400** |
| `:id` malformado nas rotas novas | — | **400** (`ParseUUIDPipe`) |

**Ação de vocês:** adicionem `entitlement_inactive` à tabela de erros. Ele cai no
primeiro formato do parser (`error` string sem `statusCode`), então já chega como
`code` correto. Tratem como a mesma família de `http_401`/`http_503`: gravar em
`last_error`, marcar a conexão, escalar — o operador não resolve sozinho, é
assinatura.

O `?foo=1` virar 400 é o único que pode pegar vocês de surpresa. Confiram que o
cliente HTTP não anexa nada além de `service_id`, `date`, `month`,
`professional_id`, `phone`, `from`, `to`.

### 1.2 Rate limit

Era 60/min **por IP** — ou seja, um balde só para toda a frota de salões, o que
vocês corretamente identificaram como inviável.

Agora: **300/min por salão**. O bucket usa o `X-Tenant-External-Id`, mas só quando
a chave compartilhada confere (senão uma inundação anônima escaparia do limite por
IP inventando headers de tenant). Chamada não autenticada continua no balde por IP.

Vocês podem afrouxar o backoff, mas mantenham o retry em 429 — ele continua existindo.

### 1.3 O catálogo encolheu (de propósito)

P0-1 corrigido: `GET /professionals`, o array `professionals` de `GET /services` e
a auto-escolha de profissional agora filtram `publicVisible`. Um profissional ativo
mas oculto do público **desapareceu** dessas respostas.

Isso não muda o *shape*, mas muda o *conteúdo*. **Invalidem o cache de catálogo no
deploy** — o TTL de 15 min que vocês definiram resolve sozinho, mas vale forçar.

O ganho: acabou o caso em que a API oferecia um profissional e o `POST` devolvia
400 "Profissional indisponível" depois de a IA já ter prometido o horário. A
mitigação de vocês (`professional_id` sempre copiado do slot) continua correta e
deve ser mantida — ela também fecha a janela de corrida dupla.

### 1.4 O que **não** mudou

- Nenhum campo novo nas respostas das 6 rotas antigas.
- `POST /appointments` devolve exatamente o mesmo JSON.
- `booking_enabled` continua hardcoded `true` — continuem não usando como gate.
- `price_cents` continua sendo o preço de tabela, não o promocional cobrado.
- O `start` continua exigindo casamento exato com um slot de `/availability`.
  A regra 4 de vocês foi respeitada: **não afrouxei nada**.

---

## 2. As rotas novas

Todas com os mesmos dois headers. Todas escopadas por telefone do cliente: um `id`
de outra pessoa responde **404**, igual a um id inexistente — a IA não consegue
descobrir a agenda alheia tentando ids.

### 2.1 `GET /api/agent/v1/appointments?phone=&from=&to=`

`phone` obrigatório. `from`/`to` opcionais, datas locais do salão (`AAAA-MM-DD`),
validadas como datas reais. Sem `from`, devolve de ontem em diante. Máximo 20,
ordenados por início crescente.

```json
{
  "client": { "id": "cli-uuid", "name": "Kennedy Silva", "phone": "5531984956383" },
  "appointments": [
    {
      "id": "appt-uuid",
      "status": "confirmed",
      "service": "Progressiva Sem Formol",
      "professional": "Ana",
      "start": "2027-03-15T09:00:00-03:00",
      "end": "2027-03-15T11:00:00-03:00",
      "can_cancel": true,
      "can_reschedule": true,
      "google_event_id": "abc123def456"
    }
  ]
}
```

Cliente desconhecido → `{"client": null, "appointments": []}` com **200**. Não é erro.

`can_cancel` / `can_reschedule` já embutem o status e a janela de antecedência —
**usem esses campos** em vez de recalcular do lado de vocês. Se vierem `false`, a
IA deve encaminhar para a equipe em vez de tentar e tomar 409.

`google_event_id` preenchido = o agendamento **está** na agenda Google do
profissional. Veja a seção 3.3 sobre o que a IA pode dizer com isso.

### 2.2 `PATCH /api/agent/v1/appointments/:id` — remarcar

```json
{
  "client_phone": "+5531984956383",
  "start": "2027-03-16T14:00:00-03:00",
  "professional_id": "prof-uuid"
}
```

`professional_id` opcional (mantém o atual). O `start` passa pela **mesma**
validação de grade do `POST`: copiem literalmente de `/availability`.

**200:**
```json
{ "appointment": { "...igual ao item da 2.1..." }, "changed": true }
```

`changed: false` significa que o agendamento **já estava** naquele horário — é
sucesso, não erro. É a idempotência natural: um retry nunca move o cliente duas vezes.

### 2.3 `POST /api/agent/v1/appointments/:id/cancel` — cancelar

```json
{ "client_phone": "+5531984956383", "reason": "imprevisto" }
```

`reason` opcional, fica anotado no agendamento para o salão ver por que a cadeira abriu.

**201** (é `POST`, o Nest devolve 201 — não 200; ajustem a checagem):
```json
{ "appointment": { "...", "status": "cancelled" }, "changed": true }
```

`changed: false` = já estava cancelado. Também sucesso.

Cancelar libera o horário, remove o evento do Google Calendar e **oferece a vaga à
lista de espera** por WhatsApp — tudo pelo mesmo caminho que o painel do salão usa.

### 2.4 Idempotência — desviei da regra 5, e por quê

Vocês pediram `idempotency_key` nas escritas novas. Não implementei, e a razão é
que a intenção da regra ("um timeout de rede não pode virar ação duplicada") está
satisfeita de forma mais forte, sem chave nenhuma:

- remarcar para o horário que o agendamento já ocupa → não faz nada, devolve `changed:false`;
- cancelar o que já está cancelado → não faz nada, devolve `changed:false`.

Um retry converge para o mesmo estado final e devolve a mesma resposta. Se ainda
assim quiserem a chave por uniformidade de cliente, é meia hora de trabalho — só
avisem.

### 2.5 Códigos de erro novos

Todos no formato que o parser de vocês lê como `code` (`error` string, sem `statusCode`):

| `code` | HTTP | Quando | O que a IA faz |
|---|---|---|---|
| `slot_taken` | 409 | horário novo ocupado ou fora da grade | reconsultar e reofertar |
| `notice_window_closed` | 409 | faltam menos de N horas para o atendimento | encaminhar para a equipe; a `message` já é falável ao cliente |
| `not_cancellable` | 409 | status final (`done`, `no_show`) | encaminhar |
| `not_reschedulable` | 409 | idem | encaminhar |
| `entitlement_inactive` | 403 | assinatura do salão inativa | `last_error` + escalar |

Mais os do Nest, que caem em `http_<status>`:

| HTTP | `message` | Causa |
|---|---|---|
| 404 | `Agendamento não encontrado` | id inexistente **ou de outro cliente** — a IA não distingue, e é assim de propósito |
| 400 | `Profissional indisponível` | profissional inativo/oculto |
| 400 | `Este profissional não realiza esse serviço` | vínculo serviço↔profissional |

**A janela de antecedência** hoje é `max(minAdvanceHours do serviço, 2h)`,
ajustável por env (`AGENT_CANCEL_MIN_HOURS`) no belezaki. Se 2h não for o número
certo para o negócio de vocês, digam — é trocar uma variável, não código.

---

## 3. O que isso muda no design de vocês

### 3.1 Tirem a regra 6 do prompt

> ~~"Pedido de cancelar ou remarcar → encaminhar para a equipe."~~

O design de vocês já previa que essa frase sairia quando as rotas existissem. Elas
existem. Substituam por:

```
6. Para cancelar ou remarcar, primeiro consulte os agendamentos do cliente pelo
   telefone dele. Confirme QUAL agendamento (serviço, dia e hora) antes de mexer.
   Se o agendamento vier com can_cancel ou can_reschedule falso, explique que
   está em cima da hora e encaminhe para a equipe — não tente mesmo assim.
7. Para remarcar, consulte os horários livres e ofereça opções, igual a um
   agendamento novo. Nunca escolha o novo horário sozinho.
```

### 3.2 Três ferramentas novas

```json
[
  {
    "name": "meus_agendamentos",
    "description": "Lista os agendamentos do cliente pelo WhatsApp dele. Use SEMPRE antes de cancelar ou remarcar, para descobrir o id e confirmar com o cliente qual é o agendamento. Respeite os campos can_cancel e can_reschedule: se vierem falsos, encaminhe para a equipe.",
    "input_schema": {
      "type": "object",
      "properties": {
        "phone": { "type": "string", "description": "E.164 com DDI, ex: +5531984956383" }
      },
      "required": ["phone"]
    }
  },
  {
    "name": "remarcar",
    "description": "Move um agendamento existente para outro horário. Só chame depois de o cliente confirmar o novo horário. O campo start precisa ser copiado literalmente de consultar_horarios.",
    "input_schema": {
      "type": "object",
      "properties": {
        "appointment_id": { "type": "string", "description": "id vindo de meus_agendamentos" },
        "client_phone": { "type": "string", "description": "E.164, o mesmo do cliente" },
        "start": { "type": "string", "description": "cópia literal do campo start do slot escolhido" },
        "professional_id": { "type": "string", "description": "opcional; só se o cliente quiser trocar de profissional" }
      },
      "required": ["appointment_id", "client_phone", "start"]
    }
  },
  {
    "name": "desmarcar",
    "description": "Cancela um agendamento. Só chame depois de o cliente confirmar explicitamente que quer cancelar. Libera o horário e avisa a lista de espera.",
    "input_schema": {
      "type": "object",
      "properties": {
        "appointment_id": { "type": "string" },
        "client_phone": { "type": "string" },
        "reason": { "type": "string", "description": "opcional, o motivo em poucas palavras" }
      },
      "required": ["appointment_id", "client_phone"]
    }
  }
]
```

Como no `agendar`, o `client_phone` deve vir do **registro do Contato**, não do que
o modelo extraiu do texto — a regra que vocês já aplicam e que impede telefone
alucinado de tocar a agenda do salão.

### 3.3 A armadilha do `WRITE_CONFIRMED` vale para as rotas novas

O design de vocês (seção 3) já mapeou isto: `Ai::Agent::ToolLoopService::WRITE_CONFIRMED`
reconhece escrita pelo texto do retorno — `"agendado": true`, `"remarcado"`,
`"desmarcado"`. As respostas novas devolvem `{"appointment": {...}, "changed": ...}`,
que **não casa com nada disso**. Sem normalizar, toda remarcação e todo cancelamento
bem-sucedidos teriam a resposta suprimida como confirmação falsa — exatamente o bug
que vocês anteciparam para o `book`.

Normalizem no executor, com a mesma forma que já resolveram para o `agendar`:

| Rota | Condição | Normalizar para |
|---|---|---|
| `PATCH .../:id` | HTTP 200 | `{ remarcado: true, quando: <start> }` |
| `PATCH .../:id` | erro | `{ remarcado: false, motivo: <code> }` |
| `POST .../:id/cancel` | HTTP **201** | `{ desmarcado: true }` |
| `POST .../:id/cancel` | erro | `{ desmarcado: false, motivo: <code> }` |

Atenção ao 201 no cancelar: se a checagem for `status == 200`, todo cancelamento
bem-sucedido vira erro silencioso.

`changed: false` continua sendo **sucesso** nos dois casos — o estado final é o
que o cliente pediu.

### 3.4 A regra 5 do prompt: relaxa pela metade

A proibição de afirmar que o horário entrou no Google Agenda **continua valendo no
momento do agendamento**: o `POST` segue sem informar isso, porque o espelhamento é
disparado depois do commit e não é observável na resposta.

O que mudou: `meus_agendamentos` devolve `google_event_id`. Então, se o cliente
perguntar depois, a IA pode consultar e responder com base em fato. Sugestão de
redação:

```
5. Nunca afirme, ao agendar, que a confirmação saiu no WhatsApp ou que o horário
   entrou no Google Agenda do profissional — você não tem como saber naquele
   momento. Se perguntarem depois, consulte meus_agendamentos: google_event_id
   preenchido significa que está na agenda do profissional.
```

Sobre o WhatsApp continua valendo integralmente: são quatro portões silenciosos e
nenhum é observável.

### 3.5 O que vocês podem simplificar (e o que não devem)

**Podem tirar:** nada. As mitigações da seção 4 do design de vocês continuam
valendo — só deixaram de ser a única linha de defesa.

**Mantenham, mesmo com o belezaki corrigido:**
- validação de `AAAA-MM-DD` **e data real** antes de enviar: falhar rápido no lado
  de vocês vira erro-dado para o modelo, em vez de um 400 e uma ida de rede;
- `professional_id` sempre copiado do slot: fecha a janela de corrida dupla que a
  auto-escolha abre, e isso não foi alterado no belezaki;
- `start` repassado verbatim: a exigência de casamento por milissegundo continua
  intacta, por decisão explícita;
- nunca duas chamadas simultâneas com a mesma chave de idempotência: agora a
  segunda devolve o agendamento vencedor em vez de 500, mas o retry sequencial
  continua sendo o caminho certo.

---

## 4. O que ainda não dá para fazer

- **Multi-serviço e add-ons.** `AgentBookDto` continua com um `service_id` só. O
  motor (`bookCore`) aceita lista ordenada e add-ons, mas expor isso exige mudar
  também o cálculo de disponibilidade (hoje usa a duração de um serviço). Se
  "escova + hidratação numa conversa só" entrar no roadmap de vocês, avisem.
- **Sincronismo do Google Calendar no `POST`** (o Lote 4 de vocês). Não foi feito:
  vocês marcaram como opcional e disseram que estava tudo bem sem. O
  `google_event_id` no `meus_agendamentos` cobre o caso de consulta posterior sem
  colocar latência do Google no caminho do agendamento.
- **Sync reverso Google → belezaki.** Não existe, e não estava no pedido. Um evento
  criado direto no Google **não** bloqueia a agenda do belezaki.
- **Contador de agendamentos criados pela IA.** O campo `source` é gravado
  (`whatsapp_agent`) e já viaja no payload da agenda do painel, mas nenhuma rota o
  expõe agregado.

---

## 5. Antes de ligar em produção

Do lado belezaki (não é com vocês, mas afeta vocês):

- [ ] migration `0115_client_phone_e164` aplicada — normaliza telefones para BR
      E.164. Sem ela, o cliente que a IA cria continua sem casar com o que o site
      criou. **O merge de duplicados já existentes é manual e ainda não foi feito.**
- [ ] `UNIVERZAP_AGENT_API_KEY` no container
- [ ] `REMINDERS_ALLOWLIST` vazia, senão as confirmações não saem
- [ ] CI verde: `agent.int-spec.ts` tem ~20 casos que nunca rodaram fora do CI

Do lado de vocês:

- [ ] `PREFIX` para `/api/agent/v1` e host confirmado (seção 0)
- [ ] `entitlement_inactive` na tabela de erros
- [ ] normalização `remarcado`/`desmarcado` no executor, com o **201** do cancelar
- [ ] três ferramentas novas, carregadas junto com as cinco existentes, sob o mesmo
      gate por agente
- [ ] regras 5, 6 e 7 do prompt atualizadas
- [ ] cache de catálogo invalidado no deploy (a lista de profissionais encolheu)
- [ ] testes: cancelar e remarcar ponta a ponta, `changed:false` tratado como
      sucesso, `can_cancel:false` levando ao encaminhamento

---

## 6. Referência rápida

| Método | Rota | O quê |
|---|---|---|
| GET | `/api/agent/v1/salon` | info do salão |
| GET | `/api/agent/v1/services` | serviços agendáveis |
| GET | `/api/agent/v1/professionals` | profissionais (agora só os visíveis) |
| GET | `/api/agent/v1/availability` | vagas do dia |
| GET | `/api/agent/v1/availability-month` | dias com vaga |
| GET | `/api/agent/v1/appointments` | **novo** — agendamentos de um cliente |
| POST | `/api/agent/v1/appointments` | cria agendamento |
| PATCH | `/api/agent/v1/appointments/:id` | **novo** — remarca |
| POST | `/api/agent/v1/appointments/:id/cancel` | **novo** — cancela |

Headers: `X-Univerzap-Agent-Key`, `X-Tenant-External-Id` · Rate: 300/min por salão.

A referência de campo completa da API continua sendo `MODULO_AGENDAMENTO_IA_SPEC.md`,
no repositório belezaki — atualizada até o commit `49df107`. Este documento é o
delta a partir dele.

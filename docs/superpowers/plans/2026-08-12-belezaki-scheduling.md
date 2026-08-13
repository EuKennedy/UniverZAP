# Agendamento belezaki — plano de implementação

> **Para quem executa:** use `superpowers:subagent-driven-development` (recomendado) ou
> `superpowers:executing-plans` para implementar tarefa a tarefa. Os passos usam
> checkbox (`- [ ]`) para acompanhamento.

**Objetivo:** permitir que o dono de um agente conecte a agenda do belezaki dele, por
agente, e que só os agentes conectados carreguem as ferramentas de agendamento.

**Arquitetura:** uma tabela nova guarda a conexão por agente com o id do salão congelado.
As ferramentas do belezaki passam a ser mais uma entrada do `own_tools` do
`Ai::AutopilotReplyService`, condicionada a essa conexão, e o caminho automático por conta
é removido. O cliente HTTP existente é endurecido (prefixo, código de erro, retry,
timeouts, validação antes de enviar).

**Stack:** Rails 7.1, RSpec + WebMock, Vue 3 `<script setup>`, Tailwind.

**Design de origem:** `docs/superpowers/specs/2026-08-12-belezaki-scheduling-design.md`.

## Restrições globais

- Ruby: RuboCop, máximo **150 colunas**. `bundle exec rubocop -a` antes de cada commit.
- Vue: **só Tailwind**. Sem CSS custom, sem scoped, sem style inline. Composition API com
  `<script setup>`.
- i18n: nenhuma string solta no template. Este projeto atualiza **`en.json` e
  `pt_BR.json`** (é fork com pt-BR como língua de produto).
- Commits: Conventional Commits. Autor `EuKennedy <kennedy.rodrigues1104@gmail.com>`.
  **Nunca** citar Claude nem adicionar co-autor.
- Migration é **manual no deploy**: ao terminar a Tarefa 1, avisar o operador com o nome
  do arquivo e o comando.
- Branch: `univerzap/phase-0-saneamento`.

## Ordem — e por que ela importa

A Tarefa 7 desliga o caminho automático. Se ela subir antes da tela existir, um salão que
hoje agenda pelo caminho automático fica **sem agenda e sem como reconectar**. Por isso a
tela (Tarefa 4) vem antes do gate (Tarefa 7). Não reordene.

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `db/migrate/20260812190000_create_ai_belezaki_connections.rb` | tabela |
| `app/models/ai/belezaki/connection.rb` | a conexão de um agente |
| `app/models/ai/assistant.rb` | associação + `agenda_provider` |
| `app/services/ai/belezaki/connect_service.rb` | resolver salão, sondar, gravar |
| `app/controllers/api/v1/accounts/ai/belezaki_connections_controller.rb` | show/create/destroy |
| `config/routes.rb` | rota aninhada no assistant |
| `app/javascript/dashboard/components-next/athenas/AthenasBelezakiConnect.vue` | o bloco na tela |
| `app/javascript/dashboard/components-next/athenas/AthenasIntegrations.vue` | monta o bloco |
| `app/javascript/dashboard/api/athenas.js` | três métodos |
| `app/services/ai/belezaki/agent_client.rb` | prefixo, erro com código, retry, timeouts |
| `app/services/ai/belezaki/scheduling_tools.rb` | validação, `professional_id`, normalização do book |
| `app/services/ai/autopilot_reply_service.rb` | o gate |

---

## Tarefa 1: Tabela, modelo e `agenda_provider`

**Arquivos:**
- Criar: `db/migrate/20260812190000_create_ai_belezaki_connections.rb`
- Criar: `app/models/ai/belezaki/connection.rb`
- Modificar: `app/models/ai/assistant.rb`
- Testar: `spec/models/ai/belezaki/connection_spec.rb`

**Interfaces produzidas:**
- `Ai::Belezaki::Connection#active?` → boolean
- `Ai::Belezaki::Connection#push_event_data` → `{id:, salon_name:, timezone:, status:, connected_at:}`
- `Ai::Assistant#belezaki_connection` → `Ai::Belezaki::Connection` ou nil
- `Ai::Assistant#agenda_provider` → `:google` | `:belezaki` | `nil`

- [ ] **Passo 1: escrever o teste que falha**

```ruby
# spec/models/ai/belezaki/connection_spec.rb
require 'rails_helper'

RSpec.describe Ai::Belezaki::Connection do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  def connect!(status: 'active')
    described_class.create!(
      ai_assistant: assistant, account: account, external_id: 'ext-1',
      salon_name: 'Studio Bella', timezone: 'America/Sao_Paulo', status: status,
      connected_at: Time.current
    )
  end

  it 'answers belezaki as the agenda provider once connected' do
    connect!

    expect(assistant.reload.agenda_provider).to eq(:belezaki)
  end

  # One agenda per agent is the whole product rule; a second row would let two
  # tools with the same name reach the model in one payload.
  it 'refuses a second connection for the same agent' do
    connect!

    expect { connect! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  # A revoked row must not keep the agent scheduling.
  it 'is not a provider once revoked' do
    connect!(status: 'revoked')

    expect(assistant.reload.agenda_provider).to be_nil
  end
end
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `bundle exec rspec spec/models/ai/belezaki/connection_spec.rb`
Esperado: FAIL — `uninitialized constant Ai::Belezaki::Connection`.

- [ ] **Passo 3: a migration**

```ruby
# db/migrate/20260812190000_create_ai_belezaki_connections.rb
class CreateAiBelezakiConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_belezaki_connections do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: { unique: true }
      t.references :account, null: false, foreign_key: true, index: false
      # Frozen at connect time. Resolving the salon per ACCOUNT on every reply is
      # what once let a cached, arbitrary row point an agent at the WRONG salon.
      t.string :external_id, null: false
      t.string :salon_name
      t.string :timezone, null: false, default: 'America/Sao_Paulo'
      t.string :status, null: false, default: 'active'
      t.datetime :connected_at
      t.text :last_error
      t.datetime :last_error_at
      t.timestamps
    end
  end
end
```

- [ ] **Passo 4: o modelo**

```ruby
# app/models/ai/belezaki/connection.rb
# One belezaki salon bound to ONE agent.
#
# The salon id is frozen here rather than resolved per reply: resolution goes
# through the account, and an account whose link changes would silently move a
# live agent onto another salon's agenda.
class Ai::Belezaki::Connection < ApplicationRecord
  self.table_name = 'ai_belezaki_connections'

  STATUSES = %w[active revoked].freeze

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  validates :external_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  # One agenda per agent: two connections would put two tools with the same name
  # in one payload, which the Anthropic API rejects outright.
  validates :ai_assistant_id, uniqueness: true

  scope :active, -> { where(status: 'active') }

  def active?
    status == 'active'
  end

  def revoke!(reason)
    update!(status: 'revoked', last_error: reason.to_s.truncate(300), last_error_at: Time.current)
  end

  def push_event_data
    { id: id, salon_name: salon_name, timezone: timezone, status: status, connected_at: connected_at }
  end
end
```

- [ ] **Passo 5: associação e `agenda_provider` no assistant**

Em `app/models/ai/assistant.rb`, junto das outras associações `calendar_*`:

```ruby
  has_one :belezaki_connection, class_name: 'Ai::Belezaki::Connection', foreign_key: :ai_assistant_id,
                                dependent: :destroy, inverse_of: :ai_assistant
```

E como método público:

```ruby
  # Which agenda this agent books on, in one place. The screen, the tool gate and
  # the mutual block all read this instead of each deciding for itself.
  def agenda_provider
    return :belezaki if belezaki_connection&.active?
    return :google if calendar_connections.active.exists?

    nil
  end
```

- [ ] **Passo 6: rodar e ver passar**

Rodar: `bundle exec rails db:migrate && bundle exec rspec spec/models/ai/belezaki/connection_spec.rb`
Esperado: 3 exemplos, 0 falhas.

- [ ] **Passo 7: commit e AVISO DE MIGRATION**

```bash
git add db/migrate/20260812190000_create_ai_belezaki_connections.rb app/models/ai/belezaki/connection.rb app/models/ai/assistant.rb spec/models/ai/belezaki/connection_spec.rb db/schema.rb
git commit -m "feat(athenas): the table one agent's belezaki agenda hangs off"
```

Avisar o operador: migration nova, `20260812190000_create_ai_belezaki_connections.rb`,
rodar `RAILS_ENV=production bundle exec rails db:migrate` e reiniciar web + sidekiq.

---

## Tarefa 2: `ConnectService` — resolver, sondar, gravar

**Arquivos:**
- Criar: `app/services/ai/belezaki/connect_service.rb`
- Testar: `spec/services/ai/belezaki/connect_service_spec.rb`

**Interfaces consumidas:** `Ai::Belezaki::Connection` (Tarefa 1),
`Ai::Belezaki::TenantResolver.external_id(account)`, `Ai::Belezaki::AgentClient#salon`.

**Interfaces produzidas:**
- `Ai::Belezaki::ConnectService.new(assistant:).perform` → `Ai::Belezaki::Connection`
- Erros: `NotLinked`, `NotConfigured`, `AgendaTaken`

- [ ] **Passo 1: escrever o teste que falha**

```ruby
# spec/services/ai/belezaki/connect_service_spec.rb
require 'rails_helper'

RSpec.describe Ai::Belezaki::ConnectService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:service) { described_class.new(assistant: assistant) }

  before do
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).with(account).and_return('ext-1')
    allow(Ai::Belezaki::AgentClient).to receive(:api_key).and_return('shared-key')
  end

  def stub_salon(status, body)
    stub_request(:get, 'https://api.belezaki.com.br/api/agent/v1/salon')
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'stores the salon the probe answered with' do
    stub_salon(200, { 'name' => 'Studio Bella', 'timezone' => 'America/Sao_Paulo' })

    connection = service.perform

    expect(connection.salon_name).to eq('Studio Bella')
    expect(connection.external_id).to eq('ext-1')
    expect(connection).to be_active
  end

  # An account that never went through the belezaki login bridge has no salon to
  # bind. That is onboarding, not a fault, and says so.
  it 'refuses when the account is not linked to a salon' do
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return(nil)

    expect { service.perform }.to raise_error(described_class::NotLinked)
  end

  # The shared key lives on the server. Missing, every route answers 503, so the
  # operator must not be told to try again.
  it 'refuses when the shared key is not configured' do
    allow(Ai::Belezaki::AgentClient).to receive(:api_key).and_return(nil)

    expect { service.perform }.to raise_error(described_class::NotConfigured)
  end

  it 'refuses while a Google calendar is connected' do
    stub_salon(200, { 'name' => 'Studio Bella' })
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account,
      google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )

    expect { service.perform }.to raise_error(described_class::AgendaTaken)
  end

  # A probe that fails must leave nothing behind: a row written here would show
  # "connected" on a salon the agent cannot actually reach.
  it 'writes no row when the probe fails' do
    stub_salon(404, { 'message' => 'Salão não encontrado para esta conta.' })

    expect { service.perform }.to raise_error(Ai::Belezaki::AgentClient::Error)
    expect(Ai::Belezaki::Connection.count).to eq(0)
  end
end
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `bundle exec rspec spec/services/ai/belezaki/connect_service_spec.rb`
Esperado: FAIL — `uninitialized constant Ai::Belezaki::ConnectService`.

- [ ] **Passo 3: implementar**

```ruby
# app/services/ai/belezaki/connect_service.rb
# Binds one agent to the salon its account already belongs to.
#
# The GET /salon call is the whole validation: an answer proves in one shot that
# the shared key is right, the tenant exists and the salon is reachable. It also
# doubles as the probe for the base URL, so a wrong prefix fails on the
# operator's screen instead of in front of a customer.
class Ai::Belezaki::ConnectService
  class NotLinked < StandardError; end
  class NotConfigured < StandardError; end
  class AgendaTaken < StandardError; end

  def initialize(assistant:)
    @assistant = assistant
  end

  def perform
    raise AgendaTaken, 'google calendar connected' if @assistant.calendar_connections.active.exists?
    raise NotConfigured, 'shared key missing' if Ai::Belezaki::AgentClient.api_key.blank?

    external_id = Ai::Belezaki::TenantResolver.external_id(@assistant.account)
    raise NotLinked, 'account has no belezaki salon' if external_id.blank?

    persist(external_id, probe(external_id))
  end

  private

  def probe(external_id)
    Ai::Belezaki::AgentClient.new(external_id: external_id).salon
  end

  # Reconnecting the same agent updates the row rather than colliding with the
  # uniqueness rule — the operator's mental model is "connect", not "delete then
  # connect".
  def persist(external_id, salon)
    connection = @assistant.belezaki_connection || @assistant.build_belezaki_connection
    connection.update!(
      account_id: @assistant.account_id, external_id: external_id,
      salon_name: salon['name'], timezone: salon['timezone'].presence || 'America/Sao_Paulo',
      status: 'active', connected_at: Time.current, last_error: nil, last_error_at: nil
    )
    connection
  end
end
```

- [ ] **Passo 4: rodar e ver passar**

Rodar: `bundle exec rspec spec/services/ai/belezaki/connect_service_spec.rb`
Esperado: 5 exemplos, 0 falhas.

Se o stub da URL não casar, é porque a Tarefa 5 ainda não corrigiu o prefixo. Ajuste o
stub para a URL que o cliente usa hoje e **deixe um comentário no teste** apontando a
Tarefa 5; ela reverte o stub para `/api/agent/v1`.

- [ ] **Passo 5: commit**

```bash
bundle exec rubocop -a app/services/ai/belezaki/connect_service.rb
git add app/services/ai/belezaki/connect_service.rb spec/services/ai/belezaki/connect_service_spec.rb
git commit -m "feat(athenas): connecting an agent to the salon it already belongs to"
```

---

## Tarefa 3: API da conexão

**Arquivos:**
- Criar: `app/controllers/api/v1/accounts/ai/belezaki_connections_controller.rb`
- Modificar: `config/routes.rb:514` (logo abaixo de `calendar_connection`)
- Testar: `spec/controllers/api/v1/accounts/ai/belezaki_connections_controller_spec.rb`

**Interfaces produzidas:**
- `GET /api/v1/accounts/:account_id/ai/assistants/:assistant_id/belezaki_connection`
- `POST` mesma rota → `{connection: {...}}` ou `{error: <código>}` com 422
- `DELETE` mesma rota → 200

Códigos de erro devolvidos: `not_linked`, `not_configured`, `agenda_taken`, `probe_failed`.

- [ ] **Passo 1: escrever o teste que falha**

```ruby
# spec/controllers/api/v1/accounts/ai/belezaki_connections_controller_spec.rb
require 'rails_helper'

RSpec.describe 'Belezaki connections API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/ai/assistants/#{assistant.id}/belezaki_connection" }

  it 'connects and returns the salon' do
    allow_any_instance_of(Ai::Belezaki::ConnectService).to receive(:perform).and_return(
      Ai::Belezaki::Connection.new(salon_name: 'Studio Bella', status: 'active')
    )

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['connection']['salon_name']).to eq('Studio Bella')
  end

  # The operator has to be told WHICH thing is wrong: "not linked" is their
  # onboarding, "not configured" is ours, and the fixes are different.
  it 'reports the reason it could not connect' do
    allow_any_instance_of(Ai::Belezaki::ConnectService)
      .to receive(:perform).and_raise(Ai::Belezaki::ConnectService::NotLinked)

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('not_linked')
  end
end
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `bundle exec rspec spec/controllers/api/v1/accounts/ai/belezaki_connections_controller_spec.rb`
Esperado: FAIL — rota inexistente (404).

- [ ] **Passo 3: a rota**

Em `config/routes.rb`, imediatamente abaixo da linha do `calendar_connection`:

```ruby
              resource :belezaki_connection, only: [:show, :create, :destroy], controller: 'belezaki_connections'
```

- [ ] **Passo 4: o controller**

```ruby
# app/controllers/api/v1/accounts/ai/belezaki_connections_controller.rb
# Binding ONE agent to a belezaki salon.
#
# Per agent, like the Google calendar next to it: the same operator may run a
# salon and a clinic as two agents, and one agenda must never answer for the
# other.
class Api::V1::Accounts::Ai::BelezakiConnectionsController < Api::V1::Accounts::BaseController
  before_action :set_assistant

  def show
    render json: { connection: @assistant.belezaki_connection&.push_event_data }
  end

  def create
    render json: { connection: Ai::Belezaki::ConnectService.new(assistant: @assistant).perform.push_event_data }
  rescue Ai::Belezaki::ConnectService::NotLinked
    refuse('not_linked')
  rescue Ai::Belezaki::ConnectService::NotConfigured
    refuse('not_configured')
  rescue Ai::Belezaki::ConnectService::AgendaTaken
    refuse('agenda_taken')
  rescue Ai::Belezaki::AgentClient::Error => e
    # The salon answered something we cannot act on. Kept as the connection's
    # last_error would be, but there is no row yet, so it only goes to the log.
    Rails.logger.warn("[Belezaki] connect probe failed assistant=#{@assistant.id}: #{e.message}")
    refuse('probe_failed')
  end

  # Disconnecting only unbinds. Appointments already made live in the salon's own
  # agenda and are real customers' real times.
  def destroy
    @assistant.belezaki_connection&.destroy
    head :ok
  end

  private

  def set_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def refuse(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
```

- [ ] **Passo 5: rodar e ver passar**

Rodar: `bundle exec rspec spec/controllers/api/v1/accounts/ai/belezaki_connections_controller_spec.rb`
Esperado: 2 exemplos, 0 falhas.

- [ ] **Passo 6: commit**

```bash
bundle exec rubocop -a app/controllers/api/v1/accounts/ai/belezaki_connections_controller.rb
git add app/controllers/api/v1/accounts/ai/belezaki_connections_controller.rb config/routes.rb spec/controllers/api/v1/accounts/ai/belezaki_connections_controller_spec.rb
git commit -m "feat(athenas): the endpoint that binds an agent to its salon"
```

---

## Tarefa 4: A tela

**Arquivos:**
- Criar: `app/javascript/dashboard/components-next/athenas/AthenasBelezakiConnect.vue`
- Modificar: `app/javascript/dashboard/components-next/athenas/AthenasIntegrations.vue:149`
- Modificar: `app/javascript/dashboard/api/athenas.js`
- Modificar: `app/javascript/dashboard/i18n/locale/en/athenas.json`, `.../pt_BR/athenas.json`

**Interfaces consumidas:** os três endpoints da Tarefa 3.

- [ ] **Passo 1: os métodos de API**

Em `app/javascript/dashboard/api/athenas.js`, junto dos métodos de `calendarConnection`:

```js
  belezakiConnection(assistantId) {
    return axios.get(`${this.url}/${assistantId}/belezaki_connection`);
  },

  connectBelezaki(assistantId) {
    return axios.post(`${this.url}/${assistantId}/belezaki_connection`);
  },

  disconnectBelezaki(assistantId) {
    return axios.delete(`${this.url}/${assistantId}/belezaki_connection`);
  },
```

Confira o nome real da base (`this.url`) no arquivo antes de colar: siga o padrão dos
métodos de calendário que já existem ali.

- [ ] **Passo 2: as chaves de i18n**

Em `pt_BR/athenas.json`, dentro do mesmo objeto onde vivem as chaves do calendário:

```json
      "BELEZAKI": {
        "TITLE": "belezaki",
        "SUBTITLE": "Use a agenda que você já mantém no belezaki. Serviços, profissionais e horários continuam sendo configurados lá.",
        "CONNECT": "Conectar belezaki",
        "DISCONNECT": "Desconectar",
        "CONNECTED": "Conectado a {salon}",
        "ONLY_ONE": "Suportamos apenas uma integração de agenda por vez.",
        "ONLY_ONE_BODY": "Este agente já está usando o Google Calendar. Desconecte-o para conectar o belezaki.",
        "DISCONNECT_GOOGLE": "Desconectar Google Calendar",
        "BLOCKED": "Bloqueado enquanto o belezaki estiver conectado.",
        "ERROR": {
          "not_linked": "Sua conta não está ligada a um salão belezaki.",
          "not_configured": "A integração com o belezaki não está configurada. Nosso time foi avisado.",
          "agenda_taken": "Este agente já tem uma agenda conectada.",
          "probe_failed": "Não conseguimos falar com o belezaki agora. Tente de novo em instantes."
        }
      }
```

Em `en/athenas.json`, o mesmo objeto traduzido:

```json
      "BELEZAKI": {
        "TITLE": "belezaki",
        "SUBTITLE": "Use the agenda you already keep in belezaki. Services, professionals and hours stay configured there.",
        "CONNECT": "Connect belezaki",
        "DISCONNECT": "Disconnect",
        "CONNECTED": "Connected to {salon}",
        "ONLY_ONE": "We support one agenda integration at a time.",
        "ONLY_ONE_BODY": "This agent is using Google Calendar. Disconnect it to connect belezaki.",
        "DISCONNECT_GOOGLE": "Disconnect Google Calendar",
        "BLOCKED": "Blocked while belezaki is connected.",
        "ERROR": {
          "not_linked": "Your account is not linked to a belezaki salon.",
          "not_configured": "The belezaki integration is not configured. Our team has been notified.",
          "agenda_taken": "This agent already has an agenda connected.",
          "probe_failed": "We could not reach belezaki right now. Try again in a moment."
        }
      }
```

- [ ] **Passo 3: o componente**

```vue
<!-- app/javascript/dashboard/components-next/athenas/AthenasBelezakiConnect.vue -->
<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import AthenasAPI from 'dashboard/api/athenas';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistantId: { type: Number, required: true },
  // Whether a Google calendar holds this agent's agenda. One agenda per agent:
  // two would put two tools with the same name in one payload.
  googleConnected: { type: Boolean, default: false },
});

const emit = defineEmits(['connected', 'disconnectGoogle']);

const { t } = useI18n();

const connection = ref(null);
const isBusy = ref(false);
const errorCode = ref('');
const showOnlyOne = ref(false);

const load = async () => {
  try {
    const { data } = await AthenasAPI.belezakiConnection(props.assistantId);
    connection.value = data?.connection || null;
  } catch {
    connection.value = null;
  }
};

const connect = async () => {
  // Asked here rather than after a round trip: the operator gets the explanation
  // and the way out in the same click.
  if (props.googleConnected) {
    showOnlyOne.value = true;
    return;
  }
  isBusy.value = true;
  errorCode.value = '';
  try {
    const { data } = await AthenasAPI.connectBelezaki(props.assistantId);
    connection.value = data.connection;
    emit('connected');
  } catch (error) {
    errorCode.value = error?.response?.data?.error || 'probe_failed';
  } finally {
    isBusy.value = false;
  }
};

const disconnect = async () => {
  isBusy.value = true;
  try {
    await AthenasAPI.disconnectBelezaki(props.assistantId);
    connection.value = null;
    emit('connected');
  } finally {
    isBusy.value = false;
  }
};

onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-n-weak">
    <div class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('ATHENAS.BELEZAKI.TITLE') }}
        </h3>
        <p class="text-[13px] text-n-slate-11 leading-relaxed max-w-md">
          {{ t('ATHENAS.BELEZAKI.SUBTITLE') }}
        </p>
        <p v-if="connection" class="text-[13px] text-n-teal-11">
          {{ t('ATHENAS.BELEZAKI.CONNECTED', { salon: connection.salon_name }) }}
        </p>
      </div>

      <Button
        v-if="connection"
        variant="ghost"
        size="sm"
        :is-loading="isBusy"
        :label="t('ATHENAS.BELEZAKI.DISCONNECT')"
        @click="disconnect"
      />
      <Button
        v-else
        size="sm"
        :is-loading="isBusy"
        :label="t('ATHENAS.BELEZAKI.CONNECT')"
        @click="connect"
      />
    </div>

    <p v-if="errorCode" class="text-[12px] text-n-ruby-11">
      {{ t(`ATHENAS.BELEZAKI.ERROR.${errorCode}`) }}
    </p>

    <!-- One agenda per agent, said where the operator can act on it. -->
    <div
      v-if="showOnlyOne"
      class="flex flex-col gap-2 p-3 rounded-xl bg-n-amber-3 ring-1 ring-n-amber-6"
    >
      <p class="text-[13px] font-medium text-n-amber-12">
        {{ t('ATHENAS.BELEZAKI.ONLY_ONE') }}
      </p>
      <p class="text-[12px] text-n-amber-11">
        {{ t('ATHENAS.BELEZAKI.ONLY_ONE_BODY') }}
      </p>
      <div class="flex gap-2">
        <Button
          size="sm"
          :label="t('ATHENAS.BELEZAKI.DISCONNECT_GOOGLE')"
          @click="emit('disconnectGoogle')"
        />
        <Button
          variant="ghost"
          size="sm"
          :label="t('ATHENAS.BELEZAKI.CANCEL')"
          @click="showOnlyOne = false"
        />
      </div>
    </div>
  </section>
</template>
```

Adicione também `"CANCEL": "Cancelar"` / `"CANCEL": "Cancel"` no objeto `BELEZAKI` dos
dois arquivos de i18n.

- [ ] **Passo 4: montar em `AthenasIntegrations.vue`**

Importar o componente junto do `AthenasCalendarConnect` (linha 16) e renderizar
imediatamente **abaixo** dele (após a linha 149), passando se o Google está conectado e
tratando os dois eventos. O componente do calendário já expõe o estado da conexão dele —
leia o arquivo e reutilize a variável existente em vez de buscar de novo.

Quando o belezaki estiver conectado, o bloco do Google recebe uma sobreposição com
`t('ATHENAS.BELEZAKI.BLOCKED')` e o botão de conectar desabilitado.

- [ ] **Passo 5: verificar**

Rodar: `pnpm eslint` e conferir que os arquivos tocados passam.

- [ ] **Passo 6: commit**

```bash
git add app/javascript/dashboard/components-next/athenas/AthenasBelezakiConnect.vue app/javascript/dashboard/components-next/athenas/AthenasIntegrations.vue app/javascript/dashboard/api/athenas.js app/javascript/dashboard/i18n/locale/en/athenas.json app/javascript/dashboard/i18n/locale/pt_BR/athenas.json
git commit -m "feat(athenas): the screen where an agent picks belezaki as its agenda"
```

---

## Tarefa 5: Cliente HTTP endurecido

**Arquivos:**
- Modificar: `app/services/ai/belezaki/agent_client.rb`
- Testar: `spec/services/ai/belezaki/agent_client_spec.rb`

**Interfaces produzidas:**
- `Ai::Belezaki::AgentClient::Error#code` → String (`slot_taken`, `validation_failed`, `http_<n>`)
- `Error#status` → Integer, `Error#validation` → Array ou nil

- [ ] **Passo 1: escrever o teste que falha**

```ruby
# spec/services/ai/belezaki/agent_client_spec.rb
require 'rails_helper'

RSpec.describe Ai::Belezaki::AgentClient do
  let(:client) { described_class.new(external_id: 'ext-1', api_key: 'k') }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }

  # The Nest app mounts everything under a global 'api' prefix. Without it every
  # call is a 404 from the proxy and the integration silently never worked.
  it 'calls under the api prefix' do
    stub_request(:get, "#{base}/salon").to_return(status: 200, body: '{"name":"Bella"}')

    expect(client.salon['name']).to eq('Bella')
  end

  # Three different error shapes come out of this API. Matching on the message
  # string is what the field doc explicitly forbids.
  it 'keeps the code of a slot conflict' do
    stub_request(:post, "#{base}/appointments")
      .to_return(status: 409, body: '{"error":"slot_taken","message":"Horário não está mais disponível."}')

    expect { client.create_appointment({}) }.to raise_error(described_class::Error) { |e|
      expect(e.code).to eq('slot_taken')
    }
  end

  it 'recognises a validation array as validation, not as a message' do
    stub_request(:post, "#{base}/appointments")
      .to_return(status: 400, body: '{"message":["idempotency_key must be longer"],"error":"Bad Request","statusCode":400}')

    expect { client.create_appointment({}) }.to raise_error(described_class::Error) { |e|
      expect(e.code).to eq('validation_failed')
      expect(e.validation).to eq(['idempotency_key must be longer'])
    }
  end

  it 'retries a 500 and gives up after two tries' do
    stub_request(:get, "#{base}/salon").to_return(status: 500, body: '{"message":"boom"}')

    expect { client.salon }.to raise_error(described_class::Error)
    expect(a_request(:get, "#{base}/salon")).to have_been_made.twice
  end

  # A 4xx is the server saying "this request is wrong". Repeating it is waste,
  # and on a write it is a second appointment waiting to happen.
  it 'does not retry a 400' do
    stub_request(:get, "#{base}/salon").to_return(status: 400, body: '{"message":"bad"}')

    expect { client.salon }.to raise_error(described_class::Error)
    expect(a_request(:get, "#{base}/salon")).to have_been_made.once
  end
end
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `bundle exec rspec spec/services/ai/belezaki/agent_client_spec.rb`
Esperado: FAIL — prefixo errado e `Error` sem `#code`.

- [ ] **Passo 3: implementar**

Substituir em `agent_client.rb`:

```ruby
  PREFIX = '/api/agent/v1'.freeze

  # 10s to read, 25s to write. The server cuts its own statements at 20s, and a
  # client timeout shorter than the server's means giving up on a request that
  # is still going to write an appointment.
  READ_TIMEOUT = 10
  WRITE_TIMEOUT = 25
  RETRIABLE = [429, 500, 502, 503, 504].freeze
  MAX_ATTEMPTS = 2
```

`Error` passa a carregar o código:

```ruby
  class Error < StandardError
    attr_reader :code, :status, :validation

    def initialize(message, code: nil, status: nil, validation: nil)
      super(message)
      @code = code
      @status = status
      @validation = validation
    end
  end
```

E o `request` ganha retry e o parser dos três formatos:

```ruby
  def request(method, path, http_options, timeout)
    attempt = 0
    begin
      attempt += 1
      response = HTTParty.public_send(method, "#{self.class.base_url}#{PREFIX}#{path}",
                                      **http_options, headers: headers, timeout: timeout)
      return response.parsed_response if response.success?

      raise build_error(response)
    rescue Error => e
      raise e unless retriable?(e.status) && attempt < MAX_ATTEMPTS

      sleep(backoff(attempt))
      retry
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error.new(e.message, code: 'network') if attempt >= MAX_ATTEMPTS

      sleep(backoff(attempt))
      retry
    end
  end

  def retriable?(status)
    RETRIABLE.include?(status.to_i)
  end

  # Jittered so two conversations retrying the same second do not line up.
  def backoff(attempt)
    (0.4 * (2**(attempt - 1))) + (rand * 0.2)
  end

  # Three shapes really come out of this API, and only one of them is the one the
  # old doc described.
  def build_error(response)
    body = response.parsed_response
    status = response.code.to_i
    return Error.new(body['message'].to_s, code: body['error'], status: status) if conflict_shape?(body)

    if body.is_a?(Hash) && body['message'].is_a?(Array)
      return Error.new('Dados inválidos.', code: 'validation_failed', status: status, validation: body['message'])
    end

    message = (body.is_a?(Hash) ? body['message'] : nil).presence || "HTTP #{status}"
    Error.new(message.to_s, code: "http_#{status}", status: status)
  end

  def conflict_shape?(body)
    body.is_a?(Hash) && body['error'].is_a?(String) && !body.key?('statusCode')
  end
```

Os métodos públicos passam o timeout: `get` usa `READ_TIMEOUT`; `create_appointment` e
`availability_month` usam `WRITE_TIMEOUT`.

- [ ] **Passo 4: rodar e ver passar**

Rodar: `bundle exec rspec spec/services/ai/belezaki/agent_client_spec.rb spec/services/ai/belezaki/connect_service_spec.rb`
Esperado: todos passam. Se o spec da Tarefa 2 tinha o stub com a URL antiga, corrija-o
para `/api/agent/v1` agora.

- [ ] **Passo 5: commit**

```bash
bundle exec rubocop -a app/services/ai/belezaki/agent_client.rb
git add app/services/ai/belezaki/agent_client.rb spec/services/ai/belezaki/agent_client_spec.rb spec/services/ai/belezaki/connect_service_spec.rb
git commit -m "fix(athenas): the belezaki client was calling a path that does not exist"
```

---

## Tarefa 6: Executor — validar antes de enviar, normalizar o book

**Arquivos:**
- Modificar: `app/services/ai/belezaki/scheduling_tools.rb`
- Testar: `spec/services/ai/belezaki/scheduling_tools_spec.rb` (já existe — acrescentar)

- [ ] **Passo 1: escrever os testes que falham**

Acrescentar ao spec existente:

```ruby
  describe 'the booking answer' do
    # The turn guard reads a booking off "agendado": true. belezaki answers with
    # {"appointment": {"status": "confirmed"}}, so without normalising it every
    # SUCCESSFUL booking would have its reply suppressed as a false confirmation.
    it 'says agendado when the salon confirmed' do
      allow(client).to receive(:create_appointment).and_return(
        'appointment' => { 'id' => 'a1', 'status' => 'confirmed', 'start' => '2026-06-20T16:00:00-03:00' }
      )

      body = JSON.parse(tools.call('agendar', valid_booking_input))

      expect(body['agendado']).to be(true)
    end

    # A replay of a key whose appointment was cancelled answers 201 with
    # status "canceled". HTTP success is not the same as an appointment.
    it 'does not claim a booking when the status is not confirmed' do
      allow(client).to receive(:create_appointment).and_return(
        'appointment' => { 'id' => 'a1', 'status' => 'canceled' }
      )

      body = JSON.parse(tools.call('agendar', valid_booking_input))

      expect(body['agendado']).to be(false)
    end
  end

  describe 'validation before the call' do
    # 2026-02-30 does not fail on their side: it answers 200 with the real slots
    # of March 2nd under an envelope that says February 30th.
    it 'refuses a date that does not exist instead of asking for it' do
      expect(client).not_to receive(:availability)

      body = JSON.parse(tools.call('consultar_horarios', { 'service_id' => SecureRandom.uuid, 'date' => '2026-02-30' }))

      expect(body['error']).to eq('invalid_input')
    end
  end
```

Defina `valid_booking_input` como um hash com `service_id` e `professional_id` UUID,
`start` ISO 8601 e `client_name`/`client_phone`, seguindo o estilo do spec existente.

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `bundle exec rspec spec/services/ai/belezaki/scheduling_tools_spec.rb`
Esperado: FAIL nos três novos.

- [ ] **Passo 3: implementar**

`professional_id` entra em `required` na `booking_tool` (a auto-escolha do belezaki pode
devolver profissional oculto que o próprio book rejeita, e abre uma segunda janela de
corrida) e a descrição passa a mandar copiar o `professional_id` do slot escolhido.

Validação antes de despachar:

```ruby
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # Sent unvalidated, these become 500s on the salon side — or worse, a 200 for a
  # day that does not exist.
  def invalid_input(input, keys)
    return 'id inválido' if keys.include?(:ids) && !uuid?(input['service_id'])
    return 'data inválida' if keys.include?(:date) && !real_date?(input['date'])

    nil
  end

  def uuid?(value)
    UUID.match?(value.to_s)
  end

  def real_date?(value)
    Date.strptime(value.to_s, '%Y-%m-%d').present?
  rescue Date::Error, TypeError
    false
  end
```

O retorno de um input inválido é `{ error: 'invalid_input', message: ... }` — erro vira
dado, como o resto do executor.

Normalização do book:

```ruby
  def book(input)
    @performed_write = true
    response = @client.create_appointment(...)
    appointment = response.is_a?(Hash) ? response['appointment'] : nil
    confirmed = appointment.is_a?(Hash) && appointment['status'] == 'confirmed'
    return { agendado: false, motivo: appointment&.dig('status') || 'sem confirmação' } unless confirmed

    { agendado: true, id: appointment['id'], inicio: appointment['start'],
      servico: appointment['service'], profissional: appointment['professional'] }
  end
```

- [ ] **Passo 4: rodar e ver passar**

Rodar: `bundle exec rspec spec/services/ai/belezaki/scheduling_tools_spec.rb`

- [ ] **Passo 5: commit**

```bash
bundle exec rubocop -a app/services/ai/belezaki/scheduling_tools.rb
git add app/services/ai/belezaki/scheduling_tools.rb spec/services/ai/belezaki/scheduling_tools_spec.rb
git commit -m "fix(athenas): a booking is only booked when the salon says confirmed"
```

---

## Tarefa 7: O gate — só agente conectado carrega as ferramentas

Esta é a tarefa que resolve o custo. **Só execute depois que a Tarefa 4 estiver de pé**,
porque ela desliga o caminho automático.

**Arquivos:**
- Modificar: `app/services/ai/autopilot_reply_service.rb` (`own_tools`, `generate_response`)
- Testar: `spec/services/ai/autopilot_reply_service_spec.rb`

- [ ] **Passo 1: escrever o teste que falha**

```ruby
  describe 'belezaki is opt-in per agent' do
    def tool_names(assistant)
      described_class.new(conversation: conversation, assistant: assistant)
                     .send(:own_tools).definitions.map { |d| d[:name] }
    end

    # The whole point of the module: a linked ACCOUNT used to switch scheduling on
    # for every one of its agents, paying five tool schemas per turn on agents
    # that book nothing.
    it 'offers no belezaki tool to an agent that has not connected one' do
      allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return('ext-1')

      expect(tool_names(assistant)).not_to include('sugerir_dias')
    end

    it 'offers them once the agent is connected' do
      Ai::Belezaki::Connection.create!(
        ai_assistant: assistant, account: account, external_id: 'ext-1', status: 'active'
      )

      expect(tool_names(assistant)).to include('sugerir_dias')
    end
  end
```

- [ ] **Passo 2: rodar e ver falhar**

Rodar: `bundle exec rspec spec/services/ai/autopilot_reply_service_spec.rb -e 'belezaki is opt-in'`

- [ ] **Passo 3: implementar**

Em `own_tools`, acrescentar a terceira entrada:

```ruby
      parts << [belezaki_definitions, belezaki_executor] if belezaki_connection.present?
```

com:

```ruby
  # Per AGENT, and only when connected. Resolving this from the account is what
  # used to put five tool schemas in every turn of every agent of a linked
  # account, including the ones that never book anything.
  def belezaki_connection
    return @belezaki_connection if defined?(@belezaki_connection)

    @belezaki_connection = @assistant.belezaki_connection&.then { |c| c.active? ? c : nil }
  end

  def belezaki_definitions
    Ai::Belezaki::SchedulingTools.definitions(include_booking: true)
  end

  def belezaki_executor
    @belezaki_executor ||= Ai::Belezaki::SchedulingTools.new(
      Ai::Belezaki::AgentClient.new(external_id: belezaki_connection.external_id),
      scope: "conv-#{@conversation.id}",
      contact: { name: @conversation.contact&.name, phone: @conversation.contact&.phone_number }
    )
  end
```

Em `generate_response`, apagar o fallback automático — o método passa a ser:

```ruby
  def generate_response(messages)
    own = own_tools
    return run_own_tool_loop(messages, own) if own.any?

    call_claude(messages)
  end
```

Remover então `belezaki_client` e `run_tool_loop`, **depois de confirmar com
`rg -n "run_tool_loop|belezaki_client" app spec` que nada mais os usa.** Se algum spec
usar, atualize-o na mesma tarefa.

- [ ] **Passo 4: rodar a suíte tocada**

Rodar: `bundle exec rspec spec/services/ai/autopilot_reply_service_spec.rb spec/services/ai/belezaki`
Esperado: tudo verde.

- [ ] **Passo 5: commit**

```bash
bundle exec rubocop -a app/services/ai/autopilot_reply_service.rb
git add app/services/ai/autopilot_reply_service.rb spec/services/ai/autopilot_reply_service_spec.rb
git commit -m "fix(athenas): every agent of a linked account was paying for the salon agenda"
```

- [ ] **Passo 6: conferir quem perdeu a agenda**

Antes de subir, no console de produção:

```ruby
Ai::Assistant.joins(:account).find_each do |a|
  next if a.belezaki_connection.present? || a.calendar_connections.active.exists?
  ext = Ai::Belezaki::TenantResolver.external_id(a.account)
  puts "assistant=#{a.id} #{a.name} account=#{a.account_id} ext=#{ext}" if ext.present?
end
```

Cada linha é um agente que hoje recebe o belezaki automaticamente e passará a precisar
conectar pela tela. Se a lista não for vazia, avise esses operadores antes do deploy.

---

## Auto-revisão

**Cobertura do spec.** Conexão por agente → T1-T3; detectar e confirmar via `GET /salon`
→ T2; exclusividade com popup e bloqueio → T2 (backend) e T4 (tela); tabela com
`external_id` congelado → T1; corte do caminho automático → T7; prefixo, código de erro,
retry, timeouts → T5; validação antes de enviar, `professional_id` obrigatório,
normalização do book → T6; risco da virada → T7 passo 6.

**Fora deste plano, de propósito:** as regras de prompt da seção 5 do design (não afirmar
WhatsApp nem Google, encaminhar cancelamento) entram junto com a instrução de agenda
quando o provider for belezaki — vira uma tarefa própria depois que T7 estiver verde, para
não misturar mudança de prompt com mudança de payload no mesmo commit.

**Nomes conferidos entre tarefas:** `agenda_provider`, `belezaki_connection`,
`Ai::Belezaki::ConnectService::{NotLinked,NotConfigured,AgendaTaken}`, `Error#code`,
`external_id`, e os códigos `not_linked` / `not_configured` / `agenda_taken` /
`probe_failed` usados em T3 e nas chaves de i18n de T4.

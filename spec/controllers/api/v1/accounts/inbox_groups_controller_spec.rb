require 'rails_helper'

RSpec.describe Api::V1::Accounts::InboxGroupsController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inbox_groups" }

  describe 'GET /api/v1/accounts/:id/inbox_groups' do
    it 'lists the account groups to any member, in order' do
      create(:inbox_group, account: account, name: 'Vendas', position: 2)
      create(:inbox_group, account: account, name: 'WhatsApp', kind: 'whatsapp', position: 1)
      create(:inbox_group, account: create(:account), name: 'Outra conta')

      get base_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('name')).to eq(%w[WhatsApp Vendas])
    end
  end

  describe 'POST /api/v1/accounts/:id/inbox_groups' do
    it 'lets an administrator rename a kind by creating its group' do
      post base_url, params: { inbox_group: { name: 'Atendimento WhatsApp', kind: 'whatsapp' } },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.inbox_groups.last).to have_attributes(name: 'Atendimento WhatsApp', kind: 'whatsapp')
    end

    it 'keeps one group per kind' do
      create(:inbox_group, account: account, kind: 'whatsapp')

      post base_url, params: { inbox_group: { name: 'Outro', kind: 'whatsapp' } },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'is closed to agents' do
      post base_url, params: { inbox_group: { name: 'Vendas' } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH and DELETE /api/v1/accounts/:id/inbox_groups/:id' do
    let!(:group) { create(:inbox_group, account: account, name: 'Vendas') }
    let!(:inbox) { create(:inbox, account: account, inbox_group: group) }

    it 'renames without changing the kind' do
      patch "#{base_url}/#{group.id}", params: { inbox_group: { name: 'Pós-venda', kind: 'whatsapp' } },
                                       headers: admin.create_new_auth_token, as: :json

      expect(group.reload).to have_attributes(name: 'Pós-venda', kind: nil)
    end

    it 'sends its inboxes back to the group of their kind when deleted' do
      delete "#{base_url}/#{group.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.inbox_group_id).to be_nil
    end

    it 'does not reach another account' do
      foreign = create(:inbox_group, account: create(:account))

      delete "#{base_url}/#{foreign.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'moving an inbox' do
    it 'moves it through the inbox update' do
      inbox = create(:inbox, account: account)
      group = create(:inbox_group, account: account)

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", params: { inbox_group_id: group.id },
                                                                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.inbox_group_id).to eq(group.id)
      expect(response.parsed_body['inbox_group_id']).to eq(group.id)
    end

    it 'accepts a group of the same account only' do
      inbox = create(:inbox, account: account)
      foreign = create(:inbox_group, account: create(:account))

      expect(inbox.update(inbox_group: foreign)).to be(false)
      expect(inbox.errors[:inbox_group]).to be_present
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SidebarLayoutController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:super_admin) { create(:super_admin) }
  let(:url) { '/api/v1/sidebar_layout' }
  let(:layout) do
    {
      version: 1,
      groups: [{ id: 'g_gestao', label: 'Gestão', order: 0 }],
      items: { 'Report' => { group: 'g_gestao', order: 0 } }
    }
  end

  def save(as_user, body = layout)
    put url, params: { layout: body }, headers: as_user.create_new_auth_token, as: :json
  end

  it 'stores the layout a super admin builds' do
    save(super_admin)

    expect(response).to have_http_status(:success)
    expect(InstallationConfig.find_by(name: 'SIDEBAR_LAYOUT').value['groups'].first['label']).to eq('Gestão')
  end

  # The tab hides itself in the dashboard, but a hidden tab is convenience, not
  # authorisation: this endpoint rewrites the menu of every tenant on the
  # installation.
  it 'refuses an account administrator' do
    save(admin)

    expect(response).to have_http_status(:unauthorized)
    expect(InstallationConfig.find_by(name: 'SIDEBAR_LAYOUT')).to be_nil
  end

  it 'refuses somebody who is not signed in' do
    put url, params: { layout: layout }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  # The screen always sends the whole layout, so a group deleted there has to
  # disappear here — surviving a merge would resurrect it on the next reload.
  it 'replaces the stored layout instead of merging into it' do
    save(super_admin)
    save(super_admin, { version: 1, groups: [], items: {} })

    expect(InstallationConfig.find_by(name: 'SIDEBAR_LAYOUT').value['groups']).to eq([])
  end

  # One key per menu item, and menu items are ours to add over time. An
  # allow-list would drop the placement of every tab we forgot to add to it.
  it 'keeps the placement of an item it has never heard of' do
    save(super_admin, { version: 1, groups: [], items: { 'AlgoNovo' => { order: 3 } } })

    expect(InstallationConfig.find_by(name: 'SIDEBAR_LAYOUT').value['items']['AlgoNovo']['order']).to eq(3)
  end
end

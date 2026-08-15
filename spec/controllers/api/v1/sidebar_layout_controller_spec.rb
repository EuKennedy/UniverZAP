# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SidebarLayoutController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:super_admin) { create(:super_admin) }
  let(:url) { '/api/v1/sidebar_layout' }
  let(:layout) do
    {
      version: 2,
      order: %w[Inbox g_gestao],
      groups: [{ id: 'g_gestao', label: 'Gestão', icon: 'i-lucide-briefcase', items: %w[Report] }],
      items: { 'Report' => { hidden: true } },
      home: { item: 'Kanban', route: 'kanban_overview', params: {} }
    }
  end

  def save(as_user, body = layout)
    put url, params: { layout: body }, headers: as_user.create_new_auth_token, as: :json
  end

  def stored
    InstallationConfig.find_by(name: 'SIDEBAR_LAYOUT')&.value
  end

  it 'stores the layout a super admin builds' do
    save(super_admin)

    expect(response).to have_http_status(:success)
    expect(stored['groups'].first['label']).to eq('Gestão')
  end

  # The order is what makes "a group, then a loose tab, then another group"
  # expressible at all, and it is a bare list of names: strip it and every
  # section falls to the bottom of the bar.
  it 'keeps the order of the top level' do
    save(super_admin)

    expect(stored['order']).to eq(%w[Inbox g_gestao])
  end

  it 'keeps which items were put inside a group' do
    save(super_admin)

    expect(stored['groups'].first['items']).to eq(%w[Report])
  end

  # The screen sends a route name and the params it needs, never a path: one
  # global setting is read by people in different accounts.
  it 'keeps the home screen, empty params and all' do
    save(super_admin)

    expect(stored['home']).to eq('item' => 'Kanban', 'route' => 'kanban_overview', 'params' => {})
  end

  # The tab hides itself in the dashboard, but a hidden tab is convenience, not
  # authorisation: this endpoint rewrites the menu of every tenant on the
  # installation.
  it 'refuses an account administrator' do
    save(admin)

    expect(response).to have_http_status(:unauthorized)
    expect(stored).to be_nil
  end

  it 'refuses somebody who is not signed in' do
    put url, params: { layout: layout }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  # The screen always sends the whole layout, so a group deleted there has to
  # disappear here — surviving a merge would resurrect it on the next reload,
  # and so would a home screen somebody had just cleared.
  it 'replaces the stored layout instead of merging into it' do
    save(super_admin)
    save(super_admin, { version: 2, order: [], groups: [], items: {} })

    expect(stored['groups']).to eq([])
    expect(stored['home']).to be_nil
  end

  # One key per menu item, and menu items are ours to add over time. An
  # allow-list would drop the placement of every tab we forgot to add to it.
  it 'keeps the placement of an item it has never heard of' do
    save(super_admin, { version: 2, order: %w[AlgoNovo], groups: [], items: { 'AlgoNovo' => { label: 'Algo novo' } } })

    expect(stored['items']['AlgoNovo']['label']).to eq('Algo novo')
  end

  # A layout saved before the rebuild is stored as it arrives; the dashboard
  # reads version 1 and converts it, so a super admin's groups survive.
  it 'still accepts a layout in the previous shape' do
    save(super_admin, { version: 1, groups: [{ id: 'g_1', label: 'Gestão', order: 0 }], items: { 'Report' => { group: 'g_1', order: 0 } } })

    expect(response).to have_http_status(:success)
    expect(stored['version']).to eq(1)
  end
end

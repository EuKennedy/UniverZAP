# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../lib/univerzap_ci/test_plan'

RSpec.describe UniverzapCi::TestPlan do
  let(:specs) do
    {
      'spec/services/woocommerce/client_spec.rb' => 'RSpec.describe Woocommerce::Client do',
      'spec/jobs/woocommerce/sync_job_spec.rb' => 'allow(Woocommerce::Client).to receive(:new)',
      'spec/models/store_order_spec.rb' => 'RSpec.describe StoreOrder do',
      'spec/models/contact_spec.rb' => 'RSpec.describe Contact do',
      'spec/services/broadcasts/sender_spec.rb' => 'let(:contact) { create(:contact, account: account) }',
      'spec/controllers/landing_controller_spec.rb' => 'RSpec.describe LandingController, type: :request do',
      'spec/services/ai/period_spec.rb' => 'RSpec.describe Ai::Period do'
    }
  end

  def plan(*changed, deleted: [])
    described_class.new(changed + deleted, specs: specs.keys, read: ->(path) { specs.fetch(path) },
                                           exists: ->(path) { deleted.exclude?(path) })
  end

  it 'runs the mirror spec and every spec citing the changed class, nothing else', :aggregate_failures do
    result = plan('app/services/woocommerce/client.rb')

    expect(result.rspec).to eq(%w[spec/jobs/woocommerce/sync_job_spec.rb spec/services/woocommerce/client_spec.rb])
    expect(result).not_to be_full
  end

  it 'reaches the specs that build a changed model through its factory' do
    expect(plan('app/models/contact.rb').rspec).to eq(%w[spec/models/contact_spec.rb spec/services/broadcasts/sender_spec.rb])
  end

  it 'runs a spec that changed by itself' do
    expect(plan('spec/models/contact_spec.rb').rspec).to eq(%w[spec/models/contact_spec.rb])
  end

  it 'takes a view to the specs of its controller' do
    expect(plan('app/views/landing/lpteste.html.erb').rspec).to eq(%w[spec/controllers/landing_controller_spec.rb])
  end

  it 'still runs the specs that cite a class that was deleted' do
    expect(plan(deleted: ['app/models/store_order.rb']).rspec).to eq(%w[spec/models/store_order_spec.rb])
  end

  it 'lints and front-tests only the changed files that still exist', :aggregate_failures do
    result = plan('app/javascript/dashboard/components-next/store/StoreOrdersCard.vue', 'app/services/woocommerce/client.rb',
                  deleted: ['app/javascript/dashboard/api/old.js'])

    expect(result.vitest).to eq(%w[app/javascript/dashboard/components-next/store/StoreOrdersCard.vue])
    expect(result.eslint).to eq(%w[app/javascript/dashboard/components-next/store/StoreOrdersCard.vue])
    expect(result.rubocop).to eq(%w[app/services/woocommerce/client.rb])
  end

  it 'runs nothing for a change outside the code' do
    result = plan('docs/README.md', 'db/migrate/20261029120000_add_column.rb')

    expect([result.rspec, result.vitest, result.eslint, result.full?]).to eq([[], [], [], false])
  end

  it 'falls back to the whole suite when the change holds the suite up' do
    %w[Gemfile.lock pnpm-lock.yaml spec/rails_helper.rb spec/factories/contacts.rb config/initializers/sidekiq.rb
       .github/workflows/univerzap-ci.yml lib/univerzap_ci/test_plan.rb app/models/application_record.rb].each do |path|
      expect(plan(path)).to be_full, path
    end
  end
end

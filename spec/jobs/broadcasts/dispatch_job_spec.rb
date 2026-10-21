# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::DispatchJob do
  let(:account) { create(:account) }
  let(:first) { create(:contact, account: account, phone_number: '+5531900000001') }
  let(:second) { create(:contact, account: account, phone_number: '+5531900000002') }
  let(:broadcast) do
    create(:broadcast, account: account, status: :running, audience: { 'contact_ids' => [first.id] })
  end

  # Dentro do horário comercial: fora dele o job só se reagenda.
  around { |example| travel_to(ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-10-20 10:00')) { example.run } }

  # Fake send: marks the recipient sent, the way a real dispatch leaves it.
  before do
    allow(Broadcasts::RecipientSenderService).to receive(:new) do |recipient|
      sender = instance_double(Broadcasts::RecipientSenderService)
      allow(sender).to receive(:perform) { recipient.update!(status: :sent, sent_at: Time.current) }
      sender
    end
  end

  # `reload` first: the job runs on its own instance and leaves the row
  # `completed`, while this memoized object still says `running`. Without it
  # dirty tracking sees no status change, skips the write, and the job exits on
  # its first line — which also made the idempotence example pass without ever
  # reaching the diff.
  def relaunch_with(*contacts)
    broadcast.reload.update!(audience: { 'contact_ids' => contacts.map(&:id) }, status: :running)
    described_class.perform_now(broadcast.id)
  end

  # Tested on one contact, then relaunched with more. The old early return on
  # `exists?` skipped the newcomers for good and the screen kept showing the
  # single test send.
  describe 'relancar depois de adicionar contatos' do
    before { described_class.perform_now(broadcast.id) }

    it 'alcanca os contatos novos' do
      relaunch_with(first, second)

      expect(broadcast.broadcast_recipients.pluck(:contact_id)).to contain_exactly(first.id, second.id)
    end

    it 'nao manda de novo para quem ja recebeu' do
      relaunch_with(first, second)

      expect(Broadcasts::RecipientSenderService).to have_received(:new).twice
    end
  end

  # There is no unique index on (broadcast_id, contact_id); the guarantee lives
  # in the diff. Running the build again must never add a second row.
  describe 'idempotencia' do
    it 'nunca cria dois destinatarios para o mesmo contato' do
      described_class.perform_now(broadcast.id)
      relaunch_with(first)
      relaunch_with(first)

      expect(broadcast.broadcast_recipients.where(contact_id: first.id).count).to eq(1)
    end
  end
end

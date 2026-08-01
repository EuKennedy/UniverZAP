require 'rails_helper'

RSpec.describe Captain::AssistantResponse do
  describe '.search (tenant isolation)' do
    let(:account) { create(:account) }

    before do
      embedding_service = instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.1))
      allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    end

    # The security property is that the vector search runs on the account-scoped
    # relation, never the whole table. We assert by_account is applied and that
    # nearest_neighbors is invoked on that scope (SQL semantics then guarantee no
    # other tenant's rows can come back), keeping the test off real pgvector.
    it 'applies the account scope before running the vector search' do
      scoped = described_class.where(account_id: account.id)
      allow(described_class).to receive(:by_account).with(account.id).and_return(scoped)
      allow(scoped).to receive(:nearest_neighbors).and_return(scoped)

      described_class.search('qualquer coisa', account_id: account.id)

      expect(described_class).to have_received(:by_account).with(account.id)
      expect(scoped).to have_received(:nearest_neighbors).with(:embedding, anything, distance: 'cosine')
    end

    it 'requires an account_id so an unscoped search is impossible' do
      expect { described_class.search('qualquer coisa') }.to raise_error(ArgumentError)
    end
  end
end

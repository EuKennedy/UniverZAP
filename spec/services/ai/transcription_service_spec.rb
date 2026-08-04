# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TranscriptionService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account, encrypted_elevenlabs_key: 'el-key') }
  let(:conversation) { create(:conversation, account: account) }
  # A real WhatsApp voice note carries NO text. That is the whole reason the
  # transcription matters: with content present, content_for_llm returns the
  # text and never looks at the attachment.
  let(:message) do
    create(:message, conversation: conversation, account: account, message_type: 'incoming', content: nil)
  end
  let(:adapter) { instance_double(Ai::Transcription::ElevenLabsAdapter, model: 'scribe_v2') }

  before do
    account.update!(token_credit_balance_cents_brl: 100_000)
    allow(Ai::Transcription::ElevenLabsAdapter).to receive(:new).and_return(adapter)
    allow(adapter).to receive(:call).and_return(
      Ai::Transcription::Result.new(text: 'quanto custa a progressiva?', model: 'scribe_v2', duration_seconds: 12.0)
    )
  end

  def audio(bytes: 40_000, content_type: 'audio/ogg')
    attachment = message.attachments.create!(account_id: account.id, file_type: :audio)
    attachment.file.attach(
      io: StringIO.new('0' * bytes), filename: 'ptt.ogg', content_type: content_type
    )
    attachment
  end

  def run(attachment)
    described_class.new(attachment: attachment, assistant: assistant).perform
  end

  describe 'what the agent ends up reading' do
    # The contract this whole service exists to fill: Message#content_for_llm
    # already turns this field into "[Voice Message] ..." for the prompt.
    it 'writes the transcription onto the attachment' do
      attachment = audio

      run(attachment)

      expect(attachment.reload.meta['transcribed_text']).to eq('quanto custa a progressiva?')
    end

    it 'makes the voice note readable by the agent' do
      attachment = audio
      run(attachment)

      expect(message.reload.content_for_llm).to include('quanto custa a progressiva?')
    end

    # `meta` is shared with whatever else the channel stored here.
    it 'merges instead of replacing the rest of the metadata' do
      attachment = audio
      attachment.update!(meta: { 'waha_id' => 'abc' })

      run(attachment)

      expect(attachment.reload.meta).to include('waha_id' => 'abc')
    end

    it 'does not pay twice for audio already transcribed' do
      attachment = audio
      attachment.update!(meta: { 'transcribed_text' => 'já transcrito' })

      expect(run(attachment)).to eq('já transcrito')
      expect(adapter).not_to have_received(:call)
    end
  end

  describe 'billing' do
    # Anything that spends money without passing through the ledger is spend we
    # absorb, which is the hole the whole credit system exists to close.
    it 'logs the call on the invocation log under its own phase' do
      expect { run(audio) }.to change(Ai::Invocation, :count).by(1)

      invocation = Ai::Invocation.last
      expect(invocation.phase).to eq('transcription')
      expect(invocation.model).to eq('scribe_v2')
      expect(invocation.cost_brl).to be > 0
    end

    it 'debits the account that owns the audio' do
      expect { run(audio) }
        .to change { Ai::CreditLedgerEntry.where(account: account, kind: 'consumption').count }.by(1)
    end

    it 'refuses when the account cannot pay for it' do
      account.update!(token_credit_balance_cents_brl: 0, token_credit_grace_used: true)

      expect { run(audio) }.to raise_error(Ai::CreditLedger::QuotaExhaustedError)
    end

    # The transcription is already saved by then; losing the reply over a
    # billing hiccup would be the wrong trade.
    it 'keeps the transcription when the cost cannot be recorded' do
      allow(Ai::Invocation).to receive(:create!).and_raise(StandardError, 'boom')
      attachment = audio

      expect { run(attachment) }.not_to raise_error
      expect(attachment.reload.meta['transcribed_text']).to be_present
    end
  end

  describe 'what it refuses to touch' do
    it 'ignores an attachment that is not audio' do
      attachment = message.attachments.create!(account_id: account.id, file_type: :image)

      expect(run(attachment)).to be_nil
    end

    it 'ignores audio past the provider size limit' do
      expect(run(audio(bytes: described_class::MAX_BYTES + 1))).to be_nil
    end

    # A one-hour file is a recording, not a message to an agent.
    it 'ignores audio far longer than a voice note' do
      long = described_class::MAX_DURATION_SECONDS * described_class::PESSIMISTIC_BYTES_PER_SECOND * 2

      expect(run(audio(bytes: long))).to be_nil
    end
  end

  describe 'provider choice' do
    # Scribe is markedly better on noisy Brazilian Portuguese phone audio, so
    # a workspace that configured it must not silently fall back.
    it 'prefers ElevenLabs when the workspace has a key' do
      run(audio)

      expect(Ai::Transcription::ElevenLabsAdapter).to have_received(:new).with(api_key: 'el-key')
    end

    it 'falls back to OpenAI so a workspace without a key still gets voice notes read' do
      assistant.update!(encrypted_elevenlabs_key: nil, encrypted_openai_key: 'oa-key')
      openai = instance_double(Ai::Transcription::OpenAiAdapter, model: 'gpt-4o-mini-transcribe')
      allow(Ai::Transcription::OpenAiAdapter).to receive(:new).and_return(openai)
      allow(openai).to receive(:call).and_return(
        Ai::Transcription::Result.new(text: 'oi', model: 'gpt-4o-mini-transcribe', duration_seconds: 3.0)
      )
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ELEVENLABS_API_KEY', nil).and_return(nil)

      run(audio)

      expect(Ai::Transcription::OpenAiAdapter).to have_received(:new).with(api_key: 'oa-key')
    end

    it 'does nothing at all when no provider is configured' do
      assistant.update!(encrypted_elevenlabs_key: nil, encrypted_openai_key: nil)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ELEVENLABS_API_KEY', nil).and_return(nil)
      allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return(nil)

      expect(run(audio)).to be_nil
    end
  end

  describe 'tenant isolation' do
    # The audio, the key and the bill all belong to one account. A crossed id
    # must never make one workspace's voice note run on another's credential.
    it 'refuses an attachment from another account' do
      other_assistant = create(:ai_assistant, account: create(:account))

      expect(described_class.new(attachment: audio, assistant: other_assistant).perform).to be_nil
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ThemeService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  def asked(text, sandbox: false)
    create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                           user_message: text, ai_response: 'ok', sandbox: sandbox)
  end

  def terms(result)
    result[:themes].pluck(:term)
  end

  it 'surfaces what customers repeat' do
    3.times { asked('quanto custa a progressiva?') }
    2.times { asked('vocês fazem progressiva sem formol?') }

    expect(terms(described_class.new(assistant: assistant).perform)).to include('progressiva')
  end

  it 'ignores a term nobody repeated' do
    asked('vocês trabalham com henna?')

    expect(terms(described_class.new(assistant: assistant).perform)).not_to include('henna')
  end

  it 'drops filler words that carry no signal' do
    3.times { asked('bom dia, vocês podem me ajudar?') }

    expect(terms(described_class.new(assistant: assistant).perform)).not_to include('podem', 'ajudar')
  end

  # Someone writing "preço, preço, preço" is one person asking about price, not
  # three.
  it 'counts one occurrence per question, not per mention' do
    asked('preço preço preço da progressiva')
    asked('qual o preço?')

    theme = described_class.new(assistant: assistant).perform[:themes].find { |t| t[:term] == 'preço' }
    expect(theme[:count]).to eq(2)
  end

  # The playground is the operator talking to themselves; counting it would
  # report their own curiosity as a market signal.
  it 'excludes playground questions' do
    3.times { asked('quanto custa a progressiva?', sandbox: true) }

    expect(described_class.new(assistant: assistant).perform[:themes]).to be_empty
  end

  it 'carries a real question as the example for each term' do
    2.times { asked('quanto custa a progressiva sem formol?') }

    theme = described_class.new(assistant: assistant).perform[:themes].first
    expect(theme[:sample]).to include('progressiva')
  end

  it 'returns an empty but well-formed payload for an agent nobody asked anything' do
    result = described_class.new(assistant: assistant).perform

    expect(result[:total_questions]).to eq(0)
    expect(result[:themes]).to be_empty
  end
end

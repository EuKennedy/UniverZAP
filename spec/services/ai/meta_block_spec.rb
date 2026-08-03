# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::MetaBlock do
  describe '.extract' do
    it 'returns the text untouched when there is no meta block' do
      expect(described_class.extract('Fica R$ 189,90 no Pix.')).to eq(['Fica R$ 189,90 no Pix.', nil])
    end

    it 'strips the block and returns the confidence' do
      text, confidence = described_class.extract(%(Fica R$ 189,90.\n<meta>{"confidence":0.94}</meta>))

      expect(text).to eq('Fica R$ 189,90.')
      expect(confidence).to eq(0.94)
    end

    it 'strips a block the model wrapped in a code fence' do
      text, = described_class.extract(%(Ok.\n```json\n<meta>{"confidence":0.2}</meta>\n```))

      expect(text).to eq('Ok.')
    end

    it 'never leaks the tag when the JSON is malformed' do
      text, confidence = described_class.extract("Ok.\n<meta>not json</meta>")

      expect(text).to eq('Ok.')
      expect(confidence).to be_nil
    end

    # A truncated generation can end mid-tag. Whatever follows an unclosed
    # `<meta>` is internal by definition and must be cut, not delivered.
    it 'cuts a dangling unclosed block' do
      text, = described_class.extract(%(Ok.\n<meta>{"confidence":0.9))

      expect(text).to eq('Ok.')
    end

    # Anything tag-shaped is internal by definition. A stray closing tag in
    # front of a customer, signed with the salon's name, is the one outcome
    # this module exists to make impossible.
    it 'removes a stray closing tag that was never opened' do
      text, = described_class.extract('Fica R$ 189,90. </meta>')

      expect(text).to eq('Fica R$ 189,90.')
    end

    it 'removes a tag written with stray spaces, JSON and all' do
      text, confidence = described_class.extract('Ok. < meta >{"confidence":0.5}< /meta >')

      expect(text).to eq('Ok.')
      expect(confidence).to eq(0.5)
    end

    it 'clamps a confidence the model reported out of range' do
      expect(described_class.extract(%(a<meta>{"confidence":7}</meta>)).last).to eq(1.0)
    end

    it 'ignores a non numeric confidence' do
      expect(described_class.extract(%(a<meta>{"confidence":"alta"}</meta>)).last).to be_nil
    end
  end
end

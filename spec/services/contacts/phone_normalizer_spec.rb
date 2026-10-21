require 'rails_helper'

RSpec.describe Contacts::PhoneNormalizer do
  it 'turns a typed Brazilian mobile into the stored E.164 shape' do
    expect(described_class.normalize('(31) 98765-4321')).to eq('+5531987654321')
  end

  it 'adds the ninth digit an old checkout left out' do
    expect(described_class.normalize('31 8765-4321')).to eq('+5531987654321')
  end

  it 'keeps a landline as it is' do
    expect(described_class.normalize('(31) 3333-4444')).to eq('+553133334444')
  end

  it 'trusts the + of an international number' do
    expect(described_class.normalize('+1 415 555 0100')).to eq('+14155550100')
  end

  it 'gives nothing for a number too short to be one' do
    expect(described_class.normalize('12345')).to be_nil
  end
end

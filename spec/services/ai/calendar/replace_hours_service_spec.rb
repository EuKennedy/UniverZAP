require 'rails_helper'

RSpec.describe Ai::Calendar::ReplaceHoursService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:connection) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )
  end
  let(:professional) do
    connection.professionals.create!(
      ai_assistant_id: assistant.id, account_id: account.id, name: 'Agenda do salão', calendar_id: 'primary'
    )
  end

  def replace(ranges)
    described_class.new(professional: professional, ranges: ranges).perform
  end

  # A salon stops for lunch, so a weekday is several ranges and not one pair.
  it 'stores a day broken by the lunch break as two ranges' do
    replace([
              { weekday: 1, starts_at: '09:00', ends_at: '12:00' },
              { weekday: 1, starts_at: '13:00', ends_at: '18:00' }
            ])

    expect(professional.hours.where(weekday: 1).count).to eq(2)
  end

  # The screen edits the week as one object: emptying Saturday IS the delete.
  it 'replaces the whole week instead of merging into it' do
    replace([{ weekday: 6, starts_at: '09:00', ends_at: '13:00' }])
    replace([{ weekday: 1, starts_at: '09:00', ends_at: '18:00' }])

    expect(professional.hours.pluck(:weekday)).to eq([1])
  end

  # Two overlapping ranges would offer 14:00 twice in the same list, and no
  # single row is wrong on its own, so the model cannot catch it.
  it 'refuses overlapping ranges on the same day' do
    expect do
      replace([
                { weekday: 2, starts_at: '09:00', ends_at: '13:00' },
                { weekday: 2, starts_at: '12:00', ends_at: '18:00' }
              ])
    end.to raise_error(described_class::Overlap)
  end

  it 'allows the same clock time on different days' do
    replace([
              { weekday: 2, starts_at: '09:00', ends_at: '13:00' },
              { weekday: 3, starts_at: '09:00', ends_at: '13:00' }
            ])

    expect(professional.hours.count).to eq(2)
  end

  it 'keeps the week untouched when one range in the batch overlaps' do
    replace([{ weekday: 1, starts_at: '09:00', ends_at: '18:00' }])

    expect do
      replace([
                { weekday: 2, starts_at: '09:00', ends_at: '13:00' },
                { weekday: 2, starts_at: '10:00', ends_at: '18:00' }
              ])
    end.to raise_error(described_class::Overlap)
    expect(professional.hours.reload.pluck(:weekday)).to eq([1])
  end

  it 'drops a row the screen left blank rather than failing the save' do
    replace([
              { weekday: 1, starts_at: '09:00', ends_at: '18:00' },
              { weekday: 2, starts_at: '', ends_at: '' }
            ])

    expect(professional.hours.count).to eq(1)
  end
end

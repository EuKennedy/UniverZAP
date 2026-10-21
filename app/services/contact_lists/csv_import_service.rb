require 'csv'

# Importa telefones de um CSV (ou de uma coluna colada) para uma lista.
# Aceita vírgula ou ponto e vírgula, com ou sem cabeçalho: em cada linha, a
# primeira célula com cara de telefone é o número e a primeira célula com
# letras é o nome. O telefone passa pelo mesmo normalizador do disparo
# (Broadcasts::PhoneNumber) e casa com contato existente com e sem o nono
# dígito — contato existente nunca é duplicado.
#
# `cold: true` — os contatos CRIADOS pela importação nascem sem consentimento
# para disparo (Contacts::BroadcastConsent), como os de grupo.
class ContactLists::CsvImportService
  MAX_ROWS = 5000
  INVALID_SAMPLE = 10

  def initialize(list, content, cold: false)
    @list = list
    @account = list.account
    @content = content.to_s.dup.force_encoding('UTF-8').scrub.delete_prefix('﻿')
    @cold = cold
    @result = { 'rows' => 0, 'added' => 0, 'created' => 0, 'invalid' => 0, 'invalid_sample' => [] }
  end

  def perform
    Contacts::BroadcastConsent.ensure_definition!(@account) if @cold
    ids = rows.filter_map { |name, phone| contact_for(name, phone)&.id }
    @result['added'] = ContactLists::MemberService.new(@list).add(ids.uniq)
    @list.update!(metadata: @list.metadata.merge('last_import' => @result.merge('at' => Time.current.to_i)))
    @result
  end

  private

  def rows
    CSV.parse(@content, col_sep: separator, liberal_parsing: true).first(MAX_ROWS).filter_map do |cells|
      cells = cells.map { |cell| cell.to_s.strip }
      next if cells.all?(&:blank?) || header?(cells)

      @result['rows'] += 1
      parse_row(cells)
    end
  rescue CSV::MalformedCSVError
    []
  end

  def parse_row(cells)
    raw_phone = cells.find { |cell| cell.gsub(/\D/, '').length >= 10 }
    phone = Broadcasts::PhoneNumber.normalize(raw_phone)
    return [cells.find { |cell| cell.match?(/\p{L}/) }, phone] if phone

    invalid!(cells.join(' ').truncate(40))
    nil
  end

  HEADER = /\A(nome|name|telefone|phone|celular|whatsapp|n[uú]mero)\z/i

  def header?(cells)
    @result['rows'].zero? && cells.any? { |cell| cell.match?(HEADER) }
  end

  def invalid!(sample)
    @result['invalid'] += 1
    @result['invalid_sample'] << sample if @result['invalid_sample'].length < INVALID_SAMPLE
  end

  def separator
    first_line = @content.lines.first.to_s
    first_line.count(';') > first_line.count(',') ? ';' : ','
  end

  def contact_for(name, phone)
    existing = @account.contacts.where(phone_number: Broadcasts::PhoneNumber.variants(phone)).order(:id).first
    return existing if existing

    attributes = @cold ? { Contacts::BroadcastConsent::ATTRIBUTE => false } : {}
    contact = @account.contacts.create!(name: name.presence || phone, phone_number: phone, custom_attributes: attributes)
    @result['created'] += 1
    contact
  rescue ActiveRecord::RecordInvalid
    invalid!(phone)
    nil
  end
end

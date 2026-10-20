# Puts the salon's real catalogue behind the two attributes the customer sheet
# and the Agendar dialog edit: `servico` (a list since the vertical template)
# and `profissional` (free text until now, a list from here on). Only the
# values change; the names the template gave the attributes stay.
#
# Add-ons are left out: they are bought on top of an attendance, never as one,
# and offering "hidratação extra" as the service of a booking is the mistake
# the agent API itself warns about.
class Belezaki::CatalogSyncService
  SERVICE_KEY = 'servico'.freeze
  PROFESSIONAL_KEY = 'profissional'.freeze

  def initialize(account:, catalog:)
    @account = account
    @catalog = catalog.with_indifferent_access
  end

  def perform
    return { synced: false } unless @catalog[:status] == 'ok'

    services = names(@catalog[:services].reject { |row| row['is_addon'] })
    professionals = names(@catalog[:professionals])
    update_definition(SERVICE_KEY, services)
    update_definition(PROFESSIONAL_KEY, professionals)
    stamp
    { synced: true, services: services.size, professionals: professionals.size }
  end

  private

  def names(rows)
    Array(rows).reject { |row| row['active'] == false }.map { |row| row['name'].to_s.strip }.reject(&:blank?).uniq.sort
  end

  def update_definition(key, values)
    definition = @account.custom_attribute_definitions.find_or_initialize_by(attribute_key: key, attribute_model: 'conversation_attribute')
    definition.attribute_display_name ||= I18n.t("belezaki.catalog.#{key}")
    definition.attribute_display_type = 'list'
    definition.attribute_values = values
    definition.save!
  end

  def stamp
    hook = Belezaki::TenantResolver.hook(@account)
    hook&.update!(settings: hook.settings.merge('catalog_synced_at' => Time.current.iso8601))
  end
end

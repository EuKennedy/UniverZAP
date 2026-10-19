namespace :vertical_templates do
  desc 'Seed Vertical/VerticalStatus rows from lib/vertical_templates/templates/*.yml (idempotent)'
  task seed: :environment do
    # Super Admin "Apply vertical template" lists Vertical rows, not the YAML
    # files, so a fresh install had an empty dropdown until this ran. Safe to
    # re-run: existing verticals keep their key, statuses are matched by title.
    names = {
      'beauty_salon' => 'Salão de beleza',
      'ecommerce' => 'E-commerce',
      'food_delivery' => 'Delivery e restaurantes',
      'healthcare_clinic' => 'Clínicas e consultórios',
      'real_estate' => 'Imobiliárias'
    }

    Dir[Rails.root.join('lib/vertical_templates/templates/*.yml')].sort.each do |path|
      key = File.basename(path, '.yml')
      template = YAML.safe_load(File.read(path))
      vertical = Vertical.find_or_create_by!(key: key) { |v| v.name = names.fetch(key, key.humanize) }

      Array(template['labels']).each_with_index do |label, position|
        status = vertical.vertical_statuses.find_or_initialize_by(title: label['title'])
        status.assign_attributes(
          color: label['color'],
          description: label['description'],
          position: position,
          closes_conversation: label['closes_conversation'] == true
        )
        status.save!
      end

      puts "#{key}: #{vertical.vertical_statuses.count} status"
    end
  end
end

class UpdateUniverzapLogoPaths < ActiveRecord::Migration[7.1]
  LOGO_PATHS = {
    'LOGO' => '/brand-assets/logo.png',
    'LOGO_DARK' => '/brand-assets/logo_dark.png',
    'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.png'
  }.freeze

  def up
    LOGO_PATHS.each do |name, path|
      record = InstallationConfig.find_by(name: name)
      record ? record.update!(value: path) : InstallationConfig.create!(name: name, value: path)
    end
  end

  def down
    LOGO_PATHS.each_key do |name|
      InstallationConfig.find_by(name: name)&.update!(value: "/brand-assets/#{name.downcase}.svg")
    end
  end
end

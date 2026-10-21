# UniverZAP: the look of a workspace in the account switcher and settings.
# An uploaded cover wins over the theme; with neither, the front end derives a
# gradient from the account name. The theme names map to Tailwind classes in
# dashboard/helper/workspaceCover.js — keep both lists in sync.
module AccountWorkspaceCover
  extend ActiveSupport::Concern

  COVER_THEMES = %w[
    brand aurora sunset ocean berry ember orchid graphite
    solid_teal solid_iris solid_ruby solid_amber solid_violet solid_slate
  ].freeze
  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_COVER_SIZE = 5.megabytes
  MAX_LOGO_SIZE = 2.megabytes

  included do
    has_one_attached :cover
    has_one_attached :logo

    store_accessor :settings, :cover_theme

    validates :cover_theme, inclusion: { in: COVER_THEMES }, allow_nil: true
    validate :acceptable_cover_image, if: -> { attachment_changes.key?('cover') }
    validate :acceptable_logo_image, if: -> { attachment_changes.key?('logo') }
  end

  def cover_url
    workspace_image_url(cover, resize_to_fill: [960, 320])
  end

  def logo_url
    workspace_image_url(logo, resize_to_fill: [256, 256])
  end

  private

  def workspace_image_url(attachment, transformation)
    return '' unless attachment.attached? && attachment.representable?

    Rails.application.routes.url_helpers.url_for(attachment.representation(transformation))
  end

  def acceptable_cover_image
    validate_workspace_image(:cover, MAX_COVER_SIZE)
  end

  def acceptable_logo_image
    validate_workspace_image(:logo, MAX_LOGO_SIZE)
  end

  def validate_workspace_image(name, max_size)
    attachment = public_send(name)
    return unless attachment.attached?

    errors.add(name, 'is too big') if attachment.byte_size > max_size
    errors.add(name, 'filetype not supported') unless ALLOWED_IMAGE_TYPES.include?(attachment.content_type)
  end
end

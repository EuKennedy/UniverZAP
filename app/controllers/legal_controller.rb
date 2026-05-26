# LGPD §9: public-facing legal pages. No authentication, no session, no
# cookies set. The version constants in Legal::Versions are also exposed
# as meta tags so crawlers / archivers see the published version date.
class LegalController < ActionController::Base # rubocop:disable Rails/ApplicationController
  layout false

  def terms
    @version = Legal::Versions::TERMS
    @changelog = Legal::Versions::TERMS_CHANGELOG
  end

  def privacy
    @version = Legal::Versions::PRIVACY
    @changelog = Legal::Versions::PRIVACY_CHANGELOG
  end
end

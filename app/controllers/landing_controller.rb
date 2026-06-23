# Public marketing landing page. No authentication, no session, no cookies.
# Self-contained HTML (own <style>/<script>), Montserrat, brand greens,
# liquid-glass aesthetic, alternating dark/light sections.
class LandingController < ActionController::Base # rubocop:disable Rails/ApplicationController
  layout false

  def show; end
end

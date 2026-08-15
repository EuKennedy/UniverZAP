# Public marketing landing page. No authentication, no session, no cookies.
# Self-contained HTML (own <style>/<script>), Montserrat, brand greens,
# liquid-glass aesthetic, alternating dark/light sections.
class LandingController < ActionController::Base # rubocop:disable Rails/ApplicationController
  layout false

  def show; end

  def lpteste; end

  # ZapGrup, o produto comercial, na mesma linguagem visual do UniverZAP.
  # Página própria e não um layout compartilhado: são dois produtos, e mexer na
  # LP de um nunca pode repintar a do outro.
  def zapgrup; end
end

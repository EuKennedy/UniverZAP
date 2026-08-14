# The sidebar layout a super admin builds, for the whole installation.
#
# There is no read action: the layout ships with the page in `window.globalConfig`
# like every other installation setting, so rendering the sidebar costs no
# request. This exists only so the organiser screen can save.
class Api::V1::SidebarLayoutController < Api::BaseController
  before_action :ensure_super_admin

  def update
    config = InstallationConfig.find_or_initialize_by(name: 'SIDEBAR_LAYOUT')
    config.value = layout_param
    config.save!
    # InstallationConfig clears the global cache after commit, so the next page
    # load already serves the new menu.
    render json: { layout: config.value }
  end

  private

  # Stored whole, never merged: the screen always sends the complete layout, so
  # a group deleted there has to disappear here rather than survive a merge.
  #
  # `permit!` is deliberate. The shape is open by design — one key per menu item,
  # and menu items are added by us over time — so an allow-list would have to be
  # edited every time we ship a tab, and forgetting would silently drop that
  # item's placement. Nothing here is ever executed or used as a lookup; it is
  # read back as data by `applyLayout`, which ignores anything it does not
  # recognise.
  def layout_param
    params.require(:layout).permit!.to_h
  end

  # The tab hides itself in the dashboard, but a hidden tab is convenience, not
  # authorisation: this endpoint rewrites the menu of every tenant.
  def ensure_super_admin
    render_unauthorized('Super admin privileges required') unless current_user.is_a?(SuperAdmin)
  end
end

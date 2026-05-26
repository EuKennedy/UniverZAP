# Compat shim: devise_token_auth 1.2.5 still calls `resource_class(mapping)`
# from its `SetUserByToken#set_user_by_token` concern, but devise 4.9.4's
# `DeviseController#resource_class` (and the matching helper) are defined
# with zero arguments. The mismatch fires every time devise's own
# `prepend_before_action :require_no_authentication` filter on Sessions /
# Passwords / Registrations / Confirmations / Unlocks etc. evaluates
# `signed_in?` → `current_user` → `set_user_by_token(nil)` →
# `resource_class(nil)` → `ArgumentError (wrong number of arguments
# (given 1, expected 0))`. Result: every devise non-API screen
# (super_admin sign-in, password reset, mailer previews) 500s before the
# action runs.
#
# We `prepend` a tiny module on both `DeviseController` and
# `Devise::Controllers::Helpers` so the method silently accepts an
# optional mapping symbol. `super()` is forwarded explicitly with no
# args to keep devise's original lookup intact. Idempotent — a future
# devise upgrade that fixes this upstream will simply override the
# behaviour and our module will become a no-op.
module DeviseResourceClassCompat
  def resource_class(mapping = nil)
    if mapping
      devise_mapping = Devise.mappings[mapping]
      return devise_mapping.to if devise_mapping
    end
    super()
  end
end

Rails.application.config.after_initialize do
  DeviseController.prepend(DeviseResourceClassCompat) if defined?(DeviseController)
  Devise::Controllers::Helpers.prepend(DeviseResourceClassCompat) if defined?(Devise::Controllers::Helpers)
end

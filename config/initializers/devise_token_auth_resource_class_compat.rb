# Compat shim: devise_token_auth 1.2.5 still calls `resource_class(mapping)`
# from its `SetUserByToken#set_user_by_token` concern, but devise 4.9.4's
# `DeviseController#resource_class` (and the matching helper) are defined
# with zero arguments. The mismatch fires every time devise's own
# `prepend_before_action :require_no_authentication` filter evaluates
# `signed_in?` → `current_user` → `set_user_by_token(nil)` →
# `resource_class(nil)` → `ArgumentError`. Result: every devise non-API
# screen (super_admin sign-in, password reset, mailers) 500s before the
# action runs.
#
# We patch THREE layers so we cannot be defeated by load order:
#
# 1. `DeviseController` — primary class devise_controller.rb:63 lives in.
# 2. `Devise::Controllers::Helpers` — module mixed into ActionController::Base
#    via Devise's railtie; some helper-only call sites resolve here.
# 3. `DeviseTokenAuth::Concerns::SetUserByToken` — the actual caller. We
#    rewrite `set_user_by_token` to invoke `resource_class()` with no args
#    so it tolerates any future devise version too.
#
# This file is excluded from RuboCop (see .rubocop.yml AllCops/Exclude)
# because it is, by design, a vendor compat shim with multiple sibling
# modules and conditional constant-presence checks that would otherwise
# fight the project's default cops for zero behavioural gain.
module DeviseResourceClassCompat
  def resource_class(mapping = nil)
    if mapping
      devise_mapping = Devise.mappings[mapping]
      return devise_mapping.to if devise_mapping
    end

    super()
  end
end

module DeviseTokenAuthSetUserByTokenCompat
  def resource_class(mapping = nil)
    return super(mapping) if mapping

    super()
  end
end

Rails.application.config.after_initialize do
  if defined?(DeviseController)
    DeviseController.prepend(DeviseResourceClassCompat)
  end

  if defined?(Devise::Controllers::Helpers)
    Devise::Controllers::Helpers.prepend(DeviseResourceClassCompat)
  end

  if defined?(DeviseTokenAuth::Concerns::SetUserByToken)
    DeviseTokenAuth::Concerns::SetUserByToken.prepend(DeviseTokenAuthSetUserByTokenCompat)
  end
end

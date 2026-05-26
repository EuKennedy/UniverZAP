# Compat shim: devise_token_auth 1.2.5 still calls `resource_class(mapping)`
# from its `SetUserByToken#set_user_by_token` concern, but devise 4.9.4's
# helpers (both `DeviseController#resource_class` and
# `Devise::Controllers::Helpers#resource_class`) are now defined with zero
# arguments. The mismatch surfaces every time a Devise-based controller
# outside the JSON API stack (SuperAdmin sign-in, /favicon, legal pages)
# triggers the helper — Rails returns 500 with
# `ArgumentError (wrong number of arguments (given 1, expected 0))` before
# the action even runs.
#
# We widen both definitions so they accept either calling convention:
#   - no args  → original devise behaviour (`devise_mapping.to`)
#   - a Symbol → resolve the configured Devise mapping for that scope
#
# Applied at `after_initialize` so devise gems are guaranteed loaded; the
# patch is idempotent (no-op if the method already accepts an argument), so
# a future devise upgrade that fixes this upstream will not collide.
Rails.application.config.after_initialize do
  patch = lambda do |target, instance_method_name|
    method = target.instance_method(instance_method_name)
    next if method.arity != 0 # already widened

    original = method
    target.module_eval do
      define_method(instance_method_name) do |mapping = nil|
        if mapping
          devise_mapping = Devise.mappings[mapping]
          next devise_mapping.to if devise_mapping
        end
        original.bind(self).call
      end
    end
  end

  patch.call(Devise::Controllers::Helpers, :resource_class) if defined?(Devise::Controllers::Helpers)
  patch.call(DeviseController, :resource_class) if defined?(DeviseController)
end

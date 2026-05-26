# Compat shim: devise_token_auth 1.2.5 still calls `resource_class(mapping)`
# from `SetUserByToken#set_user_by_token`, but devise 4.9.4's
# Devise::Controllers::Helpers#resource_class is defined with zero arguments.
# The mismatch surfaces every time a non-API controller (SuperAdmin sign-in
# page, the cookie/legal pages, etc.) accidentally triggers the helper —
# Rails returns 500 with `ArgumentError (wrong number of arguments (given 1,
# expected 0))`.
#
# We widen the helper so it tolerates either calling convention:
#   - no args  → original devise lookup (`devise_mapping.to`)
#   - a Symbol → resolve the configured Devise mapping for that scope
# This keeps devise's contract intact for happy-path callers while making
# devise_token_auth's optimistic `resource_class(mapping)` calls work.
Rails.application.config.to_prepare do
  helpers = Devise::Controllers::Helpers
  already_patched = helpers.instance_method(:resource_class).arity != 0
  unless already_patched
    helpers.module_eval do
      alias_method :_zero_arg_resource_class, :resource_class

      def resource_class(mapping = nil)
        if mapping
          devise_mapping = Devise.mappings[mapping]
          return devise_mapping.to if devise_mapping
        end
        _zero_arg_resource_class
      end
    end
  end
end

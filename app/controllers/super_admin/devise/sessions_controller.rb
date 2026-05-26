# frozen_string_literal: true

class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  # SuperAdmin login lives outside the dashboard API auth stack. Skip the
  # devise_token_auth filter so its `resource_class(mapping)` call cannot
  # collide with devise 4.9.4's zero-arg helper signature.
  skip_before_action :set_user_by_token, raise: false

  def new
    self.resource = resource_class.new(sign_in_params)
  end

  def create
    redirect_to(super_admin_session_path, flash: { error: @error_message }) && return unless valid_credentials?

    sign_in(:super_admin, @super_admin)
    flash.discard
    redirect_to super_admin_users_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  def valid_credentials?
    @super_admin = SuperAdmin.find_by!(email: params[:super_admin][:email])
    raise StandardError, 'Invalid Password' unless @super_admin.valid_password?(params[:super_admin][:password])

    true
  rescue StandardError => e
    Rails.logger.error e.message
    @error_message = 'Invalid credentials. Please try again.'
    false
  end
end

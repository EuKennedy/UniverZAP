class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show; end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
    @user.account_users.find_by(account_id: profile_params[:account_id]).update(active_at: Time.now.utc)
    head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  # LGPD Art. 8º — registra aceite explícito da versão atual de termos +
  # privacidade. Front-end manda { terms_version, privacy_version } e o
  # backend grava o par + timestamp.
  def accept_terms
    @user.update!(
      accepted_terms_version: params[:terms_version] || Legal::Versions::TERMS,
      accepted_privacy_version: params[:privacy_version] || Legal::Versions::PRIVACY,
      accepted_at: Time.current
    )
    head :ok
  end

  # LGPD Art. 18 V (portabilidade) — exporta um JSON com todos os dados
  # diretos do titular. Conversation/Message payload é resumido por volume.
  def lgpd_export
    payload = Lgpd::UserExportService.new(@user).call
    send_data payload.to_json,
              type: 'application/json',
              disposition: 'attachment',
              filename: "univerzap-export-#{@user.id}-#{Time.current.to_i}.json"
  end

  # LGPD Art. 18 VI (eliminação) — apaga o User e tudo que é ON DELETE
  # CASCADE. Workspaces órfãos (último admin saindo) ficam intactos: o
  # operador faz transferência manual antes via /super_admin.
  def lgpd_delete
    Lgpd::UserDeleteService.new(@user).call
    head :ok
  end

  private

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end

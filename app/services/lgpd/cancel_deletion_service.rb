class Lgpd::CancelDeletionService
  def initialize(user)
    @user = user
  end

  def call
    return false if @user.scheduled_for_deletion_at.blank?

    @user.update!(scheduled_for_deletion_at: nil)
    Lgpd::DeletionMailer.cancelled(@user).deliver_later
    true
  end
end

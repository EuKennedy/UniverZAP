# Per-row dispatcher used by the `POST /tasks/bulk` endpoint. We loop
# and rescue per id (instead of running the whole list in a single
# transaction) so that a row the user can't mutate doesn't roll back
# the rest. Returns `{ ok: <count>, failed: [{ id, reason }] }`.
class Tasks::BulkAction
  def initialize(account:, user:, ids:, action:, payload: {})
    @account = account
    @user = user
    @ids = ids
    @action = action
    @payload = payload || {}
  end

  def call
    ok = 0
    failed = []
    @account.tasks.where(id: @ids).find_each do |task|
      authorize_and_apply!(task)
      ok += 1
    rescue Pundit::NotAuthorizedError
      failed << { id: task.id, reason: 'forbidden' }
    rescue StandardError => e
      failed << { id: task.id, reason: e.message }
    end
    missing = @ids - @account.tasks.where(id: @ids).pluck(:id)
    missing.each { |id| failed << { id: id, reason: 'not_found' } }
    { ok: ok, failed: failed }
  end

  private

  def authorize_and_apply!(task)
    policy = TaskPolicy.new(user_context, task)
    raise Pundit::NotAuthorizedError unless authorized?(policy)

    apply!(task)
  end

  def user_context
    @user_context ||= {
      user: @user,
      account: @account,
      account_user: @account.account_users.find_by(user_id: @user.id)
    }
  end

  def authorized?(policy)
    case @action
    when 'complete'     then policy.complete?
    when 'delete'       then policy.destroy?
    when 'assign'       then policy.assign?
    when 'set_urgency'  then policy.update?
    end
  end

  def apply!(task)
    case @action
    when 'complete'    then task.update!(status: :done, completed_at: Time.current)
    when 'delete'      then task.destroy!
    when 'assign'      then apply_assign!(task)
    when 'set_urgency' then task.update!(urgency: @payload[:urgency] || @payload['urgency'])
    end
  end

  def apply_assign!(task)
    user_id = @payload[:user_id] || @payload['user_id']
    raise ArgumentError, 'missing user_id' if user_id.blank?

    membership = @account.account_users.find_by(user_id: user_id)
    raise ActiveRecord::RecordNotFound, 'user not in account' if membership.blank?

    task.task_assignees.find_or_create_by!(user_id: user_id)
  end
end

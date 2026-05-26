class Api::V1::Accounts::KanbanTaskTimeEntriesController < Api::V1::Accounts::BaseController
  before_action :fetch_task
  before_action :check_authorization

  def index
    @entries = @task.time_entries.includes(:user)
  end

  def start
    close_open_entry_for_current_user
    @entry = @task.time_entries.create!(user: Current.user, started_at: Time.current)
    Kanban::ActivityLogger.log_time_started(@task, Current.user)
    render :show
  end

  def stop
    @entry = @task.time_entries.open.find_by!(user: Current.user)
    @entry.update!(ended_at: Time.current)
    Kanban::ActivityLogger.log_time_stopped(@task, Current.user, @entry.duration_seconds)
    render :show
  end

  private

  def fetch_task
    @task = Current.account.kanban_tasks.find(params[:kanban_task_id])
  end

  def close_open_entry_for_current_user
    open_entry = @task.time_entries.open.find_by(user: Current.user)
    return unless open_entry

    open_entry.update!(ended_at: Time.current)
  end
end

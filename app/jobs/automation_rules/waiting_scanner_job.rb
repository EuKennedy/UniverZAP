class AutomationRules::WaitingScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    AutomationRules::WaitingScanner.new.perform
  end
end

# frozen_string_literal: true

# Main Module for logging different types of logs
module ScriptLogger
  def log_info(message)
    logger.info(message)
  end

  def log_error(message)
    logger.error(message)
  end

  private

  def logger
    @logger ||= Logger.new($stdout)
  end
end

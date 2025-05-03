# frozen_string_literal: true

# Main Module for logging different types of logs
module ScriptLogger
  LOGGER = Logger.new($stdout)

  def log_info(message)
    LOGGER.info(message)
  end

  def log_error(message)
    LOGGER.error(message)
  end
end

module ScriptLogger
  LOGGER = Logger.new($stdout)

  def log_info(message)
    LOGGER.info(message)
  end

  def log_error(message)
    LOGGER.error(message)
  end
end
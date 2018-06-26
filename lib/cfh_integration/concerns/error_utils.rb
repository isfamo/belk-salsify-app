module ErrorUtils
  extend self

  def format_error(error)
    return unless error
    message = error.try(:message) ? error.message : error
    message[0..5_000]
  end

end

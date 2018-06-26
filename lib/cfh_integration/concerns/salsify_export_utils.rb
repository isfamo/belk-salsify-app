module SalsifyExportUtils

  def str_to_bool(value)
    if ['yes', 'Yes'].include?(value)
      return true
    elsif ['no', 'No'].include?(value)
      return false
    else
      return value
    end
  end

  # The online-to date ends before midnight (“2016-12-16T23:59:00”)
  def dw_online_to(value)
    return unless value
    date = Time.new(*value.split('-'), 23, 59, 0, '-05:00').utc
    dw_formatted_date(date)
  end

  # The online-from date starts at midnight (“2016-12-16T00:00:00”)
  def dw_online_from(value)
    return unless value
    date = Time.new(*value.split('-'), 0, 0, 0, '-05:00').utc
    dw_formatted_date(date)
  end

  def dw_formatted_date(date)
    date.strftime('%Y-%m-%dT%H:%M:%S')
  end

end

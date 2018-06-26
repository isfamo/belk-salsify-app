class IphChangeJob < Struct.new(:org_id, :webhook_name, :styles)

  def perform
    IphMapping::IphChange.process(org_id, webhook_name, styles)
  rescue Exception => e
    puts "$IPH_CHANGE$ ERROR in IphChangeJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end

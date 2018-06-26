class SkuIphChangeJob < Struct.new(:org_id, :webhook_name, :style_by_id, :skus)

  def perform
    IphMapping::IphChange.process_skus(org_id, webhook_name, style_by_id, skus)
  rescue Exception => e
    puts "$IPH_CHANGE$ ERROR in SkuIphChangeJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end

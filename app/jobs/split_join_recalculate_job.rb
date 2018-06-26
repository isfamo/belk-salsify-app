class SplitJoinRecalculateJob < Struct.new(:product_ids)

  STAMP = '$SPLIT_JOIN$'.freeze
  SLEEP_BEFORE_START = 60.freeze

  def perform
    begin
      puts "#{STAMP} SplitJoinRecalculateJob queued for #{product_ids.length} involved products, sleeping for #{SLEEP_BEFORE_START} secs before starting..."
      sleep SLEEP_BEFORE_START
      require_rel '../../lib/new_product_grouping/**/*.rb'
      puts "#{STAMP} Starting SplitJoinRecalculateJob for #{product_ids.length} products"
      NewProductWorkflow::Recalculate.recalculate(product_ids)
      puts "#{STAMP} SplitJoinRecalculateJob done!"
    rescue Exception => e
      puts "#{STAMP} ERROR in SplitJoinRecalculateJob: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

end

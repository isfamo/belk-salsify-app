class RemovedGroupingsJob < Struct.new(:products)

  STAMP = '$GROUPINGS$'.freeze

  def perform
    require_rel '../../lib/groupings/**/*.rb'
    puts "#{STAMP} RemovedGroupingsJob queued for #{products.length} products..."
    Groupings::GroupingHandler.removed_groupings(products)
    puts "#{STAMP} RemovedGroupingsJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in RemovedGroupingsJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end

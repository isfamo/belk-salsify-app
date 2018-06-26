class ModifiedGroupingsJob < Struct.new(:products)

  STAMP = '$GROUPINGS$'.freeze

  def perform
    require_rel '../../lib/groupings/**/*.rb'
    puts "#{STAMP} ModifiedGroupingsJob queued for #{products.length} products..."
    Groupings::GroupingHandler.modified_groupings(products)
    puts "#{STAMP} ModifiedGroupingsJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in ModifiedGroupingsJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end

class NewGroupingsJob < Struct.new(:products)

  STAMP = '$GROUPINGS$'.freeze

  def perform
    require_rel '../../lib/groupings/**/*.rb'
    puts "#{STAMP} NewGroupingsJob queued for #{products.length} products..."
    Groupings::GroupingHandler.new_groupings(products)
    puts "#{STAMP} NewGroupingsJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in NewGroupingsJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end

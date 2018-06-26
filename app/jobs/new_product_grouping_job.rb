class NewProductGroupingJob < Struct.new(:new_products)
  
    def perform
      puts 'New product created...'
      puts 'Evaluating if we need to generate a new group ID'
      begin
        puts "Generating ids for #{new_products.count} new products"
        require_rel '../../lib/new_product_grouping/*.rb'
        NewProductWorkflow::Worker.run(new_products)
        puts "Finished generating ids!"
      rescue Exception => e
        puts "Error with new product workflow: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end
    
end
  
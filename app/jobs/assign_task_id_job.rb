class AssignTaskIdJob < Struct.new(:product_ids, :client)

  def perform
    puts "$$ Assign task ID job queued for #{product_ids.length} products..."
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      product_ids.each do |product_id|
        puts "$$ Generating task ID for product #{product_id}"
        task = RRDonnelley::RRDConnector.generate_task(product_id)
        puts "$$ Generated task ID is #{task.id}, updating product..."
        client.update_product(product_id, {
          PROPERTY_RRD_TASK_ID => task.id,
          PROPERTY_SKU_IMAGES_UPDATED => true
        })
        puts "$$ Done adding task ID"
      end
    rescue Exception => e
      puts "$$ ERROR while assigning task IDs: #{e.message}"
    end
  end

end

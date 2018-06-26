class NewSampleProvidedJob < Struct.new(:payload_alert_name, :products)
  include Muffin::SalsifyClient

  PIM_API_USER = ENV['PIM_API_USER']
  PIM_API_PASS = ENV['PIM_API_PASS']
  PIM_API_HOST_URL = ENV['PIM_API_URL']

  RIGHT_SAMPLE_AVAIL = 'Right Sample Available?'.freeze

  def perform
    # This should exist on a SKU level, so just operate at the product level given.

    puts "New sample provided flagged to yes..."
    begin
      products.each do |product|
        # Since at the SKU level this should really only be a single product, but technically needs to account this way due to the way webhooks send it in
        if product[RIGHT_SAMPLE_AVAIL] == false
          # If that is set, then clear it
          puts "Clearing #{RIGHT_SAMPLE_AVAIL} on product ID #{product['salsify:id']}"
          client.update_product(product['salsify:id'], { RIGHT_SAMPLE_AVAIL => nil })
        else
          puts "Product ID #{product['salsify:id']} was triggered by New Sample Provided, but #{RIGHT_SAMPLE_AVAIL} was not set to No, so changing nothing, carry on."
        end
      end
    rescue Exception => e
      puts "$$ ERROR while running New Sample Provided Job job: #{e.message}"
    end
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end

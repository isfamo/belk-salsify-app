class ClearPipImageApprovedJob < Struct.new(:payload_alert_name, :products)
  include Muffin::SalsifyClient

  PROPERTY_PIP_IMAGE_APPROVED = 'PIP Image Approved?'.freeze
  PRODUCT_ID = 'product_id'.freeze

  def perform
    puts "Clear PIP Image Approved? job queued for products #{products.map { |product| product['salsify:id'] }.join(', ')}..."
    begin
      products.each do |product|
        parent_id = product['salsify:parent_id']
        client.update_product(parent_id, { PROPERTY_PIP_IMAGE_APPROVED => nil })
      end
    rescue Exception => e
      puts "$$ ERROR while running clear PIP Image Approved? job: #{e.message}"
    end
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end

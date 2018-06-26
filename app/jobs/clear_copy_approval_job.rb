class ClearCopyApprovalJob < Struct.new(:payload_alert_name, :products)
  include Muffin::SalsifyClient

  PROPERTY_COPY_APPROVED = 'Copy Approval State'.freeze
  PROPERTY_PENDING_BASE_PUBLISH = 'isBasePublishPending'.freeze
  PROPERTY_SENT_TO_DW_TIMESTAMP = 'sentToWebDate'.freeze
  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze

  MAX_IDS_PER_FILTER = 50.freeze

  def perform
    puts "$COPY$ Clear copy approval job queued for products #{products.map { |product| product['salsify:id'] }.join(', ')}..."
    product_updates_by_id.each do |product_id, updates|
      begin
        client.update_product(product_id, updates)
      rescue Exception => e
        puts "$COPY$ ERROR while running clear copy approval job for product #{product_id}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end
    puts "$COPY$ Done with copy approval job!"
  end

  def product_updates_by_id
    @product_updates_by_id ||= products.map do |product|
      updates = { PROPERTY_COPY_APPROVED => nil }
      updates[PROPERTY_PENDING_BASE_PUBLISH] = true if style_has_pending_skus[product['salsify:id']]
      [product['salsify:id'], updates]
    end
  end

  def style_has_pending_skus
    @style_has_pending_skus ||= child_skus_by_parent_id.map do |style_id, skus|
      [style_id, skus.any? { |sku| sku[PROPERTY_SENT_TO_DW_TIMESTAMP].nil? }]
    end.to_h
  end

  def child_skus_by_parent_id
    @child_skus_by_parent_id ||= begin
      puts "$COPY$ Quering child skus for updated styles"
      t = Time.now
      map = products.each_slice(MAX_IDS_PER_FILTER).map do |style_batch|
        filter.find_children(
          parent_ids: style_batch.map { |style| style['salsify:id'] },
          selections: [PROPERTY_PARENT_PRODUCT_ID, PROPERTY_SENT_TO_DW_TIMESTAMP]
        )
      end.flatten.group_by do |partial_sku|
        partial_sku[PROPERTY_PARENT_PRODUCT_ID]
      end
      puts "$COPY$ Retrieved #{map.values.flatten.length} skus in #{(Time.now - t).round(1)} sec"
      map
    end
  end

  def filter
    @filter ||= SalsifyFilter.new(client)
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end

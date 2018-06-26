module SiblingSkus
  extend self

  def update_skus
    puts "updating #{product.sku} sibling products #{skus_with_same_color.join(',')}..."
    skus_with_same_color.each  { |sku| salsify_client.update_product(sku, sku_body) }
  end

  def skus_with_same_color
    @skus_with_same_color ||= sibling_products.select do |salsify_product|
      salsify_product.nrfColorCode == product.color_code
    end.map(&:product_id)
  end

  # bulk get can only support upto 100 products at a time
  def sibling_products
    all_related_skus.each_slice(75).flat_map { |product_ids| salsify_client.products(product_ids) }
  end

  def all_related_skus
    salsify_client.product_relatives(product.sku).siblings.map(&:id) + [ product.sku ]
  end

end

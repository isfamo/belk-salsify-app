class Sku < ApplicationRecord
  belongs_to :parent_product

  scope :product_ids, -> {
    Sku.pluck(:product_id)
  }

  scope :skus_with_parents, -> {
    Sku.where("parent_id IS NOT NULL").pluck(:product_id)
  }

  scope :sku_to_parent_hash, -> (skus) {
    Sku.where(product_id: skus).pluck(:product_id, :parent_id).to_h
  }

  scope :with_recent_inventory, -> (date = Date.today) {
    date = DateTime.strptime("#{date.to_s} 2359 #{CMAEvent.offset}", '%Y-%m-%d %H%M %z') - 15.day
    where("inventory_reset_date > ?", date).pluck(:product_id)
  }

end

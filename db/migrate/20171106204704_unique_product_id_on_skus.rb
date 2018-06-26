class UniqueProductIdOnSkus < ActiveRecord::Migration[5.0]
  def change
    remove_index :skus, :product_id
    add_index :skus, :product_id, unique: true
  end
end

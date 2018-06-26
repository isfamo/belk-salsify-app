class CreateParentProducts < ActiveRecord::Migration[5.0]
  def change
    create_table :parent_products do |t|
      t.string :product_id
      t.date :first_inventory_date
      t.timestamps
    end
    add_index :parent_products, :product_id, using: :btree
  end
end

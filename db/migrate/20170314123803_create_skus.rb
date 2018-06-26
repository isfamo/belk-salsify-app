class CreateSkus < ActiveRecord::Migration[5.0]
  def change
    create_table :skus do |t|
      t.string :product_id
      t.string :parent_id
      t.belongs_to :parent_product, index: true, foreign_key: true
      t.timestamps
    end

    add_index :skus, :parent_id, using: :btree
    add_index :skus, :product_id, using: :btree
  end
end

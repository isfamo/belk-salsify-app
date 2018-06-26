class RemoveSomeMoreUnusedIndicies < ActiveRecord::Migration[5.0]
  def change
    remove_index :skus, :parent_product_id
    remove_index :salsify_sql_nodes, :sid
  end
end

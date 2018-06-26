class RemoveUnusedIndicies < ActiveRecord::Migration[5.0]
  def change
    remove_index :skus, :parent_id
  end
end

class AddParentIdToCMAEvent < ActiveRecord::Migration[5.0]
  def change
    add_column :cma_events, :parent_id, :string
  end
end

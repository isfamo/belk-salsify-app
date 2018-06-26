class AddIndexToCMAEvent < ActiveRecord::Migration[5.0]
  def change
    add_index :cma_events, [:sku_code, :adevent, :event_id], unique: true
    change_column :cma_events, :start_date, :datetime, null: false
    change_column :cma_events, :end_date, :datetime, null: false
  end
end

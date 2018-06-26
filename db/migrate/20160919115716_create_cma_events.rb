class CreateCMAEvents < ActiveRecord::Migration[5.0]
  def change
    create_table :cma_events do |t|
      t.string :sku_code
      t.string :vendor_upc
      t.integer :record_type
      t.string :event_id
      t.datetime :start_date
      t.datetime :end_date
      t.string :adevent
    end

    add_index :cma_events, :start_date, using: :btree
    add_index :cma_events, :end_date, using: :btree
  end
end

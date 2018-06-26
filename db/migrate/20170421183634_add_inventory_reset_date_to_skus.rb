class AddInventoryResetDateToSkus < ActiveRecord::Migration[5.0]
  def change
    add_column :skus, :inventory_reset_date, :date
  end
end

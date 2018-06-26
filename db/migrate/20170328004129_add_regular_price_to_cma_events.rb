class AddRegularPriceToCMAEvents < ActiveRecord::Migration[5.0]
  def change
    add_column :cma_events, :regular_price, :string
  end
end

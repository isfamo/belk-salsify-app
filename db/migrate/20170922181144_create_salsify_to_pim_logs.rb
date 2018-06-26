class CreateSalsifyToPimLogs < ActiveRecord::Migration[5.0]
  def change
    create_table :salsify_to_pim_logs do |t|
      t.text :product_id
      t.text :car_id
      t.text :status
      t.text :type
      t.datetime :dtstamp

      t.timestamps
    end
  end
end

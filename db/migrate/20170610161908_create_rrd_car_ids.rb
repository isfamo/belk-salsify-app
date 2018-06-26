class CreateRrdCarIds < ActiveRecord::Migration[5.0]
  def change
    create_table :rrd_car_ids do |t|
      t.string :product_id

      t.timestamps
    end
  end
  execute("ALTER SEQUENCE rrd_image_ids_id_seq START with 1000000 RESTART;")
end

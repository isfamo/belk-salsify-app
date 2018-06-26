class CreateRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    create_table :rrd_requested_samples do |t|
      t.string :product_id
      t.string :color_id
      t.date :completed_at

      t.timestamps
    end
    execute("ALTER SEQUENCE rrd_image_ids_id_seq START with 1000000 RESTART;")
  end
end

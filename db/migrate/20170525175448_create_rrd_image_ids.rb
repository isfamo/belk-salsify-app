class CreateRrdImageIds < ActiveRecord::Migration[5.0]
  def change
    create_table :rrd_image_ids do |t|
      t.string :salsify_asset_id
      t.boolean :approved
      t.timestamps
    end
    execute("ALTER SEQUENCE rrd_image_ids_id_seq START with 1000000 RESTART;")
  end
end

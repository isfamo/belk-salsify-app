class CreateRrdDeletedImages < ActiveRecord::Migration[5.0]
  def change
    create_table :rrd_deleted_images do |t|
      t.string :file_name
      t.string :rrd_image_id

      t.timestamps
    end
  end
end

class AddFieldsToRrdImageId < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_image_ids, :product_id, :string
    add_column :rrd_image_ids, :color_code, :string
    add_column :rrd_image_ids, :shot_type, :string
    add_column :rrd_image_ids, :image_name, :string
  end
end

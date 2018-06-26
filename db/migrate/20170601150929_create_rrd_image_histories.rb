class CreateRrdImageHistories < ActiveRecord::Migration[5.0]
  def change
    create_table :rrd_image_histories do |t|
      t.string :image_id
      t.string :name
      t.date :date

      t.timestamps
    end
  end
end

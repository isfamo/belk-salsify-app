class CreateRrdTaskIds < ActiveRecord::Migration[5.0]
  def change
    create_table :rrd_task_ids do |t|
      t.string :product_id

      t.timestamps
    end
    execute("ALTER SEQUENCE rrd_task_ids_id_seq START with 1000000 RESTART;")
  end
end

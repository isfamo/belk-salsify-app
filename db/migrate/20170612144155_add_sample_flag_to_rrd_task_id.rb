class AddSampleFlagToRrdTaskId < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_task_ids, :is_sample, :boolean
  end
end

class RemoveIsSampleFromRrdTaskId < ActiveRecord::Migration[5.0]
  def change
    remove_column :rrd_task_ids, :is_sample, :boolean
  end
end

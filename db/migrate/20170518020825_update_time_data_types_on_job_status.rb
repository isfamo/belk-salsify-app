class UpdateTimeDataTypesOnJobStatus < ActiveRecord::Migration[5.0]
  def up
    remove_column :job_statuses, :start_time
    remove_column :job_statuses, :end_time
    add_column :job_statuses, :start_time, :datetime
    add_column :job_statuses, :end_time, :datetime
  end

  def down
    remove_column :job_statuses, :start_time
    remove_column :job_statuses, :end_time
    add_column :job_statuses, :start_time, :time
    add_column :job_statuses, :end_time, :time
  end
end

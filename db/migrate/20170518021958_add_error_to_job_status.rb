class AddErrorToJobStatus < ActiveRecord::Migration[5.0]
  def change
    add_column :job_statuses, :error, :string, default: 'None'
  end
end

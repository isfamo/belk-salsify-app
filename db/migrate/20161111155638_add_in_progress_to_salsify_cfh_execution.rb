class AddInProgressToSalsifyCfhExecution < ActiveRecord::Migration[5.0]
  def change
    add_column :salsify_cfh_executions, :in_progress, :bool, default: false
  end
end

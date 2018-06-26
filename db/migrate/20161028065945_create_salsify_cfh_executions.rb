class CreateSalsifyCfhExecutions < ActiveRecord::Migration[5.0]
  def change
    create_table :salsify_cfh_executions do |t|
      t.string :exec_type, default: "auto"

      t.timestamps
    end

    add_index :salsify_cfh_executions, :id, using: :btree

    add_column :salsify_sql_nodes, :salsify_cfh_execution_id, :integer
    add_foreign_key :salsify_sql_nodes, :salsify_cfh_executions
  end
end

class CreateCfhExecutionErrors < ActiveRecord::Migration[5.0]
  def change
    create_table :cfh_execution_errors do |t|
      t.integer :salsify_cfh_execution_id
      t.string :product_id, default: ''
      t.string :category_id, default: ''
      t.string :message, default: ''
      t.timestamps
    end

    add_index :cfh_execution_errors, :salsify_cfh_execution_id, using: :btree
    add_foreign_key :cfh_execution_errors, :salsify_cfh_executions
  end
end

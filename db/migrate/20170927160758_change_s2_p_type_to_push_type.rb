class ChangeS2PTypeToPushType < ActiveRecord::Migration[5.0]
  def change
    rename_column :salsify_to_pim_logs, :type, :push_type
  end
end

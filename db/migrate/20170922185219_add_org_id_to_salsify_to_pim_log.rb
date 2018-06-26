class AddOrgIdToSalsifyToPimLog < ActiveRecord::Migration[5.0]
  def change
    add_column :salsify_to_pim_logs, :org_id, :integer
  end
end

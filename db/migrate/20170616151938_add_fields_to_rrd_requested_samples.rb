class AddFieldsToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :of_or_sl, :string
    add_column :rrd_requested_samples, :turn_in_date, :date
    add_column :rrd_requested_samples, :silhouette_required, :boolean
    add_column :rrd_requested_samples, :instructions, :string
  end
end

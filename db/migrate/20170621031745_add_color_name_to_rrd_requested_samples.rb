class AddColorNameToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :color_name, :string
  end
end

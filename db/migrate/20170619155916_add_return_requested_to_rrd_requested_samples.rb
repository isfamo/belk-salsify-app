class AddReturnRequestedToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :return_requested, :boolean
  end
end

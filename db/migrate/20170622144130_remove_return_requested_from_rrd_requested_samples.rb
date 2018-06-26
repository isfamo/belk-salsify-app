class RemoveReturnRequestedFromRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    remove_column :rrd_requested_samples, :return_requested, :boolean
  end
end

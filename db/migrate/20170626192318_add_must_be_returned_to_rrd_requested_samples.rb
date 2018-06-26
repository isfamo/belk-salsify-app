class AddMustBeReturnedToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :must_be_returned, :boolean
  end
end

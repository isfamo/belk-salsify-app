class AddReturnInfoToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :return_to, :string
    add_column :rrd_requested_samples, :return_notes, :string
  end
end

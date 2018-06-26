class AddOhOrFvToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :on_hand_or_from_vendor, :string
  end
end

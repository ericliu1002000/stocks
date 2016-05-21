class AddDownloadTimesToStocks < ActiveRecord::Migration
  def change
    add_column :stocks, :download_times, :integer, default: 0
  end
end
